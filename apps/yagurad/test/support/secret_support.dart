import 'dart:typed_data';

import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/secret_store.dart';

/// A protector for one fake account scope on one fake machine: blobs are
/// tagged with both and refuse to open under another, like DPAPI user scope
/// (the key depends on the account and on the machine).
class FakeSecretProtector implements SecretProtector {
  FakeSecretProtector(this.scopeSid, {this.machine = 'machine-1'});

  @override
  final String scopeSid;

  /// Stands for the machine-bound part of the DPAPI key.
  final String machine;

  String get _tag => '$scopeSid@$machine';

  @override
  Uint8List protect(Uint8List plain) {
    final tag = _tag.codeUnits;
    return Uint8List.fromList([
      tag.length,
      ...tag,
      for (final b in plain) b ^ 0x5A,
    ]);
  }

  @override
  Uint8List unprotect(Uint8List blob) {
    final length = blob[0];
    final tag = String.fromCharCodes(blob.sublist(1, 1 + length));
    if (tag != _tag) {
      throw YaguraException(
        'secret_store_unavailable',
        'secret protected for $tag, not $_tag',
      );
    }
    return Uint8List.fromList([
      for (final b in blob.sublist(1 + length)) b ^ 0x5A,
    ]);
  }
}

/// The scope of a `--dev` daemon run by a user.
const devSid = 'S-1-5-21-1-2-3-1001';

/// The scope of the service (LocalSystem).
const serviceSid = 'S-1-5-18';
