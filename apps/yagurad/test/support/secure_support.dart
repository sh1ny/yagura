import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
// The tests open sockets from chosen source addresses.
// ignore: implementation_imports
import 'package:grpc/src/client/channel.dart' show ClientChannelBase;
// ignore: implementation_imports
import 'package:grpc/src/client/http2_connection.dart'
    show SocketTransportConnector;
import 'package:test/test.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/api_server.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/secret_store.dart';
import 'package:yagurad/src/security/security.dart';

import 'daemon_support.dart';
import 'secret_support.dart';

/// A clock the test moves: certificates, codes and throttles read it.
class TestClock {
  TestClock([DateTime? start])
    : _time = _whole(start ?? DateTime.now().toUtc());

  DateTime _time;

  // Certificates carry whole seconds, so the clock does too.
  static DateTime _whole(DateTime time) => DateTime.fromMillisecondsSinceEpoch(
    time.millisecondsSinceEpoch ~/ 1000 * 1000,
    isUtc: true,
  );

  DateTime get time => _time;

  set time(DateTime value) => _time = _whole(value);

  DateTime call() => _time;

  void advance(Duration by) => time = _time.add(by);
}

/// Client TLS credentials: [caPem] as the only trusted root, the daemon's
/// fixed [authority] as the name to verify, and optionally a client
/// certificate.
class MutualTlsCredentials extends ChannelCredentials {
  MutualTlsCredentials({
    required this.caPem,
    required String authority,
    this.certificate,
    this.key,
    this.chain = const [],
  }) : super.secure(authority: authority);

  final String caPem;
  final Uint8List? certificate;
  final EcKeyPair? key;
  final List<Uint8List> chain;

  @override
  SecurityContext? get securityContext {
    final context = SecurityContext()
      ..setAlpnProtocols(['grpc-exp', 'h2'], false)
      ..setTrustedCertificatesBytes(utf8.encode(caPem));
    if (certificate != null) {
      context
        ..useCertificateChainBytes(
          utf8.encode(
            [
              for (final c in [certificate!, ...chain]) certificatePem(c),
            ].join(),
          ),
        )
        ..usePrivateKeyBytes(utf8.encode(key!.privateKeyPem));
    }
    return context;
  }
}

/// A transport that connects from [sourceAddress], to look like another
/// remote address to the daemon.
class _SourceConnector extends SocketTransportConnector {
  _SourceConnector(super.host, super.port, super.options, this.sourceAddress);

  final InternetAddress sourceAddress;

  @override
  Future<Socket> initSocket(Object host, int port) =>
      Socket.connect(host, port, sourceAddress: sourceAddress);
}

/// A device that paired with the daemon.
class PairedDevice {
  PairedDevice._(
    this.harness,
    this.name,
    this.deviceId,
    this.key,
    this.certificate,
  );

  /// A device built from the answer of an Enroll call made by hand.
  factory PairedDevice.forTest(
    SecureHarness harness,
    String name,
    String deviceId,
    EcKeyPair key,
    Uint8List certificate,
  ) => PairedDevice._(harness, name, deviceId, key, certificate);

  final SecureHarness harness;
  final String name;
  final String deviceId;
  final EcKeyPair key;
  final Uint8List certificate;

  late final ClientChannelBase channel = harness.channelWith(
    certificate: certificate,
    key: key,
  );

  late final pb.SystemClient system = pb.SystemClient(channel);
  late final pb.PairingClient pairing = pb.PairingClient(channel);
  late final pb.InstancesClient instances = pb.InstancesClient(channel);
  late final pb.OperationsClient operations = pb.OperationsClient(channel);
  late final pb.SteamClient steam = pb.SteamClient(channel);
  late final pb.LogsClient logs = pb.LogsClient(channel);

  String get sha256 => Certificate.parse(certificate).sha256;

  /// A new connection that presents this device's certificate.
  ClientChannelBase connect() =>
      harness.channelWith(certificate: certificate, key: key);
}

/// A service-mode daemon behind a real TLS listener on a loopback port.
class SecureHarness {
  SecureHarness._(
    this.env,
    this.daemon,
    this.server,
    this.logLines,
    this.clock,
  );

  final TestEnv env;
  final Daemon daemon;
  final ApiServer server;
  final List<String> logLines;
  final TestClock clock;

  DaemonSecurity get security => daemon.security!;
  String get caPem => certificatePem(security.identity.caCertificate.der);
  String get authority => security.identity.authority;

  /// Starts a service-mode daemon on [env] and serves it over mutual TLS.
  /// [clock] starts the daemon at that time.
  static Future<SecureHarness> start(
    TestEnv env, {
    TestClock? clock,
    SecretProtector? secretProtector,
    Daemon? daemon,
    Future<ApiServer> Function(Daemon daemon, List<String> lines)? serve,
  }) async {
    final testClock = clock ?? TestClock();
    final d =
        daemon ??
        await env.start(
          serviceMode: true,
          secretProtector: secretProtector ?? FakeSecretProtector(serviceSid),
          clock: testClock.call,
        );
    final lines = <String>[];
    final server =
        await (serve?.call(d, lines) ??
            ApiServer.serveSecure(
              d,
              address: InternetAddress.loopbackIPv4,
              port: 0,
              logSink: lines.add,
            ));
    final harness = SecureHarness._(env, d, server, lines, testClock);
    addTearDown(() async {
      for (final channel in harness._channels) {
        await channel.terminate();
      }
      await server.close();
    });
    return harness;
  }

  final _channels = <ClientChannelBase>[];

  /// A channel that trusts the daemon CA, presents no certificate unless
  /// given one, and verifies the daemon's fixed name. [from] makes the
  /// connection come from another loopback address.
  ClientChannelBase channelWith({
    Uint8List? certificate,
    EcKeyPair? key,
    List<Uint8List> chain = const [],
    String? caPem,
    InternetAddress? from,
  }) {
    final options = ChannelOptions(
      credentials: MutualTlsCredentials(
        caPem: caPem ?? this.caPem,
        authority: authority,
        certificate: certificate,
        key: key,
        chain: chain,
      ),
      // A refused handshake should fail the call, not hang it.
      connectTimeout: const Duration(seconds: 10),
    );
    final ClientChannelBase channel;
    if (from == null) {
      channel = ClientChannel(
        InternetAddress.loopbackIPv4.address,
        port: server.port,
        options: options,
      );
    } else {
      channel = ClientTransportConnectorChannel(
        _SourceConnector(
          InternetAddress.loopbackIPv4.address,
          server.port,
          options,
          from,
        ),
        options: options,
      );
    }
    _channels.add(channel);
    return channel;
  }

  ClientChannelBase untrustedChannel() => untrustedChannelTo(server.port);

  /// Issues a pairing code on the daemon.
  String issueCode() => security.pairing.issueCode().code;

  /// What a client does at pairing: fetches the CA with `Pairing.Info`,
  /// pins it, and enrolls a new key under [name] with [code] (a fresh one
  /// when null).
  Future<PairedDevice> pair(
    String name, {
    String? code,
    InternetAddress? from,
  }) async {
    final info = await pb.PairingClient(untrustedChannel())
        .info(pb.PairingInfoRequest());
    expect(
      info.caFingerprintSha256,
      sha256Hex(info.caCertificateDer),
      reason: 'the daemon reports the fingerprint of the CA it sends',
    );
    final key = generateKeyPair();
    final enroll =
        await pb.PairingClient(
          channelWith(from: from, caPem: certificatePem(info.caCertificateDer)),
        ).enroll(
          pb.EnrollRequest(
            code: code ?? issueCode(),
            deviceName: name,
            csrDer: buildCsr(key: key, commonName: name),
          ),
        );
    return PairedDevice._(
      this,
      name,
      enroll.deviceId,
      key,
      Uint8List.fromList(enroll.clientCertificateDer),
    );
  }

  /// A CA-signed client certificate for a key that never enrolled.
  (Uint8List, EcKeyPair) unenrolledCertificate({
    DateTime? notBefore,
    DateTime? notAfter,
  }) {
    final key = generateKeyPair();
    final now = clock.time;
    return (
      issueClientCertificate(
        issuerKey: security.identity.caKey,
        issuer: security.identity.caCertificate,
        subjectKey: key.publicKey,
        commonName: 'nobody',
        notBefore: notBefore ?? now.subtract(const Duration(hours: 1)),
        notAfter: notAfter ?? now.add(const Duration(days: 365)),
      ),
      key,
    );
  }
}

/// A channel for the unauthenticated calls of pairing: TLS without
/// verification of the server (the client has no CA yet) and without a
/// client certificate.
ClientChannel untrustedChannelTo(int port) {
  final channel = ClientChannel(
    InternetAddress.loopbackIPv4.address,
    port: port,
    options: const ChannelOptions(
      credentials: ChannelCredentials.secure(
        onBadCertificate: allowBadCertificates,
      ),
    ),
  );
  addTearDown(channel.terminate);
  return channel;
}

/// A raw call of [path] with [request] bytes; completes with the first
/// response or fails with the call's error.
Future<List<int>> rawCall(
  ClientChannelBase channel,
  String path, {
  List<int> request = const [],
  Duration timeout = const Duration(seconds: 10),
}) {
  final call = channel.createCall(
    ClientMethod<List<int>, List<int>>(path, (r) => r, (r) => r),
    Stream.value(request),
    CallOptions(timeout: timeout),
  );
  return call.response.first;
}

/// The reason of the `ErrorDetail` a failed call carries.
String? reasonOf(GrpcError error) {
  for (final detail in error.details ?? const []) {
    try {
      // ignore: avoid_dynamic_calls
      final typeUrl = (detail as dynamic).typeUrl as String;
      if (typeUrl.endsWith('/yagura.v1.ErrorDetail')) {
        return pb.ErrorDetail.fromBuffer(
          // ignore: avoid_dynamic_calls
          (detail as dynamic).value as List<int>,
        ).reason;
      }
    } on Object {
      continue;
    }
  }
  return null;
}
