import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
// The client decodes details with grpc's own copy of Any.
// ignore: implementation_imports
import 'package:grpc/src/generated/google/protobuf/any.pb.dart' show Any;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/api_server.dart';
import 'package:yagurad/src/api/instances_api.dart';
import 'package:yagurad/src/api/pressure.dart';
import 'package:yagurad/src/host/daemon.dart';

import 'daemon_support.dart';

/// A running API server on an ephemeral loopback port with generated clients,
/// shut down when the test ends.
class ApiHarness {
  ApiHarness._(this.daemon, this.server, this.channel, this.logLines)
    : system = pb.SystemClient(channel),
      plugins = pb.PluginsClient(channel),
      instances = pb.InstancesClient(channel),
      operations = pb.OperationsClient(channel),
      steam = pb.SteamClient(channel),
      logs = pb.LogsClient(channel);

  final Daemon daemon;
  final ApiServer server;
  final ClientChannel channel;

  /// What the server wrote to its incident log.
  final List<String> logLines;

  final pb.SystemClient system;
  final pb.PluginsClient plugins;
  final pb.InstancesClient instances;
  final pb.OperationsClient operations;
  final pb.SteamClient steam;
  final pb.LogsClient logs;

  /// Starts [daemon] (a fresh one on [env] when null) behind a server.
  static Future<ApiHarness> start(
    TestEnv env, {
    Daemon? daemon,
    WatchLimits watchLimits = const WatchLimits(),
    int requestLimit = maxRequestBytes,
    int responseLimit = maxResponseBytes,
  }) async {
    final d = daemon ?? await env.start();
    final lines = <String>[];
    final server = await ApiServer.serveDev(
      d,
      address: InternetAddress.loopbackIPv4,
      port: 0,
      logSink: lines.add,
      watchLimits: watchLimits,
      requestLimit: requestLimit,
      responseLimit: responseLimit,
    );
    final channel = ClientChannel(
      '127.0.0.1',
      port: server.port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    addTearDown(() async {
      await channel.terminate();
      await server.close();
    });
    return ApiHarness._(d, server, channel, lines);
  }

  /// A new connection to the server, closed when the test ends. Calls on it
  /// do not share HTTP/2 flow control with the harness's own channel.
  ClientChannel connect() {
    final other = ClientChannel(
      '127.0.0.1',
      port: server.port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    addTearDown(other.terminate);
    return other;
  }

  /// Creates a Valheim instance through the API.
  Future<pb.Instance> createValheim({String name = 'Friends'}) =>
      instances.createInstance(
        pb.CreateInstanceRequest(
          pluginId: 'valheim',
          name: name,
          settings: pb.JsonDocument(json: '{"serverName":"$name"}'),
        ),
      );
}

/// The `ErrorDetail` a failed call carried, null when it had none.
pb.ErrorDetail? errorDetailOf(GrpcError error) {
  for (final detail in error.details ?? const []) {
    if (detail is Any && detail.typeUrl.endsWith('/yagura.v1.ErrorDetail')) {
      return pb.ErrorDetail.fromBuffer(detail.value);
    }
  }
  return null;
}

/// Matches a failed call with [code] and an `ErrorDetail` whose reason is
/// [reason].
Matcher failsWithStatus(int code, String reason) => throwsA(
  isA<GrpcError>()
      .having((e) => e.code, 'code', code)
      .having((e) => errorDetailOf(e)?.reason, 'ErrorDetail.reason', reason),
);

/// The error [call] fails with; fails the test when it succeeds.
Future<GrpcError> failureOf(Future<Object?> call) async {
  try {
    await call;
  } on GrpcError catch (e) {
    return e;
  }
  fail('the call succeeded');
}

/// Reads [stream] until [count] items arrived or [timeout] passed.
Future<List<T>> take<T>(
  Stream<T> stream,
  int count, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final out = <T>[];
  final done = Completer<void>();
  final subscription = stream.listen(
    (item) {
      out.add(item);
      if (out.length >= count && !done.isCompleted) done.complete();
    },
    onError: (Object e, StackTrace s) {
      if (!done.isCompleted) done.completeError(e, s);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );
  try {
    await done.future.timeout(
      timeout,
      onTimeout: () => fail('timed out after ${out.length} of $count items'),
    );
  } finally {
    await subscription.cancel();
  }
  return out;
}
