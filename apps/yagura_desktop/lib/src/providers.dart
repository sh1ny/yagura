/// Riverpod providers, keyed by daemon id (design D10).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'connection.dart';
import 'grpc_transport.dart';

/// M1 has one daemon: the dev-mode connection.
const String kDevDaemonId = 'dev';

/// The connection object of a daemon. Only the dev daemon can be created here;
/// tests override it with a connection over a fake transport.
final daemonConnectionProvider = Provider.family<DaemonConnection, String>((
  ref,
  daemonId,
) {
  final connection = DaemonConnection(id: daemonId, connect: GrpcTransport.new);
  ref.onDispose(connection.dispose);
  connection.start();
  return connection;
});

final connectionStatusProvider =
    StreamProvider.family<ConnectionStatus, String>(
      (ref, daemonId) =>
          ref.watch(daemonConnectionProvider(daemonId)).statusStream,
    );

final instancesProvider = StreamProvider.family<List<Instance>, String>(
  (ref, daemonId) =>
      ref.watch(daemonConnectionProvider(daemonId)).instancesStream,
);

final operationsProvider = StreamProvider.family<List<OperationState>, String>(
  (ref, daemonId) =>
      ref.watch(daemonConnectionProvider(daemonId)).operationsStream,
);
