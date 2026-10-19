/// Per-daemon key material in the OS keychain (design D13).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:yagura_pki/yagura_pki.dart';

import 'keychain.dart';

/// What a secure connection needs: the pinned CA, the client certificate and
/// its private key.
final class DeviceCredentials {
  const DeviceCredentials({
    required this.caDer,
    required this.certificateDer,
    required this.keyPem,
  });

  final Uint8List caDer;
  final Uint8List certificateDer;

  /// SEC1 `EC PRIVATE KEY` PEM. It never leaves the keychain and this process.
  final String keyPem;

  /// The client certificate's `not_after`.
  DateTime get certificateNotAfter =>
      Certificate.parse(certificateDer).notAfter;
}

/// Reads and writes [DeviceCredentials] by daemon id. The key, the client
/// certificate and the CA sit in one keychain entry, so pairing and renewal
/// each replace them in a single write: there is no half-written state.
///
/// The keychain cannot be listed, so the ids that have entries are recorded in
/// an index entry; [sweep] uses it to remove what no listed daemon owns.
final class CredentialStore {
  const CredentialStore(this._keychain);

  final Keychain _keychain;

  static const _index = 'yagura.ids';
  static String _device(String id) => 'yagura.$id.device';
  static String _pending(String id) => 'yagura.$id.pending-key';

  /// The credentials of [daemonId], or null when none are stored (or they are
  /// unreadable).
  Future<DeviceCredentials?> load(String daemonId) async {
    final device = await _keychain.read(_device(daemonId));
    if (device == null) return null;
    try {
      if (jsonDecode(device) case {
        'key': final String key,
        'certificate': final String certificate,
        'ca': final String ca,
      }) {
        return DeviceCredentials(
          caDer: certificateFromPem(ca),
          certificateDer: certificateFromPem(certificate),
          keyPem: key,
        );
      }
    } on FormatException {
      // Fall through: damaged entries count as missing.
    }
    return null;
  }

  Future<void> save(String daemonId, DeviceCredentials credentials) async {
    await _remember(daemonId);
    await _keychain.write(
      _device(daemonId),
      jsonEncode({
        'key': credentials.keyPem,
        'certificate': certificatePem(credentials.certificateDer),
        'ca': certificatePem(credentials.caDer),
      }),
    );
  }

  /// Replaces the key and certificate together (renewal); the CA stays.
  /// Throws [StateError] when nothing is stored for [daemonId].
  Future<void> replaceDevice(
    String daemonId, {
    required String keyPem,
    required Uint8List certificateDer,
  }) async {
    final current = await load(daemonId);
    if (current == null) {
      throw StateError('no credentials are stored for daemon $daemonId');
    }
    await save(
      daemonId,
      DeviceCredentials(
        caDer: current.caDer,
        certificateDer: certificateDer,
        keyPem: keyPem,
      ),
    );
  }

  /// A key generated for an enrollment or renewal that has not completed.
  Future<void> writePendingKey(String daemonId, String keyPem) async {
    await _remember(daemonId);
    await _keychain.write(_pending(daemonId), keyPem);
  }

  Future<String?> readPendingKey(String daemonId) =>
      _keychain.read(_pending(daemonId));

  Future<void> deletePendingKey(String daemonId) =>
      _keychain.delete(_pending(daemonId));

  /// Removes everything stored for [daemonId].
  Future<void> delete(String daemonId) async {
    await _keychain.delete(_device(daemonId));
    await _keychain.delete(_pending(daemonId));
    await _forget(daemonId);
  }

  /// Startup cleanup: removes the pending key of every id in [listed] (no
  /// enrollment or renewal survives a restart) and, with [removeUnlisted],
  /// everything stored for ids that are not listed (an interrupted pairing).
  Future<void> sweep(Set<String> listed, {required bool removeUnlisted}) async {
    for (final id in await _ids()) {
      if (listed.contains(id)) {
        await deletePendingKey(id);
      } else if (removeUnlisted) {
        await delete(id);
      } else {
        await deletePendingKey(id);
      }
    }
  }

  Future<Set<String>> _ids() async {
    final raw = await _keychain.read(_index);
    if (raw == null) return {};
    try {
      if (jsonDecode(raw) case final List<Object?> ids) {
        return {
          for (final id in ids)
            if (id is String) id,
        };
      }
    } on FormatException {
      // An unreadable index lists nothing.
    }
    return {};
  }

  Future<void> _remember(String id) async {
    final ids = await _ids();
    if (ids.add(id)) await _keychain.write(_index, jsonEncode(ids.toList()));
  }

  Future<void> _forget(String id) async {
    final ids = await _ids();
    if (!ids.remove(id)) return;
    if (ids.isEmpty) {
      await _keychain.delete(_index);
    } else {
      await _keychain.write(_index, jsonEncode(ids.toList()));
    }
  }
}
