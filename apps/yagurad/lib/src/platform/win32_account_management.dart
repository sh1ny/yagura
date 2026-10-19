import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'win32_security.dart';

/// Creating and repairing the service accounts (design D7): `NetUserAdd`,
/// `NetUserSetInfo`, local group membership and the logon rights of the Local
/// Security Authority. Windows only; the calls need administrator rights, so
/// only `elevated` rows run them.

final DynamicLibrary _netapi = DynamicLibrary.open('netapi32.dll');
final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');

final int Function(Pointer<Utf16>, int, Pointer<Void>, Pointer<Uint32>)
_netUserAdd = _netapi
    .lookupFunction<
      Uint32 Function(Pointer<Utf16>, Uint32, Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Utf16>, int, Pointer<Void>, Pointer<Uint32>)
    >('NetUserAdd');

final int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Void>,
  Pointer<Uint32>,
)
_netUserSetInfo = _netapi
    .lookupFunction<
      Uint32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Void>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        Pointer<Void>,
        Pointer<Uint32>,
      )
    >('NetUserSetInfo');

final int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  int,
  Pointer<Pointer<Void>>,
  int,
  Pointer<Uint32>,
  Pointer<Uint32>,
)
_netUserGetLocalGroups = _netapi
    .lookupFunction<
      Uint32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Pointer<Void>>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        int,
        Pointer<Pointer<Void>>,
        int,
        Pointer<Uint32>,
        Pointer<Uint32>,
      )
    >('NetUserGetLocalGroups');

final int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int)
_netLocalGroupAddMembers = _netapi
    .lookupFunction<
      Uint32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Void>,
        Uint32,
      ),
      int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int)
    >('NetLocalGroupAddMembers');

final int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int)
_netLocalGroupDelMembers = _netapi
    .lookupFunction<
      Uint32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Void>,
        Uint32,
      ),
      int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int)
    >('NetLocalGroupDelMembers');

final int Function(Pointer<Void>) _netApiBufferFree = _netapi
    .lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('NetApiBufferFree');

final int Function(Pointer<Void>, Pointer<Void>, int, Pointer<IntPtr>)
_lsaOpenPolicy = _advapi
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Pointer<IntPtr>),
      int Function(Pointer<Void>, Pointer<Void>, int, Pointer<IntPtr>)
    >('LsaOpenPolicy');

final int Function(int, Pointer<Void>, Pointer<Void>, int)
_lsaAddAccountRights = _advapi
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Void>, Pointer<Void>, Uint32),
      int Function(int, Pointer<Void>, Pointer<Void>, int)
    >('LsaAddAccountRights');

final int Function(int, Pointer<Void>, int, Pointer<Void>, int)
_lsaRemoveAccountRights = _advapi
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Void>, Uint8, Pointer<Void>, Uint32),
      int Function(int, Pointer<Void>, int, Pointer<Void>, int)
    >('LsaRemoveAccountRights');

final int Function(int, Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Uint32>)
_lsaEnumerateAccountRights = _advapi
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Void>,
        Pointer<Pointer<Void>>,
        Pointer<Uint32>,
      ),
      int Function(int, Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Uint32>)
    >('LsaEnumerateAccountRights');

final int Function(Pointer<Void>) _lsaFreeMemory = _advapi
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'LsaFreeMemory',
    );

final int Function(int) _lsaClose = _advapi
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('LsaClose');

final int Function(int) _lsaNtStatusToWinError = _advapi
    .lookupFunction<Uint32 Function(Int32), int Function(int)>(
      'LsaNtStatusToWinError',
    );

/// `NERR_UserExists`.
const nerrUserExists = 2224;

/// `ERROR_MEMBER_IN_ALIAS` and `ERROR_MEMBER_NOT_IN_ALIAS`.
const _errorMemberInAlias = 1378;
const _errorMemberNotInAlias = 1377;

/// A failed account call, with its `NET_API_STATUS` or Win32 error.
class Win32AccountError implements Exception {
  const Win32AccountError(this.call, this.code);

  final String call;
  final int code;

  @override
  String toString() => '$call failed with error $code';
}

/// Creates the local account [name] with [password]: an ordinary user whose
/// password does not expire and cannot be changed by it. Returns the
/// `NET_API_STATUS` ([nerrUserExists] when it exists already).
int createLocalAccount(String name, String password, String comment) {
  final user = name.toNativeUtf16();
  final secret = password.toNativeUtf16();
  final note = comment.toNativeUtf16();
  final info = calloc<Uint8>(56);
  try {
    // USER_INFO_1: name, password, password_age, priv, home_dir, comment,
    // flags, script_path.
    info.cast<Pointer<Utf16>>().value = user;
    (info + 8).cast<Pointer<Utf16>>().value = secret;
    (info + 20).cast<Uint32>().value = 1; // USER_PRIV_USER
    (info + 32).cast<Pointer<Utf16>>().value = note;
    // UF_SCRIPT | UF_PASSWD_CANT_CHANGE | UF_DONT_EXPIRE_PASSWD
    (info + 40).cast<Uint32>().value = 0x1 | 0x40 | 0x10000;
    return _netUserAdd(nullptr, 1, info.cast(), nullptr);
  } finally {
    calloc
      ..free(user)
      ..free(secret)
      ..free(note)
      ..free(info);
  }
}

/// Sets the password of the local account [name] (`NetUserSetInfo` level
/// 1003); no logon is made with it. Returns the `NET_API_STATUS`.
int setLocalAccountPassword(String name, String password) {
  final user = name.toNativeUtf16();
  final secret = password.toNativeUtf16();
  final info = calloc<Pointer<Utf16>>();
  try {
    info.value = secret;
    return _netUserSetInfo(nullptr, user, 1003, info.cast(), nullptr);
  } finally {
    calloc
      ..free(user)
      ..free(secret)
      ..free(info);
  }
}

/// The names of the local groups [account] belongs to.
List<String> localGroupsOf(String account) {
  final user = account.toNativeUtf16();
  final buffer = calloc<Pointer<Void>>();
  final read = calloc<Uint32>();
  final total = calloc<Uint32>();
  try {
    final status = _netUserGetLocalGroups(
      nullptr,
      user,
      0,
      0,
      buffer,
      -1,
      read,
      total,
    );
    if (status != 0) throw Win32AccountError('NetUserGetLocalGroups', status);
    try {
      return [
        for (var i = 0; i < read.value; i++)
          (buffer.value.cast<Pointer<Utf16>>() + i).value.toDartString(),
      ];
    } finally {
      _netApiBufferFree(buffer.value);
    }
  } finally {
    calloc
      ..free(user)
      ..free(buffer)
      ..free(read)
      ..free(total);
  }
}

/// Adds the local account [account] to the local group [group]; being a
/// member already is success.
void addToLocalGroup(String group, String account) =>
    _changeMembership(group, account, _netLocalGroupAddMembers, 'Add');

/// Removes [account] from the local group [group]; not being a member is
/// success.
void removeFromLocalGroup(String group, String account) =>
    _changeMembership(group, account, _netLocalGroupDelMembers, 'Del');

void _changeMembership(
  String group,
  String account,
  int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int) call,
  String verb,
) {
  final groupName = group.toNativeUtf16();
  final member = account.toNativeUtf16();
  final info = calloc<Pointer<Utf16>>();
  try {
    // LOCALGROUP_MEMBERS_INFO_3: lgrmi3_domainandname.
    info.value = member;
    final status = call(nullptr, groupName, 3, info.cast(), 1);
    if (status != 0 &&
        status != _errorMemberInAlias &&
        status != _errorMemberNotInAlias) {
      throw Win32AccountError('NetLocalGroup${verb}Members', status);
    }
  } finally {
    calloc
      ..free(groupName)
      ..free(member)
      ..free(info);
  }
}

/// The logon right the service accounts are granted (design D7).
const logonRightsGranted = ['SeBatchLogonRight'];

/// The logon rights the service accounts are denied.
const logonRightsDenied = [
  'SeDenyInteractiveLogonRight',
  'SeDenyRemoteInteractiveLogonRight',
  'SeDenyNetworkLogonRight',
];

/// Assigns [rights] to the account with the binary SID [sid]
/// (`LsaAddAccountRights` keeps what the account has: idempotent).
void addAccountRights(Uint8List sid, List<String> rights) {
  final attributes = calloc<Uint8>(48);
  final policy = calloc<IntPtr>();
  final sidBuffer = calloc<Uint8>(sid.length);
  final strings = calloc<Uint8>(16 * rights.length);
  final texts = <Pointer<Utf16>>[];
  try {
    attributes.cast<Uint32>().value = 48;
    // POLICY_LOOKUP_NAMES | POLICY_CREATE_ACCOUNT
    var status = _lsaOpenPolicy(
      nullptr,
      attributes.cast(),
      0x800 | 0x10,
      policy,
    );
    if (status != 0) {
      throw Win32AccountError('LsaOpenPolicy', _lsaNtStatusToWinError(status));
    }
    try {
      sidBuffer.asTypedList(sid.length).setAll(0, sid);
      for (var i = 0; i < rights.length; i++) {
        final text = rights[i].toNativeUtf16();
        texts.add(text);
        final entry = strings + i * 16;
        // LSA_UNICODE_STRING: Length, MaximumLength, Buffer.
        entry.cast<Uint16>().value = rights[i].length * 2;
        (entry + 2).cast<Uint16>().value = rights[i].length * 2 + 2;
        (entry + 8).cast<Pointer<Utf16>>().value = text;
      }
      status = _lsaAddAccountRights(
        policy.value,
        sidBuffer.cast(),
        strings.cast(),
        rights.length,
      );
      if (status != 0) {
        throw Win32AccountError(
          'LsaAddAccountRights',
          _lsaNtStatusToWinError(status),
        );
      }
    } finally {
      _lsaClose(policy.value);
    }
  } finally {
    for (final text in texts) {
      calloc.free(text);
    }
    calloc
      ..free(attributes)
      ..free(policy)
      ..free(sidBuffer)
      ..free(strings);
  }
}

/// `STATUS_OBJECT_NAME_NOT_FOUND`: the account holds no rights (and has no
/// entry in the policy database).
const _statusObjectNameNotFound = -1073741772; // 0xC0000034

/// Takes every right the policy database holds for the account with the binary
/// SID [sid] (`LsaRemoveAccountRights`, `AllRights` true), which also removes
/// its entry. Deleting an account does not do this: its SID would stay in the
/// local security policy, with the logon rights, as an orphan. An account
/// without rights is not an error.
void removeAllAccountRights(Uint8List sid) {
  final attributes = calloc<Uint8>(48);
  final policy = calloc<IntPtr>();
  final sidBuffer = calloc<Uint8>(sid.length);
  try {
    attributes.cast<Uint32>().value = 48;
    final opened = _lsaOpenPolicy(
      nullptr,
      attributes.cast(),
      0x800 | 0x10,
      policy,
    );
    if (opened != 0) {
      throw Win32AccountError('LsaOpenPolicy', _lsaNtStatusToWinError(opened));
    }
    try {
      sidBuffer.asTypedList(sid.length).setAll(0, sid);
      final status = _lsaRemoveAccountRights(
        policy.value,
        sidBuffer.cast(),
        1,
        nullptr,
        0,
      );
      if (status != 0 && status != _statusObjectNameNotFound) {
        throw Win32AccountError(
          'LsaRemoveAccountRights',
          _lsaNtStatusToWinError(status),
        );
      }
    } finally {
      _lsaClose(policy.value);
    }
  } finally {
    calloc
      ..free(attributes)
      ..free(policy)
      ..free(sidBuffer);
  }
}

/// The rights the policy database holds for the account with the binary SID
/// [sid] (`LsaEnumerateAccountRights`, read-only); empty when it holds none.
List<String> accountRights(Uint8List sid) {
  final attributes = calloc<Uint8>(48);
  final policy = calloc<IntPtr>();
  final sidBuffer = calloc<Uint8>(sid.length);
  final rights = calloc<Pointer<Void>>();
  final count = calloc<Uint32>();
  try {
    attributes.cast<Uint32>().value = 48;
    final opened = _lsaOpenPolicy(nullptr, attributes.cast(), 0x800, policy);
    if (opened != 0) {
      throw Win32AccountError('LsaOpenPolicy', _lsaNtStatusToWinError(opened));
    }
    try {
      sidBuffer.asTypedList(sid.length).setAll(0, sid);
      final status = _lsaEnumerateAccountRights(
        policy.value,
        sidBuffer.cast(),
        rights,
        count,
      );
      if (status == _statusObjectNameNotFound) return const [];
      if (status != 0) {
        throw Win32AccountError(
          'LsaEnumerateAccountRights',
          _lsaNtStatusToWinError(status),
        );
      }
      try {
        return [
          for (var i = 0; i < count.value; i++)
            _lsaString(rights.value.cast<Uint8>() + i * 16),
        ];
      } finally {
        _lsaFreeMemory(rights.value);
      }
    } finally {
      _lsaClose(policy.value);
    }
  } finally {
    calloc
      ..free(attributes)
      ..free(policy)
      ..free(sidBuffer)
      ..free(rights)
      ..free(count);
  }
}

/// The text of the `LSA_UNICODE_STRING` at [entry]: length in bytes, maximum
/// length, then the buffer pointer at offset 8.
String _lsaString(Pointer<Uint8> entry) {
  final bytes = entry.cast<Uint16>().value;
  final buffer = (entry + 8).cast<Pointer<Uint16>>().value;
  return String.fromCharCodes(buffer.asTypedList(bytes ~/ 2));
}

final int Function(
  Pointer<Utf16>,
  Pointer<Void>,
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
)
_lookupAccountSid = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
      )
    >('LookupAccountSidW');

/// The name of the well-known group or account with the string SID [sid] on
/// this machine (`Users` for `S-1-5-32-545`, localised), or null.
String? accountNameOfSid(String sid) {
  final bytes = stringToSid(sid);
  final buffer = calloc<Uint8>(bytes.length);
  final nameSize = calloc<Uint32>();
  final domainSize = calloc<Uint32>();
  final use = calloc<Uint32>();
  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    _lookupAccountSid(
      nullptr,
      buffer.cast(),
      nullptr,
      nameSize,
      nullptr,
      domainSize,
      use,
    );
    if (nameSize.value == 0) return null;
    final name = calloc<Uint16>(nameSize.value + 1).cast<Utf16>();
    final domain = calloc<Uint16>(domainSize.value + 1).cast<Utf16>();
    try {
      if (_lookupAccountSid(
            nullptr,
            buffer.cast(),
            name,
            nameSize,
            domain,
            domainSize,
            use,
          ) ==
          0) {
        return null;
      }
      return name.toDartString();
    } finally {
      calloc
        ..free(name)
        ..free(domain);
    }
  } finally {
    calloc
      ..free(buffer)
      ..free(nameSize)
      ..free(domainSize)
      ..free(use);
  }
}
