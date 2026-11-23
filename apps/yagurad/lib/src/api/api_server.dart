import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/daemon.dart';
import '../security/auth_gate.dart';
import '../security/identity.dart';
import 'firewall_api.dart';
import 'gated_service.dart';
import 'instances_api.dart';
import 'logs_api.dart';
import 'mods_api.dart';
import 'operations_api.dart';
import 'pairing_api.dart';
import 'plugins_api.dart';
import 'pressure.dart';
import 'reflection.dart';
import 'secure_listener.dart';
import 'service_support.dart';
import 'steam_api.dart';
import 'stub_apis.dart';
import 'system_api.dart';

/// The daemon's gRPC server: the services of the daemon version, the stubs of
/// the services this version does not build, and server reflection, all
/// behind an [AuthGate]. Dev mode serves plaintext on loopback with
/// [AllowAllGate]; service mode serves mutual TLS with [DeviceAuthGate].
class ApiServer {
  ApiServer._(
    this._server,
    this.address, {
    this._listener,
    this._daemon,
    ListenerBinder? binder,
    this._log,
  }) : _binder = binder ?? SecureListener.bind;

  final YaguraGrpcServer _server;
  final Daemon? _daemon;
  final ListenerBinder _binder;
  final LogSink? _log;
  SecureListener? _listener;
  Timer? _rotation;
  final _failed = Completer<void>();
  var _closed = false;

  /// The address the listener is bound to.
  final InternetAddress address;

  /// The bound port (the real one when the request was port 0).
  int get port => _listener?.port ?? _server.port!;

  /// Completes with an error when the server can no longer listen: the
  /// certificate rotation closed the listener and neither the new nor the
  /// old certificate could be served again (design D4). The daemon exits, so
  /// the service manager restarts it.
  Future<void> get failed => _failed.future;

  /// Serves [daemon] plaintext on [address]:[port]. Plaintext is for dev mode
  /// only; the caller has checked that [address] is loopback.
  static Future<ApiServer> serveDev(
    Daemon daemon, {
    required InternetAddress address,
    required int port,
    LogSink? logSink,
    WatchLimits watchLimits = const WatchLimits(),
    int requestLimit = maxRequestBytes,
    int responseLimit = maxResponseBytes,
  }) async {
    final log = logSink ?? ((line) => stderr.writeln('yagurad: $line'));
    const gate = AllowAllGate();
    final server = _create(
      [
        SystemApi(daemon, log, devMode: !gate.authenticates),
        PluginsApi(daemon, log),
        InstancesApi(daemon, log, watchLimits: watchLimits),
        OperationsApi(daemon, log, watchLimits: watchLimits),
        LogsApi(daemon, log),
        PairingStub(),
        SteamApi(daemon, log),
        ModsApi(daemon, log),
        RconStub(),
        FirewallStub(),
      ],
      gate,
      requestLimit: requestLimit,
      responseLimit: responseLimit,
    );
    await server.serve(address: address, port: port);
    return ApiServer._(server, address);
  }

  /// Serves [daemon] over mutual TLS (design D1, D2): a certificate-less
  /// handshake completes, and the gate decides on every call. [binder] opens
  /// the listener; tests replace it to make a bind fail.
  static Future<ApiServer> serveSecure(
    Daemon daemon, {
    required InternetAddress address,
    required int port,
    LogSink? logSink,
    WatchLimits watchLimits = const WatchLimits(),
    int requestLimit = maxRequestBytes,
    int responseLimit = maxResponseBytes,
    ListenerBinder? binder,
    Duration rotationInterval = const Duration(days: 1),
  }) async {
    final security = daemon.security;
    if (security == null) {
      throw YaguraException(
        'service_mode_required',
        'the secure listener needs the identity of a service-mode daemon',
      );
    }
    final log = logSink ?? ((line) => stderr.writeln('yagurad: $line'));
    final server = _create(
      [
        SystemApi(daemon, log, devMode: !security.gate.authenticates),
        PluginsApi(daemon, log),
        InstancesApi(daemon, log, watchLimits: watchLimits),
        OperationsApi(daemon, log, watchLimits: watchLimits),
        LogsApi(daemon, log),
        PairingApi(daemon, security, log),
        SteamApi(daemon, log),
        ModsApi(daemon, log),
        RconStub(),
        // The stub stays where the daemon manages no rules (a host without a
        // firewall).
        if (daemon.firewall != null)
          FirewallApi(daemon, log)
        else
          FirewallStub(),
      ],
      security.gate,
      requestLimit: requestLimit,
      responseLimit: responseLimit,
    );
    final bind = binder ?? SecureListener.bind;
    final identity = security.identity;
    final listener = await bind(
      server,
      address,
      port,
      _context(identity.caCertificate, identity.serverMaterial),
    );
    final api = ApiServer._(
      server,
      address,
      listener: listener,
      daemon: daemon,
      binder: bind,
      log: log,
    );
    try {
      await api.checkCertificateRotation();
    } on Object {
      await api.close();
      rethrow;
    }
    api._rotation = Timer.periodic(rotationInterval, (_) {
      unawaited(api.checkCertificateRotation());
    });
    return api;
  }

  static YaguraGrpcServer _create(
    List<Service> services,
    AuthGate gate, {
    required int requestLimit,
    required int responseLimit,
  }) {
    final index = DescriptorIndex(pb.yaguraDescriptorSet);
    final names = <String>[
      for (final service in services) service.$name,
      'grpc.reflection.v1.ServerReflection',
      'grpc.reflection.v1alpha.ServerReflection',
    ];
    return YaguraGrpcServer.create(
      services: [
        for (final service in [
          ...services,
          ReflectionApi(index, () => names),
          ReflectionV1AlphaApi(index, () => names),
        ])
          GatedService(service, gate),
      ],
      keepAliveOptions: const ServerKeepAliveOptions(
        minIntervalBetweenPingsWithoutData: Duration(seconds: 20),
        maxBadPings: 2,
      ),
      requestLimit: requestLimit,
      responseLimit: responseLimit,
    );
  }

  /// TLS with the daemon CA as the only trusted root: a client certificate
  /// from another CA, or an expired one, fails the handshake (design D1).
  static SecurityContext _context(Certificate ca, ServerMaterial server) =>
      SecurityContext()
        ..setAlpnProtocols(['grpc-exp', 'h2'], true)
        ..setTrustedCertificatesBytes(utf8.encode(certificatePem(ca.der)))
        ..useCertificateChainBytes(
          utf8.encode(certificatePem(server.certificate.der)),
        )
        ..usePrivateKeyBytes(utf8.encode(server.key.privateKeyPem));

  /// Replaces the server certificate when under 30 days remain: a new one is
  /// issued, the listener is closed and served again with it, and the
  /// connections that used the old one are dropped (design D4). When the new
  /// bind fails the old certificate is served again and notice
  /// `server_cert_rotation_failed` is raised until the next attempt; when
  /// that bind fails too [failed] completes with an error.
  Future<void> checkCertificateRotation() async {
    final listener = _listener;
    final daemon = _daemon;
    final security = daemon?.security;
    if (listener == null || daemon == null || security == null || _closed) {
      return;
    }
    final identity = security.identity;
    if (!identity.serverCertificateDue()) return;
    final material = identity.issueServer();
    final port = listener.port;
    await listener.close(dropConnections: true);
    try {
      final rebound = await _binder(
        _server,
        address,
        port,
        _context(identity.caCertificate, material),
      );
      if (_closed) {
        // close() ran while the bind was pending: nobody else will close it.
        await rebound.close(dropConnections: true);
        return;
      }
      _listener = rebound;
      identity.adopt(material);
      daemon.runtimeNotices.removeWhere(
        (n) => n.step == 'server_cert_rotation_failed',
      );
      _log?.call(
        'server certificate replaced; it ends '
        '${identity.serverCertificate.notAfter.toIso8601String()}',
      );
    } on Object catch (e) {
      final message =
          'the new server certificate could not be served ($e); the old one '
          'is served again and the rotation is retried';
      // One notice, however many days the failure lasts. Nothing reads the
      // runtime notices yet (no health field carries them), so the log is
      // where an administrator finds out.
      daemon.runtimeNotices
        ..removeWhere((n) => n.step == 'server_cert_rotation_failed')
        ..add(StartupNotice('server_cert_rotation_failed', message));
      _log?.call('server_cert_rotation_failed: $message');
      try {
        final restored = await _binder(
          _server,
          address,
          port,
          _context(identity.caCertificate, identity.serverMaterial),
        );
        if (_closed) {
          await restored.close(dropConnections: true);
          return;
        }
        _listener = restored;
      } on Object catch (e2) {
        _listener = null;
        if (!_failed.isCompleted) {
          _failed.completeError(
            YaguraException(
              'listener_unavailable',
              'the listener closed for the certificate rotation could not be '
                  'opened again on port $port: $e2',
            ),
          );
          // Whoever awaits `failed` handles it; an unobserved failure is
          // not an uncaught error.
          unawaited(_failed.future.catchError((Object _) {}));
        }
      }
    }
  }

  /// Stops listening and ends the calls in flight.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _rotation?.cancel();
    if (_listener case final listener?) {
      await listener.close(dropConnections: true);
    } else {
      await _server.shutdown();
    }
  }
}
