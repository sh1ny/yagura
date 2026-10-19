import 'dart:ffi';
import 'dart:io' show Platform;
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

/// `NTE_BAD_KEY_STATE`: the key (a DPAPI master key) is not usable in this
/// state; what an unknown master key yields.
const ntBadKeyState = 0x8009000B;

/// `NTE_BAD_DATA`.
const ntBadData = 0x80090005;

/// `ERROR_INVALID_DATA`: the blob is damaged, or its integrity check fails.
const errorInvalidData = 13;

/// Whether a `CryptUnprotectData` failure with [code] means the blob can
/// never be opened by this key (a wrong-key failure, design D3). Any other
/// code, a transient or environmental fault, says nothing about the blob.
bool isWrongKeyCode(int code) {
  final unsigned = code & 0xFFFFFFFF;
  return unsigned == ntBadKeyState ||
      unsigned == ntBadData ||
      unsigned == errorInvalidData;
}

/// A DPAPI call failed; [code] is the Win32 error.
class DpapiError extends Win32Error {
  DpapiError(super.call, super.code);

  /// Whether the blob can never be opened by this key (see
  /// [isWrongKeyCode]).
  bool get isWrongKey => isWrongKeyCode(code);

  @override
  String toString() =>
      '$call failed with error $code (0x${(code & 0xFFFFFFFF).toRadixString(16)})';
}

Win32Error _failed(String call) =>
    Win32Error(call, Win32.instance.getLastError());

/// The string form (`S-1-5-...`) of the SID at [sid], copied out of the
/// system allocation.
String _sidString(Pointer<Void> sid) {
  final win32 = Win32.instance;
  final out = calloc<Pointer<Utf16>>();
  try {
    final call = callReadingError(
      () => win32.convertSidToStringSid(sid, out),
      (r) => r == 0,
    );
    if (call.value == 0) {
      throw Win32Error('ConvertSidToStringSidW', call.error);
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
    final call = callReadingError(
      () => win32.openProcessToken(
        win32.getCurrentProcess(),
        Win32.tokenQuery,
        token,
      ),
      (r) => r == 0,
    );
    if (call.value == 0) throw Win32Error('OpenProcessToken', call.error);
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
    final call = callReadingError(
      () => win32.convertStringSidToSid(text, out),
      (r) => r == 0,
    );
    if (call.value == 0) {
      throw Win32Error('ConvertStringSidToSidW', call.error);
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
    final call = callReadingError(
      () => win32.cryptProtectData(
        input.cast(),
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output.cast(),
      ),
      (r) => r == 0,
    );
    if (call.value == 0) throw Win32Error('CryptProtectData', call.error);
    return _takeBlob(output);
  } finally {
    calloc
      ..free(bytes)
      ..free(input)
      ..free(output);
  }
}

/// Reverses [dpapiProtect]; throws [DpapiError] when the blob is damaged or
/// protected for another scope, or DPAPI fails for any other reason.
/// [DpapiError.isWrongKey] tells the two apart.
Uint8List dpapiUnprotect(Uint8List blob) {
  final win32 = Win32.instance;
  final input = calloc<Uint8>(16);
  final output = calloc<Uint8>(16);
  final bytes = _blobOf(blob, input);
  try {
    // A failure has no effect, so one that reads as error 0 is repeated to
    // read the true code (see [callReadingError]); a wrong-key failure must
    // not be mistaken for a transient one.
    final call = callReadingError(
      () => win32.cryptUnprotectData(
        input.cast(),
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output.cast(),
      ),
      (r) => r == 0,
    );
    if (call.value == 0) throw DpapiError('CryptUnprotectData', call.error);
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
    final call = callReadingError(
      () => win32.convertStringSecurityDescriptorToSecurityDescriptor(
        text,
        Win32.sddlRevision1,
        out,
        nullptr,
      ),
      (r) => r == 0,
    );
    if (call.value == 0) {
      return Win32Error(
        'ConvertStringSecurityDescriptorToSecurityDescriptorW',
        call.error,
      );
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

/// The SID of the Administrators group.
const administratorsGroupSid = 'S-1-5-32-544';

/// The string SID of the owner of the kernel object [handle] (a pipe end,
/// opened for reading its security: any handle may do).
String pipeOwnerSid(int handle) {
  final win32 = Win32.instance;
  final needed = calloc<Uint32>();
  final owner = calloc<Pointer<Void>>();
  final defaulted = calloc<Int32>();
  try {
    // The first call only reports the size the descriptor needs.
    win32.getKernelObjectSecurity(
      handle,
      Win32.ownerSecurityInformation,
      nullptr,
      0,
      needed,
    );
    final size = needed.value;
    if (size == 0) throw _failed('GetKernelObjectSecurity');
    final descriptor = calloc<Uint8>(size);
    try {
      final read = callReadingError(
        () => win32.getKernelObjectSecurity(
          handle,
          Win32.ownerSecurityInformation,
          descriptor.cast(),
          size,
          needed,
        ),
        (r) => r == 0,
      );
      if (read.value == 0) {
        throw Win32Error('GetKernelObjectSecurity', read.error);
      }
      final found = callReadingError(
        () => win32.getSecurityDescriptorOwner(
          descriptor.cast(),
          owner,
          defaulted,
        ),
        (r) => r == 0,
      );
      if (found.value == 0 || owner.value == nullptr) {
        throw Win32Error('GetSecurityDescriptorOwner', found.error);
      }
      return _sidString(owner.value);
    } finally {
      calloc.free(descriptor);
    }
  } finally {
    calloc
      ..free(needed)
      ..free(owner)
      ..free(defaulted);
  }
}

/// `WRITE_OWNER`.
const writeOwner = 0x00080000;

/// Replaces the DACL of the object behind [handle] (opened with `WRITE_DAC`,
/// and `WRITE_OWNER` for [ownerSid]) with the one from [sddl], through
/// `SetKernelObjectSecurity`. The new DACL is protected, so nothing inherits;
/// with [protect] false it is marked unprotected instead, for the entries the
/// daemon's own walk writes to a child (they carry the inherited flag).
/// Setting the descriptor through the handle that was checked leaves no gap
/// for a path to be swapped for another.
void setHandleDacl(
  int handle,
  String sddl, {
  String? ownerSid,
  bool protect = true,
}) {
  final win32 = Win32.instance;
  Win32Error? failure;
  final parseError = _withDescriptor(
    ownerSid == null ? sddl : 'O:$ownerSid$sddl',
    (sd) {
      // A failed call has no effect, so a failure that reads as error 0 is
      // repeated (see [callReadingError]).
      final call = callReadingError(
        () => win32.setKernelObjectSecurity(
          handle,
          Win32.daclSecurityInformation |
              (protect
                  ? Win32.protectedDaclSecurityInformation
                  : Win32.unprotectedDaclSecurityInformation) |
              (ownerSid == null ? 0 : Win32.ownerSecurityInformation),
          sd,
        ),
        (r) => r == 0,
      );
      if (call.value == 0) {
        failure = Win32Error('SetKernelObjectSecurity', call.error);
      }
    },
  );
  if (parseError != null) throw parseError;
  if (failure case final error?) throw error;
}

/// Replaces the DACL of the file at [path] with the one from [sddl] (see
/// [setHandleDacl]), on a handle opened for `WRITE_DAC` without following a
/// link at [path].
void setFileDacl(String path, String sddl, {String? ownerSid}) {
  final win32 = Win32.instance;
  final name = path.toNativeUtf16();
  try {
    final open = callReadingError(
      () => win32.createFile(
        name,
        Win32.writeDac | (ownerSid == null ? 0 : writeOwner),
        Win32.fileShareReadWrite,
        nullptr,
        Win32.openExisting,
        Win32.fileFlagBackupSemantics | Win32.fileFlagOpenReparsePoint,
        0,
      ),
      (h) => h == Win32.invalidHandle,
    );
    if (open.value == Win32.invalidHandle) {
      throw Win32Error('CreateFileW', open.error);
    }
    try {
      setHandleDacl(open.value, sddl, ownerSid: ownerSid);
    } finally {
      win32.closeHandle(open.value);
    }
  } finally {
    calloc.free(name);
  }
}

/// Calls [use] with a `SECURITY_ATTRIBUTES` (not inheritable) that carries
/// the descriptor of [sddl]; both are freed afterwards. Throws the
/// conversion error when [sddl] does not parse.
T withSecurityAttributes<T>(String sddl, T Function(Pointer<Void>) use) {
  late T result;
  final error = _withDescriptor(sddl, (sd) {
    // struct { DWORD nLength; LPVOID lpSecurityDescriptor; BOOL bInherit; }
    final attributes = calloc<Uint8>(24);
    try {
      attributes.cast<Uint32>().value = 24;
      (attributes + 8).cast<Pointer<Void>>().value = sd;
      result = use(attributes.cast<Void>());
    } finally {
      calloc.free(attributes);
    }
  });
  if (error != null) throw error;
  return result;
}

final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');

final int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Void>,
  Pointer<Uint32>,
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
)
_lookupAccountName = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Uint32>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Uint32>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      )
    >('LookupAccountNameW');

/// [account] as the local machine names it (`BOX\yagura-srv`; `.\` when the
/// machine name is not known), so that a lookup searches the local accounts
/// and never the domain the machine has joined.
String qualifyLocalAccount(String account, String? computerName) =>
    '${computerName == null || computerName.isEmpty ? '.' : computerName}'
    '\\$account';

/// `SidTypeUser` of `SID_NAME_USE`.
const _sidTypeUser = 1;

/// The string SID of the local user account [account], or null when there is
/// no such user (a group, a domain account or an alias of the same name is
/// not one).
String? lookupAccountSid(String account) {
  final name = qualifyLocalAccount(
    account,
    Platform.environment['COMPUTERNAME'],
  ).toNativeUtf16();
  final sidSize = calloc<Uint32>();
  final domainSize = calloc<Uint32>();
  final use = calloc<Uint32>();
  try {
    _lookupAccountName(
      nullptr,
      name,
      nullptr,
      sidSize,
      nullptr,
      domainSize,
      use,
    );
    if (sidSize.value == 0) return null;
    final sid = calloc<Uint8>(sidSize.value);
    final domain = calloc<Uint16>(domainSize.value + 1).cast<Utf16>();
    try {
      if (_lookupAccountName(
            nullptr,
            name,
            sid.cast(),
            sidSize,
            domain,
            domainSize,
            use,
          ) ==
          0) {
        return null;
      }
      if (use.value != _sidTypeUser) return null;
      return _sidString(sid.cast());
    } finally {
      calloc
        ..free(sid)
        ..free(domain);
    }
  } finally {
    calloc
      ..free(name)
      ..free(sidSize)
      ..free(domainSize)
      ..free(use);
  }
}

/// The SID of the user the process [pid] runs as, or null when the process
/// cannot be inspected.
String? processUserSid(int pid) {
  final win32 = Win32.instance;
  final process = win32.openProcess(
    Win32.processQueryLimitedInformation,
    0,
    pid,
  );
  if (process == 0) return null;
  try {
    return _tokenUserSid(process);
  } finally {
    win32.closeHandle(process);
  }
}

String? _tokenUserSid(int process) {
  final win32 = Win32.instance;
  final token = calloc<IntPtr>();
  final length = calloc<Uint32>();
  try {
    if (win32.openProcessToken(process, Win32.tokenQuery, token) == 0) {
      return null;
    }
    try {
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
          return null;
        }
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

/// Whether this process's token holds Administrators as a deny-only group:
/// the user is an administrator that has not elevated.
bool administratorsAreDenyOnly() {
  const tokenGroups = 2;
  const denyOnly = 0x10;
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
      return false;
    }
    try {
      win32.getTokenInformation(token.value, tokenGroups, nullptr, 0, length);
      final buffer = calloc<Uint8>(length.value);
      try {
        if (win32.getTokenInformation(
              token.value,
              tokenGroups,
              buffer.cast(),
              length.value,
              length,
            ) ==
            0) {
          return false;
        }
        // TOKEN_GROUPS: DWORD GroupCount, then 16-byte SID_AND_ATTRIBUTES
        // entries from offset 8.
        final count = buffer.cast<Uint32>().value;
        for (var i = 0; i < count; i++) {
          final entry = buffer + 8 + i * 16;
          final sid = _sidString(entry.cast<Pointer<Void>>().value);
          final attributes = (entry + 8).cast<Uint32>().value;
          if (sid == 'S-1-5-32-544') return attributes & denyOnly != 0;
        }
        return false;
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

/// Whether this process's token is elevated (`TokenElevation`): an
/// administrator that has elevated, or LocalSystem. A standard user, and an
/// administrator in a prompt that has not been elevated, are not.
bool isElevated() {
  const tokenElevation = 20;
  final win32 = Win32.instance;
  final token = calloc<IntPtr>();
  final elevation = calloc<Uint32>();
  final length = calloc<Uint32>();
  try {
    final open = callReadingError(
      () => win32.openProcessToken(
        win32.getCurrentProcess(),
        Win32.tokenQuery,
        token,
      ),
      (r) => r == 0,
    );
    if (open.value == 0) throw Win32Error('OpenProcessToken', open.error);
    try {
      final query = callReadingError(
        () => win32.getTokenInformation(
          token.value,
          tokenElevation,
          elevation.cast(),
          4,
          length,
        ),
        (r) => r == 0,
      );
      if (query.value == 0) {
        throw Win32Error('GetTokenInformation', query.error);
      }
      return elevation.value != 0;
    } finally {
      win32.closeHandle(token.value);
    }
  } finally {
    calloc
      ..free(token)
      ..free(elevation)
      ..free(length);
  }
}

final int Function(
  Pointer<Void>,
  int,
  int,
  Pointer<Pointer<Utf16>>,
  Pointer<Uint32>,
)
_descriptorToString = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Uint32,
        Uint32,
        Pointer<Pointer<Utf16>>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Void>,
        int,
        int,
        Pointer<Pointer<Utf16>>,
        Pointer<Uint32>,
      )
    >('ConvertSecurityDescriptorToStringSecurityDescriptorW');

/// The owner and the DACL of the kernel object [handle] (opened with
/// `READ_CONTROL`) as SDDL, for reading with `parseSecurity`.
String securityDescriptorSddl(int handle) {
  final win32 = Win32.instance;
  const information =
      Win32.ownerSecurityInformation | Win32.daclSecurityInformation;
  final needed = calloc<Uint32>();
  try {
    // The first call only reports the size the descriptor needs.
    win32.getKernelObjectSecurity(handle, information, nullptr, 0, needed);
    final size = needed.value;
    if (size == 0) throw _failed('GetKernelObjectSecurity');
    final descriptor = calloc<Uint8>(size);
    final text = calloc<Pointer<Utf16>>();
    try {
      final read = callReadingError(
        () => win32.getKernelObjectSecurity(
          handle,
          information,
          descriptor.cast(),
          size,
          needed,
        ),
        (r) => r == 0,
      );
      if (read.value == 0) {
        throw Win32Error('GetKernelObjectSecurity', read.error);
      }
      final converted = callReadingError(
        () => _descriptorToString(
          descriptor.cast(),
          Win32.sddlRevision1,
          information,
          text,
          nullptr,
        ),
        (r) => r == 0,
      );
      if (converted.value == 0) {
        throw Win32Error(
          'ConvertSecurityDescriptorToStringSecurityDescriptorW',
          converted.error,
        );
      }
      try {
        return text.value.toDartString();
      } finally {
        win32.localFree(text.value.cast());
      }
    } finally {
      calloc
        ..free(descriptor)
        ..free(text);
    }
  } finally {
    calloc.free(needed);
  }
}
