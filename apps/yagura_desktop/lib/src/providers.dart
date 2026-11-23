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

/// What is wrong with the saved daemon list.
final class ListProblem {
  const ListProblem(
    this.message, {
    this.canDiscard = false,
    this.discardDetail = '',
    this.canDiscardCopy = false,
    this.savingRefused = false,
  });

  final String message;

  /// Whether unreadable entries can be discarded (see
  /// [DaemonRegistry.discardUnreadable]), and what the confirmation says.
  final bool canDiscard;
  final String discardDetail;

  /// Whether a kept copy of a damaged list can be discarded (see
  /// [DaemonRegistry.discardDamagedCopy]).
  final bool canDiscardCopy;

  /// Whether the list cannot be saved, so no daemon can be paired.
  final bool savingRefused;
}

/// The daemons whose clock looks wrong: a certificate they just issued is
/// already due for renewal.
final daemonClockSuspectProvider =
    NotifierProvider<DaemonClockSuspects, Set<String>>(DaemonClockSuspects.new);

class DaemonClockSuspects extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void mark(String id, {required bool suspect}) {
    if (state.contains(id) == suspect) return;
    state = suspect ? {...state, id} : ({...state}..remove(id));
  }
}

/// The problem with the saved daemon list, null when it was read in full.
final daemonListProblemProvider =
    NotifierProvider<DaemonListProblem, ListProblem?>(DaemonListProblem.new);

class DaemonListProblem extends Notifier<ListProblem?> {
  @override
  ListProblem? build() => null;

  // ignore: use_setters_to_change_properties
  void report(ListProblem? problem) => state = problem;
}

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
    onRenewed: (at) =>
        ref.read(daemonRegistryProvider.notifier).markRenewed(daemonId, at),
    onClockSuspect: ({required bool suspect}) {
      if (!ref.mounted) return;
      ref
          .read(daemonClockSuspectProvider.notifier)
          .mark(daemonId, suspect: suspect);
    },
  );
  final connection = DaemonConnection(
    id: daemonId,
    connect: link.open,
    afterConnect: link.keepFresh,
    delay: ref.read(reconnectDelayProvider),
    now: ref.read(clockProvider),
    lastSeenBefore: () => ref
        .read(daemonRegistryProvider)
        .where((d) => d.id == daemonId)
        .firstOrNull
        ?.lastSeen,
    onSeen: (seen) =>
        ref.read(daemonRegistryProvider.notifier).markSeen(daemonId, seen),
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

/// Every prompt pending on a daemon, whoever started the operation.
final promptsProvider = StreamProvider.family<List<PendingPrompt>, String>(
  (ref, daemonId) =>
      ref.watch(daemonConnectionProvider(daemonId)).promptsStream,
);

/// The daemon's `settings_invalid` notices by instance id.
final settingsInvalidProvider =
    StreamProvider.family<Map<String, String>, String>(
      (ref, daemonId) =>
          ref.watch(daemonConnectionProvider(daemonId)).settingsInvalidStream,
    );
