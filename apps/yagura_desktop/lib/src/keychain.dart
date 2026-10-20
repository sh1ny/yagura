/// The OS keychain behind the device keys (design D13).
library;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when the OS keychain cannot be read or written. Pairing is refused
/// with `keychain_unavailable`; paired daemons are listed `offline` with it.
class KeychainUnavailable implements Exception {
  const KeychainUnavailable([this.message = '']);

  final String message;

  static const reason = 'keychain_unavailable';

  @override
  String toString() => message.isEmpty ? reason : '$reason: $message';
}

/// A small string store. Production uses `flutter_secure_storage` (Windows
/// Credential Manager, libsecret); tests use an in-memory fake.
abstract interface class Keychain {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [Keychain] over `flutter_secure_storage`.
final class SecureStorageKeychain implements Keychain {
  SecureStorageKeychain([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw KeychainUnavailable(e.message ?? e.code);
    } on Exception catch (e) {
      throw KeychainUnavailable('$e');
    }
  }

  @override
  Future<String?> read(String key) => _guard(() => _storage.read(key: key));

  @override
  Future<void> write(String key, String value) =>
      _guard(() => _storage.write(key: key, value: value));

  @override
  Future<void> delete(String key) => _guard(() => _storage.delete(key: key));
}
