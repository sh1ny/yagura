import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:protobuf/well_known_types/google/protobuf/any.pb.dart';
import 'package:yagura_pki/yagura_pki.dart' show certificatePem;
import 'package:yagura_proto/yagura_proto.dart';

import 'credentials.dart';
import 'dialer.dart';
import 'transport.dart';

/// Default address of the daemon's development connection.
const String kDevHost = '127.0.0.1';
const int kDevPort = 7443;

/// [DaemonTransport] over a plaintext loopback gRPC channel (dev mode).
final class GrpcTransport implements DaemonTransport {
  GrpcTransport({String host = kDevHost, int port = kDevPort})
    : this._(
        ClientChannel(
          host,
          port: port,
          options: const ChannelOptions(
            credentials: ChannelCredentials.insecure(),
          ),
        ),
      );

  /// Mutual TLS: [credentials].caDer is the only trusted root and the server
  /// is checked against [authority], whatever [host] says (design D13).
  GrpcTransport.secure({
    required String host,
    required int port,
    required String authority,
    required DeviceCredentials credentials,
  }) : this._(
         ClientChannel(
           host,
           port: port,
           options: ChannelOptions(
             credentials: PinnedChannelCredentials(
               authority: authority,
               caDer: credentials.caDer,
               certificateDer: credentials.certificateDer,
               keyPem: credentials.keyPem,
             ),
           ),
         ),
       );

  GrpcTransport._(this._channel) {
    _system = SystemClient(_channel);
    _instances = InstancesClient(_channel);
    _operations = OperationsClient(_channel);
    _logs = LogsClient(_channel);
    _plugins = PluginsClient(_channel);
    _pairing = PairingClient(_channel);
  }

  final ClientChannel _channel;
  late final SystemClient _system;
  late final InstancesClient _instances;
  late final OperationsClient _operations;
  late final LogsClient _logs;
  late final PluginsClient _plugins;
  late final PairingClient _pairing;

  /// Client deadline for unary calls (docs/protocol.md).
  static const _unaryTimeout = Duration(seconds: 30);

  CallOptions get _unary => CallOptions(timeout: _unaryTimeout);

  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on GrpcError catch (e) {
      throw toCallException(e);
    }
  }

  Stream<T> _stream<T>(Stream<T> Function() open) async* {
    try {
      yield* open();
    } on GrpcError catch (e) {
      throw toCallException(e);
    }
  }

  @override
  Future<DaemonInfo> getInfo() =>
      _call(() => _system.getInfo(GetInfoRequest(), options: _unary));

  @override
  Stream<InstanceEvent> watchInstances() =>
      _stream(() => _instances.watchInstances(WatchInstancesRequest()));

  @override
  Future<Instance> getInstance(String instanceId) => _call(
    () => _instances.getInstance(
      GetInstanceRequest(instanceId: instanceId),
      options: _unary,
    ),
  );

  @override
  Future<EnrollResponse> renewCertificate(Uint8List csrDer) => _call(
    () => _pairing.renewCertificate(
      RenewCertificateRequest(csrDer: csrDer),
      options: _unary,
    ),
  );

  @override
  Future<Instance> createInstance(CreateInstanceRequest request) =>
      _call(() => _instances.createInstance(request, options: _unary));

  @override
  Future<Instance> updateSettings(UpdateSettingsRequest request) =>
      _call(() => _instances.updateSettings(request, options: _unary));

  @override
  Future<Instance> setSecret(SetSecretRequest request) =>
      _call(() => _instances.setSecret(request, options: _unary));

  @override
  Future<Operation> install(String instanceId) => _call(
    () => _instances.install(
      LifecycleRequest(instanceId: instanceId),
      options: _unary,
    ),
  );

  @override
  Future<Operation> start(String instanceId) => _call(
    () => _instances.start(
      LifecycleRequest(instanceId: instanceId),
      options: _unary,
    ),
  );

  @override
  Future<Operation> stop(String instanceId) => _call(
    () => _instances.stop(
      LifecycleRequest(instanceId: instanceId),
      options: _unary,
    ),
  );

  @override
  Future<Operation> deleteInstance(DeleteInstanceRequest request) =>
      _call(() => _instances.deleteInstance(request, options: _unary));

  @override
  Stream<OperationEvent> watchOperation(
    String operationId, {
    int afterSequence = 0,
  }) => _stream(
    () => _operations.watchOperation(
      WatchOperationRequest(
        operationId: operationId,
        afterSequence: Int64(afterSequence),
      ),
    ),
  );

  @override
  Future<List<PluginSummary>> listPlugins() async {
    final response = await _call(
      () => _plugins.listPlugins(ListPluginsRequest(), options: _unary),
    );
    return response.plugins;
  }

  @override
  Future<PluginDetail> getPlugin(String pluginId) => _call(
    () => _plugins.getPlugin(
      GetPluginRequest(pluginId: pluginId),
      options: _unary,
    ),
  );

  @override
  Stream<LogBatch> backlog(String instanceId) => _stream(
    () => _logs.backlog(BacklogRequest(instanceId: instanceId, lines: 5000)),
  );

  @override
  Stream<LogBatch> follow(String instanceId) =>
      _stream(() => _logs.follow(FollowRequest(instanceId: instanceId)));

  @override
  Future<void> close() => _channel.shutdown();
}

/// A TLS context that trusts [caDer] and nothing else (no system roots), and
/// presents [certificateDer] with [keyPem] when given (mutual TLS).
SecurityContext pinnedSecurityContext({
  required List<int> caDer,
  List<int>? certificateDer,
  String? keyPem,
}) {
  final context = SecurityContext()
    ..setAlpnProtocols(['grpc-exp', 'h2'], false)
    ..setTrustedCertificatesBytes(utf8.encode(certificatePem(caDer)));
  if (certificateDer != null && keyPem != null) {
    context
      ..useCertificateChainBytes(utf8.encode(certificatePem(certificateDer)))
      ..usePrivateKeyBytes(utf8.encode(keyPem));
  }
  return context;
}

/// Channel credentials over [pinnedSecurityContext], checking the server
/// against the fixed [authority] (`yagurad-<daemon-id>`).
final class PinnedChannelCredentials extends ChannelCredentials {
  PinnedChannelCredentials({
    required String authority,
    required this.caDer,
    this.certificateDer,
    this.keyPem,
  }) : super.secure(authority: authority);

  final Uint8List caDer;
  final Uint8List? certificateDer;
  final String? keyPem;

  @override
  SecurityContext? get securityContext => pinnedSecurityContext(
    caDer: caDer,
    certificateDer: certificateDer,
    keyPem: keyPem,
  );
}

/// [PairingChannel] over gRPC: the two calls that need no client certificate.
final class GrpcPairingChannel implements PairingChannel {
  /// Without [pinnedCa] the server certificate is not verified (the caller
  /// checks the CA it returns); with it, only that CA is trusted.
  GrpcPairingChannel({
    required String host,
    required int port,
    Uint8List? pinnedCa,
    String? authority,
  }) : _channel = ClientChannel(
         host,
         port: port,
         options: ChannelOptions(
           credentials: pinnedCa == null
               ? const ChannelCredentials.secure(
                   onBadCertificate: allowBadCertificates,
                 )
               : PinnedChannelCredentials(
                   authority: authority ?? host,
                   caDer: pinnedCa,
                 ),
         ),
       ) {
    _client = PairingClient(_channel);
  }

  final ClientChannel _channel;
  late final PairingClient _client;

  static const _timeout = Duration(seconds: 30);

  @override
  Future<PairingInfo> info() async {
    try {
      return await _client.info(
        PairingInfoRequest(),
        options: CallOptions(timeout: _timeout),
      );
    } on GrpcError catch (e) {
      throw toCallException(e);
    }
  }

  @override
  Future<EnrollResponse> enroll(EnrollRequest request) async {
    try {
      return await _client.enroll(
        request,
        options: CallOptions(timeout: _timeout),
      );
    } on GrpcError catch (e) {
      throw toCallException(e);
    }
  }

  @override
  Future<void> close() => _channel.shutdown();
}

/// Reduces a [GrpcError] and its packed `yagura.v1.ErrorDetail` (if any) to a
/// [DaemonCallException].
DaemonCallException toCallException(GrpcError error) {
  ErrorDetail? detail;
  for (final GeneratedMessage message in error.details ?? const []) {
    if (message is Any && message.typeUrl.endsWith('yagura.v1.ErrorDetail')) {
      detail = ErrorDetail.fromBuffer(message.value);
    }
  }
  // The TLS stack reports a server certificate that does not chain to the
  // pinned CA (or does not carry the fixed name) as a failed handshake.
  final tlsRefused =
      detail == null &&
      error.code == StatusCode.unavailable &&
      (error.message ?? '').contains('CERTIFICATE_VERIFY_FAILED');
  return DaemonCallException(
    code: error.code,
    reason: tlsRefused ? 'server_ca_mismatch' : detail?.reason ?? '',
    message: detail != null && detail.message.isNotEmpty
        ? detail.message
        : (error.message ?? ''),
    fieldViolations: {
      for (final v in detail?.fieldViolations ?? const <FieldViolation>[])
        v.field_1: v.description,
    },
  );
}
