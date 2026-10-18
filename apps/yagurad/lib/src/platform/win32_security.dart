import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'win32.dart';

/// A Windows security call failed with [code] (`GetLastError`).
class Win32Error implements Exception {
  Win32Error(this.call, this.code);

  /// The Win32 function that failed.
  final String call;
  final int code;

  @override
  String toString() => 'Win32Error: $call failed with error $code';
}

Win32Error _failed(String call) =>
    Win32Error(call, Win32.instance.getLastError());

/// The string form (`S-1-5-...`) of the SID at [sid], copied out of the
/// system allocation.
String _sidString(Pointer<Void> sid) {
  final win32 = Win32.instance;
  final out = calloc<Pointer<Utf16>>();
  try {
    if (win32.convertSidToStringSid(sid, out) == 0) {
      throw _failed('ConvertSidToStringSidW');
    }
    final text = out.value.toDartString();
    win32.localFree(out.value.cast());
    return text;
  } finally {
    calloc.free(out);
  }
}

/// The SID of the user the current process token belongs to, in string form.
String currentUserSid() {
  final win32 = Win32.instance;
  final token = calloc<IntPtr>();
  final length = calloc<Uint32>();
  try {
    if (win32.openProcessToken(
          win32.getCurrentProcess(),
          Win32.tokenQuery,
          token,
        ) ==
        0) {
      throw _failed('OpenProcessToken');
    }
    try {
      // The first call only reports the size the `TOKEN_USER` needs.
      win32.getTokenInformation(
        token.value,
        Win32.tokenUser,
        nullptr,
        0,
        length,
      );
      final buffer = calloc<Uint8>(length.value);
      try {
        if (win32.getTokenInformation(
              token.value,
              Win32.tokenUser,
              buffer.cast(),
              length.value,
              length,
            ) ==
            0) {
          throw _failed('GetTokenInformation');
        }
        // `TOKEN_USER` starts with `SID_AND_ATTRIBUTES.Sid`, a pointer.
        return _sidString(buffer.cast<Pointer<Void>>().value);
      } finally {
        calloc.free(buffer);
      }
    } finally {
      win32.closeHandle(token.value);
    }
  } finally {
    calloc
      ..free(token)
      ..free(length);
  }
}

/// The string form (`S-1-5-...`) of the SID in [sid] bytes.
String sidToString(Uint8List sid) {
  final buffer = calloc<Uint8>(sid.length);
  try {
    buffer.asTypedList(sid.length).setAll(0, sid);
    return _sidString(buffer.cast());
  } finally {
    calloc.free(buffer);
  }
}

/// The SID bytes of the string form [sid].
Uint8List stringToSid(String sid) {
  final win32 = Win32.instance;
  final text = sid.toNativeUtf16();
  final out = calloc<Pointer<Void>>();
  try {
    if (win32.convertStringSidToSid(text, out) == 0) {
      throw _failed('ConvertStringSidToSidW');
    }
    final length = win32.getLengthSid(out.value);
    final bytes = Uint8List.fromList(
      out.value.cast<Uint8>().asTypedList(length),
    );
    win32.localFree(out.value);
    return bytes;
  } finally {
    calloc
      ..free(text)
      ..free(out);
  }
}

/// A `DATA_BLOB` over a native copy of [data]: `cbData` at 0, `pbData` at 8.
Pointer<Uint8> _blobOf(Uint8List data, Pointer<Uint8> blob) {
  final bytes = calloc<Uint8>(data.isEmpty ? 1 : data.length);
  bytes.asTypedList(data.length).setAll(0, data);
  blob.cast<Uint32>().value = data.length;
  (blob + 8).cast<Pointer<Uint8>>().value = bytes;
  return bytes;
}

Uint8List _takeBlob(Pointer<Uint8> blob) {
  final length = blob.cast<Uint32>().value;
  final data = (blob + 8).cast<Pointer<Uint8>>().value;
  final bytes = Uint8List.fromList(data.asTypedList(length));
  // The system copy may hold a secret: clear it before releasing it.
  data.asTypedList(length).fillRange(0, length, 0);
  Win32.instance.localFree(data.cast());
  return bytes;
}

/// `CRYPTPROTECT_UI_FORBIDDEN`: never prompt, user scope (no
/// `CRYPTPROTECT_LOCAL_MACHINE`).
const _cryptProtectUiForbidden = 1;

/// Protects [plain] with DPAPI in the current user's scope.
Uint8List dpapiProtect(Uint8List plain) {
  final win32 = Win32.instance;
  final input = calloc<Uint8>(16);
  final output = calloc<Uint8>(16);
  final bytes = _blobOf(plain, input);
  try {
    if (win32.cryptProtectData(
          input.cast(),
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          _cryptProtectUiForbidden,
          output.cast(),
        ) ==
        0) {
      throw _failed('CryptProtectData');
    }
    return _takeBlob(output);
  } finally {
    calloc
      ..free(bytes)
      ..free(input)
      ..free(output);
  }
}

/// Reverses [dpapiProtect]; throws [Win32Error] when the blob is damaged or
/// protected for another scope.
Uint8List dpapiUnprotect(Uint8List blob) {
  final win32 = Win32.instance;
  final input = calloc<Uint8>(16);
  final output = calloc<Uint8>(16);
  final bytes = _blobOf(blob, input);
  try {
    if (win32.cryptUnprotectData(
          input.cast(),
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          _cryptProtectUiForbidden,
          output.cast(),
        ) ==
        0) {
      throw _failed('CryptUnprotectData');
    }
    return _takeBlob(output);
  } finally {
    calloc
      ..free(bytes)
      ..free(input)
      ..free(output);
  }
}

/// Converts [sddl] to a self-relative security descriptor and passes it to
/// [use]; the descriptor is freed afterwards. Returns the conversion error
/// (captured right after the call) when [sddl] does not parse, else `null`.
Win32Error? _withDescriptor(String sddl, void Function(Pointer<Void> sd) use) {
  final win32 = Win32.instance;
  final text = sddl.toNativeUtf16();
  final out = calloc<Pointer<Void>>();
  try {
    if (win32.convertStringSecurityDescriptorToSecurityDescriptor(
          text,
          Win32.sddlRevision1,
          out,
          nullptr,
        ) ==
        0) {
      return _failed('ConvertStringSecurityDescriptorToSecurityDescriptorW');
    }
    try {
      use(out.value);
    } finally {
      win32.localFree(out.value);
    }
    return null;
  } finally {
    calloc
      ..free(text)
      ..free(out);
  }
}

/// Whether SDDL [sddl] converts to a security descriptor.
bool sddlParses(String sddl) => _withDescriptor(sddl, (_) {}) == null;

/// Replaces the DACL of the file at [path] with the one from [sddl], through
/// `SetKernelObjectSecurity` on a handle opened for `WRITE_DAC` without
/// following a link at [path]. The new DACL is protected: nothing inherits.
void setFileDacl(String path, String sddl) {
  final win32 = Win32.instance;
  final name = path.toNativeUtf16();
  final int handle;
  final int openError;
  try {
    handle = win32.createFile(
      name,
      Win32.writeDac,
      Win32.fileShareReadWrite,
      nullptr,
      Win32.openExisting,
      Win32.fileFlagBackupSemantics | Win32.fileFlagOpenReparsePoint,
      0,
    );
    openError = handle == Win32.invalidHandle ? win32.getLastError() : 0;
  } finally {
    calloc.free(name);
  }
  if (handle == Win32.invalidHandle) throw Win32Error('CreateFileW', openError);
  try {
    Win32Error? failure;
    final parseError = _withDescriptor(sddl, (sd) {
      if (win32.setKernelObjectSecurity(
            handle,
            Win32.daclSecurityInformation |
                Win32.protectedDaclSecurityInformation,
            sd,
          ) ==
          0) {
        failure = _failed('SetKernelObjectSecurity');
      }
    });
    if (parseError != null) throw parseError;
    if (failure case final error?) throw error;
  } finally {
    win32.closeHandle(handle);
  }
}
