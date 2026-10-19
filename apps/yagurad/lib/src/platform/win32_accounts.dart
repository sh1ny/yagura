import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'win32.dart';

final DynamicLibrary _netapi = DynamicLibrary.open('netapi32.dll');
final DynamicLibrary _userenv = DynamicLibrary.open('userenv.dll');

final int Function(Pointer<Utf16>, Pointer<Utf16>) _netUserDel = _netapi
    .lookupFunction<
      Uint32 Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)
    >('NetUserDel');

final int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>)
_deleteProfile = _userenv
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>)
    >('DeleteProfileW');

/// `NERR_UserNotFound`.
const nerrUserNotFound = 2221;

/// Deletes the local account [name]; returns the `NET_API_STATUS` (0 on
/// success, [nerrUserNotFound] when there is no such account).
int deleteLocalAccount(String name) {
  final user = name.toNativeUtf16();
  try {
    return _netUserDel(nullptr, user);
  } finally {
    calloc.free(user);
  }
}

/// Deletes the profile of the account with SID [sid]; returns 0 on success or
/// the Win32 error (`ERROR_FILE_NOT_FOUND` when the account never had a
/// profile). A profile that is still loaded fails with a sharing or access
/// error and is left.
int deleteAccountProfile(String sid) {
  final text = sid.toNativeUtf16();
  try {
    final call = callReadingError(
      () => _deleteProfile(text, nullptr, nullptr),
      (r) => r == 0,
    );
    return call.value == 0 ? call.error : 0;
  } finally {
    calloc.free(text);
  }
}
