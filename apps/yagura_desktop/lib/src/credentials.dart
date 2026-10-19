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

/// Reads and writes [DeviceCredentials] by daemon id. The key and the client
/// certificate sit in one keychain entry, so a renewal swaps both at once.
final class CredentialStore {
  const CredentialStore(this._keychain);

  final Keychain _keychain;

  static String _device(String id) => 'yagura.$id.device';
  static String _ca(String id) => 'yagura.$id.ca';
  static String _pending(String id) => 'yagura.$id.pending-key';

  /// The credentials of [daemonId], or null when none are stored (or they are
  /// unreadable).
  Future<DeviceCredentials?> load(String daemonId) async {
    final device = await _keychain.read(_device(daemonId));
    final ca = await _keychain.read(_ca(daemonId));
    if (device == null || ca == null) return null;
    try {
      if (jsonDecode(device) case {
        'key': final String key,
        'certificate': final String certificate,
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
    await _keychain.write(_ca(daemonId), certificatePem(credentials.caDer));
    await replaceDevice(
      daemonId,
      keyPem: credentials.keyPem,
      certificateDer: credentials.certificateDer,
    );
  }

  /// Replaces the key and certificate together (renewal).
  Future<void> replaceDevice(
    String daemonId, {
    required String keyPem,
    required Uint8List certificateDer,
  }) => _keychain.write(
    _device(daemonId),
    jsonEncode({'key': keyPem, 'certificate': certificatePem(certificateDer)}),
  );

  /// A key generated for an enrollment or renewal that has not completed.
  Future<void> writePendingKey(String daemonId, String keyPem) =>
      _keychain.write(_pending(daemonId), keyPem);

  Future<String?> readPendingKey(String daemonId) =>
      _keychain.read(_pending(daemonId));

  Future<void> deletePendingKey(String daemonId) =>
      _keychain.delete(_pending(daemonId));

  /// Removes everything stored for [daemonId].
  Future<void> delete(String daemonId) async {
    await _keychain.delete(_device(daemonId));
    await _keychain.delete(_ca(daemonId));
    await _keychain.delete(_pending(daemonId));
  }
}
