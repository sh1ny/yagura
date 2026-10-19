/// Riverpod providers, keyed by daemon id (design D10, D13).
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'connection.dart';
import 'daemon_link.dart';
import 'daemon_record.dart';
import 'dialer.dart';
import 'keychain.dart';
import 'registry.dart';

export 'daemon_record.dart' show kDevDaemonId;

/// The OS keychain holding device keys, certificates and CAs.
final keychainProvider = Provider<Keychain>((ref) => SecureStorageKeychain());

/// Where the daemon list is kept.
final daemonListStoreProvider = Provider<DaemonListStore>(
  (ref) => FileDaemonListStore(
    File('${supportDirectory()}${Platform.pathSeparator}daemons.json'),
  ),
);

final daemonDialerProvider = Provider<DaemonDialer>(
  (ref) => const GrpcDialer(),
);

/// The current time; tests pin it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Waits between reconnect attempts; tests release the waits by hand.
final reconnectDelayProvider = Provider<Delay>((ref) => Future<void>.delayed);

/// Waits between the daily certificate checks.
final renewalDelayProvider = Provider<Delay>((ref) => Future<void>.delayed);

/// Whether the registry lists the loopback development daemon: not in a
/// release build.
final devDaemonEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment(
    'YAGURA_DEV_DAEMON',
    defaultValue: !kReleaseMode,
  ),
);

final daemonRegistryProvider =
    NotifierProvider<DaemonRegistry, List<DaemonRecord>>(DaemonRegistry.new);

/// The connection object of a daemon. Tests override it with a connection
/// over a fake transport.
final daemonConnectionProvider = Provider.family<DaemonConnection, String>((
  ref,
  daemonId,
) {
  final link = DaemonLink(
    daemonId: daemonId,
    record: () => ref
        .read(daemonRegistryProvider)
        .where((d) => d.id == daemonId)
        .firstOrNull,
    keychain: ref.read(keychainProvider),
    dialer: ref.read(daemonDialerProvider),
    now: ref.read(clockProvider),
    delay: ref.read(renewalDelayProvider),
  );
  final connection = DaemonConnection(
    id: daemonId,
    connect: link.open,
    afterConnect: link.keepFresh,
    delay: ref.read(reconnectDelayProvider),
    now: ref.read(clockProvider),
  );
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
