import 'dart:typed_data';

import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/secret_store.dart';

/// A protector for one fake account scope: blobs are tagged with the scope
/// and refuse to open in another, like DPAPI user scope.
class FakeSecretProtector implements SecretProtector {
  FakeSecretProtector(this.scopeSid);

  @override
  final String scopeSid;

  @override
  Uint8List protect(Uint8List plain) {
    final tag = scopeSid.codeUnits;
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
    if (tag != scopeSid) {
      throw YaguraException(
        'secret_store_unavailable',
        'secret protected for $tag, not $scopeSid',
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
