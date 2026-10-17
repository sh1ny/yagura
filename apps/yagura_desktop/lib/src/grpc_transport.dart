import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:protobuf/well_known_types/google/protobuf/any.pb.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'transport.dart';

/// Default address of the daemon's development connection.
const String kDevHost = '127.0.0.1';
const int kDevPort = 7443;

/// [DaemonTransport] over a plaintext loopback gRPC channel (dev mode).
final class GrpcTransport implements DaemonTransport {
  GrpcTransport({String host = kDevHost, int port = kDevPort})
    : _channel = ClientChannel(
        host,
        port: port,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      ) {
    _system = SystemClient(_channel);
    _instances = InstancesClient(_channel);
    _operations = OperationsClient(_channel);
    _logs = LogsClient(_channel);
    _plugins = PluginsClient(_channel);
  }

  final ClientChannel _channel;
  late final SystemClient _system;
  late final InstancesClient _instances;
  late final OperationsClient _operations;
  late final LogsClient _logs;
  late final PluginsClient _plugins;

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

/// Reduces a [GrpcError] and its packed `yagura.v1.ErrorDetail` (if any) to a
/// [DaemonCallException].
DaemonCallException toCallException(GrpcError error) {
  ErrorDetail? detail;
  for (final GeneratedMessage message in error.details ?? const []) {
    if (message is Any && message.typeUrl.endsWith('yagura.v1.ErrorDetail')) {
      detail = ErrorDetail.fromBuffer(message.value);
    }
  }
  return DaemonCallException(
    code: error.code,
    reason: detail?.reason ?? '',
    message: detail != null && detail.message.isNotEmpty
        ? detail.message
        : (error.message ?? ''),
    fieldViolations: {
      for (final v in detail?.fieldViolations ?? const <FieldViolation>[])
        v.field_1: v.description,
    },
  );
}
