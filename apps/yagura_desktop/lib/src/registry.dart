/// The daemon registry: which daemons the client knows (design D13).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credentials.dart';
import 'daemon_record.dart';
import 'keychain.dart';
import 'pairing.dart';
import 'providers.dart';

/// The paired daemons, plus the loopback development daemon when enabled.
class DaemonRegistry extends Notifier<List<DaemonRecord>> {
  late Future<void> _ready;
  DaemonListLoad _loaded = const DaemonListLoad([]);
  Future<void> _saves = Future.value();

  @override
  List<DaemonRecord> build() {
    _ready = Future.microtask(_load);
    return [if (ref.watch(devDaemonEnabledProvider)) const DaemonRecord.dev()];
  }

  /// Completes when the saved list has been read.
  Future<void> get ready => _ready;

  Future<void> _load() async {
    final DaemonListLoad saved;
    try {
      saved = await ref.read(daemonListStoreProvider).load();
    } on Object catch (e) {
      debugPrint('daemon list: not read: $e');
      if (ref.mounted) {
        ref
            .read(daemonListProblemProvider.notifier)
            .report(ListProblem('The saved daemon list could not be read: $e'));
      }
      return;
    }
    if (!ref.mounted) return;
    // Daemons paired while the list was loading stay.
    final known = {for (final d in state) d.id};
    state = [
      ...state,
      for (final d in saved.daemons)
        if (known.add(d.id)) d,
    ];
    _loaded = saved;
    await _settle();
  }

  /// Reports what is wrong with the saved list and cleans up the keychain as
  /// far as that is safe.
  Future<void> _settle() async {
    ref.read(daemonListProblemProvider.notifier).report(_problemOf(_loaded));
    await _sweep(_loaded.clean);
  }

  static ListProblem? _problemOf(DaemonListLoad saved) {
    final parts = <String>[];
    if (saved.readError case final error?) {
      parts.add(
        'The saved daemon list could not be read ($error). Nothing was '
        'changed or deleted, and changes to the list are not saved. Quit '
        'whatever else uses daemons.json and start the app again.',
      );
    }
    if (saved.damaged) {
      parts.add(
        saved.copied
            ? 'The saved daemon list is damaged and was not read. A copy was '
                  'kept as daemons.json.damaged next to it.'
            : 'The saved daemon list is damaged and was not read, and no copy '
                  'of it could be made. Changes to the list are not saved '
                  'until the file is fixed or moved.',
      );
    }
    if (saved.unreadable > 0) {
      final n = saved.unreadable;
      parts.add(
        '$n saved daemon ${n == 1 ? 'entry' : 'entries'} could not be read '
        'and ${n == 1 ? 'is' : 'are'} skipped. ${n == 1 ? 'It stays' : 'They stay'} '
        'in daemons.json until you discard ${n == 1 ? 'it' : 'them'}.',
      );
    }
    if (saved.overCapNames.isNotEmpty) {
      final n = saved.overCapNames.length;
      parts.add(
        '$n saved ${n == 1 ? 'daemon is' : 'daemons are'} beyond the limit '
        'of $kMaxDaemons and not shown. ${n == 1 ? 'It stays' : 'They stay'} '
        'in daemons.json: remove a daemon to make room, or discard '
        '${n == 1 ? 'it' : 'them'}.',
      );
    }
    final copy = saved.damagedCopies > 0 && !saved.damaged;
    if (copy) {
      parts.add(
        'A copy of a damaged daemon list is kept as daemons.json.damaged. '
        'Until you discard it, the keys of daemons that are not listed are '
        'kept, so the copy can still be restored by hand.',
      );
    }
    if (parts.isEmpty) return null;
    return ListProblem(
      parts.join('\n'),
      canDiscard: saved.unreadable > 0 || saved.overCapNames.isNotEmpty,
      savingRefused:
          saved.readError != null || (saved.damaged && !saved.copied),
      discardDetail: _discardDetail(saved),
      canDiscardCopy: copy,
    );
  }

  /// What the confirmation of discarding unreadable entries says.
  static String _discardDetail(DaemonListLoad saved) {
    final lines = <String>[
      'These entries are deleted from daemons.json for good, and the keys '
          'and certificates stored in the keychain for them are deleted with '
          'the other key material that belongs to no listed daemon.',
    ];
    final unnamed = saved.unreadable - saved.unreadableNames.length;
    if (saved.unreadableNames.isNotEmpty || unnamed > 0) {
      lines.add(
        'Entries that could not be read: ${[...saved.unreadableNames, if (unnamed > 0) '$unnamed without a readable name'].join(', ')}.',
      );
    }
    if (saved.overCapNames.isNotEmpty) {
      lines.add(
        'Entries beyond the limit of $kMaxDaemons daemons, which are not shown '
        'and not checked: ${saved.overCapNames.join(', ')}.',
      );
    }
    lines.add(
      'If they belong to daemons paired with a newer version of the app, '
      'those daemons must be paired again.',
    );
    return lines.join('\n\n');
  }

  /// Drops the entries that could not be read from the saved list for good,
  /// then runs the cleanup of orphaned key material that their presence had
  /// held back.
  Future<void> discardUnreadable() async {
    await _ready;
    ref.read(daemonListStoreProvider).discardUnreadable();
    await _mutate((list) => list);
    if (!ref.mounted) return;
    _loaded = _loaded.without(unreadableEntries: true);
    await _settle();
  }

  /// Deletes the kept copy of a damaged list, then runs the cleanup of key
  /// material that its presence had held back.
  Future<void> discardDamagedCopy() async {
    await _ready;
    await ref.read(daemonListStoreProvider).discardDamagedCopies();
    if (!ref.mounted) return;
    _loaded = _loaded.without(copies: true);
    await _settle();
  }

  /// Removes key material no listed daemon owns: pending keys of interrupted
  /// enrollments or renewals, and everything of an interrupted pairing. When
  /// the list could not be read in full nothing is removed except pending
  /// keys, because an unlisted id may belong to an entry that is only
  /// unreadable.
  Future<void> _sweep(bool removeUnlisted) async {
    final store = CredentialStore(ref.read(keychainProvider));
    try {
      await store.sweep({
        for (final d in state) d.id,
      }, removeUnlisted: removeUnlisted);
    } on KeychainUnavailable catch (e) {
      debugPrint('daemon list: keychain sweep skipped: $e');
    }
  }

  /// Applies [change] to the latest list and saves the result, after every
  /// earlier change: all writes of `daemons.json` go through this queue, and
  /// each starts from the state the previous one left, so none can save an
  /// older copy. [change] returns null to leave the list alone. The state is
  /// published only once the save succeeded; a failed save throws.
  Future<void> _mutate(
    List<DaemonRecord>? Function(List<DaemonRecord> current) change,
  ) {
    final run = _saves.then((_) async {
      if (!ref.mounted) return;
      final next = change(state);
      if (next == null) return;
      await ref.read(daemonListStoreProvider).save([
        for (final d in next)
          if (!d.isDev) d,
      ]);
      if (ref.mounted) state = next;
    });
    _saves = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Pairs a daemon from a pairing string and adds it to the list (replacing
  /// the entry of the same daemon when it is paired again). Throws
  /// [PairingFailure]; when the list cannot be saved nothing stays behind:
  /// the daemon is not listed and a new daemon's credentials are removed.
  Future<DaemonRecord> pair(String pairingString, String deviceName) async {
    await _ready;
    // Before any network call or keychain write: a daemon that cannot be
    // listed afterwards must not use up its one-time code.
    if (ref.read(daemonListStoreProvider).saveRefusal case final why?) {
      throw PairingFailure(
        'daemon_list_unsaved',
        'Pairing is not possible while the daemon list cannot be saved: $why',
      );
    }
    final service = PairingService(
      keychain: ref.read(keychainProvider),
      dialer: ref.read(daemonDialerProvider),
    );
    final record = await service.pair(
      pairingString,
      deviceName,
      knownIds: {
        for (final d in state)
          if (!d.isDev) d.id,
      },
    );
    var replaced = false;
    try {
      await _mutate((current) {
        replaced = current.any((d) => d.id == record.id);
        return [
          for (final d in current)
            if (d.id != record.id) d,
          record,
        ];
      });
    } on Object catch (e) {
      if (!replaced) await _forgetCredentials(record.id);
      throw PairingFailure(
        'daemon_list_unsaved',
        'The daemon was paired but the list of daemons could not be saved, '
            'so it was not added: $e',
      );
    }
    // A daemon paired again gets a fresh connection with its new credentials.
    ref.invalidate(daemonConnectionProvider(record.id));
    return record;
  }

  /// Forgets a daemon and everything the keychain holds for it. Throws when
  /// the list cannot be saved; the daemon then stays listed.
  Future<void> remove(String id) async {
    await _ready;
    if (state.any((d) => d.id == id && d.isDev)) return;
    await _mutate(
      (current) => [
        for (final d in current)
          if (d.id != id) d,
      ],
    );
    ref.invalidate(daemonConnectionProvider(id));
    await _forgetCredentials(id);
  }

  /// Notes when a daemon answered or was lost, in the list and on disk. A
  /// failed save is not worth interrupting anything for.
  Future<void> markSeen(String id, DateTime seen) async {
    await _ready;
    if (!ref.mounted) return;
    try {
      await _mutate((current) {
        final known = current.where((d) => d.id == id).firstOrNull;
        if (known == null || known.isDev) return null;
        return [
          for (final d in current)
            if (d.id == id) d.copyWith(lastSeen: seen) else d,
        ];
      });
    } on Object catch (e) {
      debugPrint('daemon list: last seen of $id not saved: $e');
    }
  }

  /// Notes when the client renewed its certificate with a daemon, in the list
  /// and on disk: the daily limit on renewals survives a restart through it.
  Future<void> markRenewed(String id, DateTime renewed) async {
    await _ready;
    if (!ref.mounted) return;
    await _mutate((current) {
      final known = current.where((d) => d.id == id).firstOrNull;
      if (known == null || known.isDev) return null;
      return [
        for (final d in current)
          if (d.id == id) d.copyWith(lastRenewal: renewed) else d,
      ];
    });
  }

  Future<void> _forgetCredentials(String id) async {
    try {
      await CredentialStore(ref.read(keychainProvider)).delete(id);
    } on KeychainUnavailable catch (e) {
      debugPrint('daemon $id: credentials not deleted: $e');
    }
  }
}
