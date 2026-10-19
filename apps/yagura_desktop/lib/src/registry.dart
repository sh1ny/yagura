/// The daemon registry: which daemons the client knows (design D13).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credentials.dart';
import 'daemon_record.dart';
import 'pairing.dart';
import 'providers.dart';

/// The paired daemons, plus the loopback development daemon when enabled.
class DaemonRegistry extends Notifier<List<DaemonRecord>> {
  @override
  List<DaemonRecord> build() {
    Future.microtask(_load);
    return [if (ref.watch(devDaemonEnabledProvider)) const DaemonRecord.dev()];
  }

  Future<void> _load() async {
    final saved = await ref.read(daemonListStoreProvider).load();
    if (!ref.mounted) return;
    // Daemons paired while the list was loading stay.
    final known = {for (final d in state) d.id};
    state = [
      ...state,
      for (final d in saved.take(kMaxDaemons))
        if (known.add(d.id)) d,
    ];
  }

  Future<void> _save() => ref.read(daemonListStoreProvider).save([
    for (final d in state)
      if (!d.isDev) d,
  ]);

  /// Pairs a daemon from a pairing string and adds it to the list (replacing
  /// the entry of the same daemon when it is paired again). Throws
  /// [PairingFailure].
  Future<DaemonRecord> pair(String pairingString, String deviceName) async {
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
    state = [
      for (final d in state)
        if (d.id != record.id) d,
      record,
    ];
    await _save();
    // A daemon paired again gets a fresh connection with its new credentials.
    ref.invalidate(daemonConnectionProvider(record.id));
    return record;
  }

  /// Forgets a daemon and everything the keychain holds for it.
  Future<void> remove(String id) async {
    if (state.any((d) => d.id == id && d.isDev)) return;
    state = [
      for (final d in state)
        if (d.id != id) d,
    ];
    ref.invalidate(daemonConnectionProvider(id));
    await _save();
    await CredentialStore(ref.read(keychainProvider)).delete(id);
  }
}
