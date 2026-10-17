import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../host/daemon.dart';
import 'instances_api.dart';
import 'logs_api.dart';
import 'operations_api.dart';
import 'plugins_api.dart';
import 'pressure.dart';
import 'reflection.dart';
import 'service_support.dart';
import 'stub_apis.dart';
import 'system_api.dart';

/// The daemon's gRPC server: the M1 services, the stubs of the services this
/// version does not build, and (in dev mode) server reflection.
class ApiServer {
  ApiServer._(this._server, this.address);

  final YaguraGrpcServer _server;

  /// The address the listener is bound to.
  final InternetAddress address;

  /// The bound port (the real one when the request was port 0).
  int get port => _server.port!;

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
    final services = <Service>[
      SystemApi(daemon, log, devMode: true),
      PluginsApi(daemon, log),
      InstancesApi(daemon, log, watchLimits: watchLimits),
      OperationsApi(daemon, log, watchLimits: watchLimits),
      LogsApi(daemon, log),
      PairingStub(),
      SteamStub(),
      ModsStub(),
      RconStub(),
      FirewallStub(),
    ];
    final index = DescriptorIndex(pb.yaguraDescriptorSet);
    final names = <String>[
      for (final service in services) service.$name,
      'grpc.reflection.v1.ServerReflection',
      'grpc.reflection.v1alpha.ServerReflection',
    ];
    final server = YaguraGrpcServer.create(
      services: [
        ...services,
        ReflectionApi(index, () => names),
        ReflectionV1AlphaApi(index, () => names),
      ],
      keepAliveOptions: const ServerKeepAliveOptions(
        minIntervalBetweenPingsWithoutData: Duration(seconds: 20),
        maxBadPings: 2,
      ),
      requestLimit: requestLimit,
      responseLimit: responseLimit,
    );
    await server.serve(address: address, port: port);
    return ApiServer._(server, address);
  }

  /// Stops listening and ends the calls in flight.
  Future<void> close() => _server.shutdown();
}
