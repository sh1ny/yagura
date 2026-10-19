import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'win32.dart';
import '../service/install_root_security.dart' show parseSecurity;
import 'win32_security.dart';

/// The shared logon module (design D7, D10, ADR 0015): logs a service account
/// on (`LogonUserW`, batch), gives it a window station and desktop that name
/// the account SID, loads its profile and environment, and starts a process in
/// its token (`CreateProcessAsUserW`). The launcher uses it for the relay
/// of a game server (`yagura-srv`, `YaguraSrv\Default`) and the daemon for
/// SteamCMD and its bootstrap (`yagura-steam`, `YaguraSteam\Default`).
///
/// Windows only. Every function here needs the privileges of LocalSystem, so
/// only `elevated` rows run them for real.

final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');
final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _userenv = DynamicLibrary.open('userenv.dll');
final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');

final int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  int,
  Pointer<IntPtr>,
)
_logonUser = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<IntPtr>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        int,
        Pointer<IntPtr>,
      )
    >('LogonUserW');

final int Function(
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
  Pointer<Utf16>,
  Pointer<Void>,
  Pointer<Void>,
)
_createProcessAsUser = _advapi
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
        Int32,
        Uint32,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('CreateProcessAsUserW');

final int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint8>)
_lookupPrivilegeValue = _advapi
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint8>),
      int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint8>)
    >('LookupPrivilegeValueW');

final int Function(int, int, Pointer<Uint8>, int, Pointer<Void>, Pointer<Void>)
_adjustTokenPrivileges = _advapi
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Pointer<Uint8>,
        Uint32,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(int, int, Pointer<Uint8>, int, Pointer<Void>, Pointer<Void>)
    >('AdjustTokenPrivileges');

final int Function(Pointer<Utf16>, int, int, Pointer<Void>)
_createWindowStation = _user32
    .lookupFunction<
      IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>),
      int Function(Pointer<Utf16>, int, int, Pointer<Void>)
    >('CreateWindowStationW');

final int Function(
  Pointer<Utf16>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
)
_createDesktop = _user32
    .lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
        Uint32,
        Uint32,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
      )
    >('CreateDesktopW');

final int Function() _getProcessWindowStation = _user32
    .lookupFunction<IntPtr Function(), int Function()>(
      'GetProcessWindowStation',
    );

final int Function(int) _setProcessWindowStation = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetProcessWindowStation',
    );

/// `SetUserObjectSecurity` takes a pointer to the `SECURITY_INFORMATION`, not
/// the flags by value (spike S2).
final int Function(int, Pointer<Uint32>, Pointer<Void>) _setUserObjectSecurity =
    _user32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>, Pointer<Void>),
      int Function(int, Pointer<Uint32>, Pointer<Void>)
    >('SetUserObjectSecurity');

final int Function(int) _closeWindowStation = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseWindowStation',
    );

final int Function(int) _closeDesktop = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseDesktop');

final int Function(int, Pointer<Uint8>) _loadUserProfile = _userenv
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('LoadUserProfileW');

final int Function(int, int) _unloadUserProfile = _userenv
    .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'UnloadUserProfile',
    );

final int Function(Pointer<Pointer<Void>>, int, int) _createEnvironmentBlock =
    _userenv.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, IntPtr, Int32),
      int Function(Pointer<Pointer<Void>>, int, int)
    >('CreateEnvironmentBlock');

final int Function(Pointer<Void>) _destroyEnvironmentBlock = _userenv
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'DestroyEnvironmentBlock',
    );

final int Function(Pointer<Void>, int, int, Pointer<IntPtr>)
_initializeProcThreadAttributeList = _kernel
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<IntPtr>),
      int Function(Pointer<Void>, int, int, Pointer<IntPtr>)
    >('InitializeProcThreadAttributeList');

final int Function(
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
  int,
  Pointer<Void>,
  Pointer<Void>,
)
_updateProcThreadAttribute = _kernel
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Uint32,
        IntPtr,
        Pointer<Void>,
        IntPtr,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
        int,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('UpdateProcThreadAttribute');

final void Function(Pointer<Void>) _deleteProcThreadAttributeList = _kernel
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'DeleteProcThreadAttributeList',
    );

const _logon32LogonBatch = 4;
const _procThreadAttributeHandleList = 0x00020002;
const _extendedStartupInfoPresent = 0x00080000;
const _startupInfoExSize = 112;

/// `WINSTA_ALL_ACCESS`, `DESKTOP_ALL` and `GENERIC_ALL` hold no standard
/// rights; the station and desktop handles also need `READ_CONTROL` and
/// `WRITE_DAC` for the DACL to be set on an existing object (spike S2).
const _readControlWriteDac = 0x00020000 | 0x00040000;
const _winstaAllAccess = 0x37F;
const _desktopAll = 0x01FF;
const _genericAll = 0x10000000;

/// Which part of starting a process as a service account failed.
enum LogonStage {
  /// The account itself: lookup, logon, profile, environment, window station
  /// and desktop. The account is the problem (`launch_logon_failed`).
  account,

  /// Creating the process: a missing, quarantined or broken image fails here
  /// whatever the account.
  process,
}

/// A logon, profile load or process start of a service account failed.
class LogonFailure implements Exception {
  const LogonFailure(
    this.account,
    this.call,
    this.error, {
    this.stage = LogonStage.account,
  });

  /// What failed; see [LogonStage].
  final LogonStage stage;

  final String account;

  /// The Win32 call.
  final String call;

  /// Its error, as `GetLastError` read it.
  final int error;

  @override
  String toString() => '$call for $account failed with error $error';
}

/// The owner of a window station or desktop that is neither SYSTEM,
/// Administrators nor [accountSid] (the account the object is for), from the
/// owner's SDDL (`O:SY`); null when it is one of them. `CreateWindowStationW`
/// and `CreateDesktopW` open an object of that name that already exists, and
/// its owner keeps `WRITE_DAC` whatever DACL is set, so an object another
/// account created first is not adopted. The account itself has full access
/// already, so owning its own object grants it nothing new.
String? untrustedWindowObjectOwner(String ownerSddl, String accountSid) {
  final owner = parseSecurity(ownerSddl).ownerSid;
  if (owner == 'S-1-5-18' || owner == 'S-1-5-32-544') return null;
  if (owner != null && owner.toLowerCase() == accountSid.toLowerCase()) {
    return null;
  }
  return owner ?? 'nobody';
}

/// The window station and desktop of a service account: `YaguraSrv\Default`
/// for `yagura-srv` and `YaguraSteam\Default` for `yagura-steam`.
String windowStationOf(String account) =>
    account == 'yagura-steam' ? 'YaguraSteam' : 'YaguraSrv';

/// Turns on [privilege] in this process's token, if the token holds it.
bool enablePrivilege(String privilege) {
  final win32 = Win32.instance;
  final token = calloc<IntPtr>();
  final name = privilege.toNativeUtf16();
  final privileges = calloc<Uint8>(16);
  try {
    // TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY
    if (win32.openProcessToken(win32.getCurrentProcess(), 0x28, token) == 0) {
      return false;
    }
    try {
      // TOKEN_PRIVILEGES: count, then a LUID and its attributes.
      privileges.cast<Uint32>().value = 1;
      if (_lookupPrivilegeValue(nullptr, name, privileges + 4) == 0) {
        return false;
      }
      (privileges + 12).cast<Uint32>().value = 2; // SE_PRIVILEGE_ENABLED
      return _adjustTokenPrivileges(
            token.value,
            0,
            privileges,
            0,
            nullptr,
            nullptr,
          ) !=
          0;
    } finally {
      win32.closeHandle(token.value);
    }
  } finally {
    calloc
      ..free(token)
      ..free(name)
      ..free(privileges);
  }
}

/// A logged-on service account with its profile loaded, ready to start
/// processes. Every profile load is balanced: [close] unloads the profile
/// (design D7; an unbalanced load keeps the hive loaded until reboot and the
/// profile cannot be deleted).
class AccountSession {
  AccountSession._(
    this.account,
    this.sid,
    this._token,
    this._profile,
    this._environment,
    this.desktop,
    this._stationHandle,
    this._desktopHandle,
  );

  final String account;

  /// The account's SID, as the desktop ACL names it.
  final String sid;
  final int _token;
  final int _profile;
  final Pointer<Void> _environment;

  /// `<station>\Default`, the `lpDesktop` of the processes started.
  final String desktop;

  /// The station and desktop handles stay open as long as the session: the
  /// last handle of an object nobody is attached to destroys it, and a child
  /// that starts on a destroyed desktop fails with 0xC0000142 (the spike's
  /// launcher kept them open too).
  final int _stationHandle;
  final int _desktopHandle;
  var _closed = false;

  /// Logs [account] on with [password] (batch logon), prepares its window
  /// station and desktop, loads its profile and builds its environment.
  /// Throws a [LogonFailure] naming the call and its error.
  factory AccountSession.open(String account, String password) {
    final win32 = Win32.instance;
    final sid = lookupAccountSid(account);
    if (sid == null) throw LogonFailure(account, 'LookupAccountName', 1332);
    final user = account.toNativeUtf16();
    final domain = '.'.toNativeUtf16();
    final secret = password.toNativeUtf16();
    final token = calloc<IntPtr>();
    try {
      final logon = callReadingError(
        () => _logonUser(user, domain, secret, _logon32LogonBatch, 0, token),
        (r) => r == 0,
      );
      if (logon.value == 0) {
        throw LogonFailure(account, 'LogonUserW', logon.error);
      }
    } finally {
      // The password does not stay in native memory.
      for (var i = 0; i <= password.length; i++) {
        (secret.cast<Uint16>() + i).value = 0;
      }
      calloc
        ..free(user)
        ..free(domain)
        ..free(secret);
    }
    final handle = token.value;
    calloc.free(token);
    var profile = 0;
    var objects = (station: 0, desktop: 0);
    Pointer<Void> environment = nullptr;
    try {
      final station = windowStationOf(account);
      objects = _prepareDesktop(account, sid, station);
      profile = _loadProfile(account, handle);
      environment = _environmentBlock(account, handle);
      return AccountSession._(
        account,
        sid,
        handle,
        profile,
        environment,
        '$station\\Default',
        objects.station,
        objects.desktop,
      );
    } on Object {
      if (objects.desktop != 0) _closeDesktop(objects.desktop);
      if (objects.station != 0) _closeWindowStation(objects.station);
      if (environment != nullptr) _destroyEnvironmentBlock(environment);
      if (profile != 0) _unloadUserProfile(handle, profile);
      win32.closeHandle(handle);
      rethrow;
    }
  }

  /// Starts [commandLine] as the account (`CreateProcessAsUserW`).
  ///
  /// [handles], when given, are the only handles the child inherits
  /// (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`, design D10); they must be
  /// inheritable. [stdin], [stdout] and [stderr] are the child's standard
  /// handles. The thread handle is returned open, so a process started
  /// [suspended] can be resumed. [environment], when given, is added to the
  /// account's own environment.
  StartedProcess start({
    required String commandLine,
    String? workingDirectory,
    int flags = 0,
    bool hidden = true,
    List<int>? handles,
    int? stdin,
    int? stdout,
    int? stderr,
    Map<String, String> environment = const {},
  }) {
    if (_closed) throw StateError('the session is closed');
    enablePrivilege('SeAssignPrimaryTokenPrivilege');
    enablePrivilege('SeIncreaseQuotaPrivilege');
    final startup = calloc<Uint8>(_startupInfoExSize);
    final processInfo = calloc<Uint8>(Win32.processInformationSize);
    final command = commandLine.toNativeUtf16();
    final directory = workingDirectory?.toNativeUtf16();
    final desktopName = desktop.toNativeUtf16();
    final list = handles == null ? null : calloc<IntPtr>(handles.length);
    final listSize = calloc<IntPtr>();
    Pointer<Void> attributes = nullptr;
    Pointer<Void> block = _environment;
    Pointer<Utf16>? merged;
    try {
      // STARTUPINFOW is 104 bytes; the extended structure (112) only goes with
      // an attribute list and EXTENDED_STARTUPINFO_PRESENT.
      startup.cast<Uint32>().value = list != null ? _startupInfoExSize : 104;
      (startup + 16).cast<Pointer<Utf16>>().value = desktopName;
      var startFlags = 0;
      if (hidden) {
        startFlags |= Win32.startfUseShowWindow;
        (startup + 64).cast<Uint16>().value = Win32.swHide;
      }
      if (stdin != null || stdout != null || stderr != null) {
        startFlags |= Win32.startfUseStdHandles;
        (startup + 80).cast<IntPtr>().value = stdin ?? 0;
        (startup + 88).cast<IntPtr>().value = stdout ?? 0;
        (startup + 96).cast<IntPtr>().value = stderr ?? 0;
      }
      (startup + 60).cast<Uint32>().value = startFlags;
      var creation = flags | Win32.createUnicodeEnvironment;
      if (list != null) {
        for (var i = 0; i < handles!.length; i++) {
          list[i] = handles[i];
        }
        _initializeProcThreadAttributeList(nullptr, 1, 0, listSize);
        attributes = calloc<Uint8>(listSize.value).cast();
        if (_initializeProcThreadAttributeList(attributes, 1, 0, listSize) ==
            0) {
          throw LogonFailure(
            account,
            'InitializeProcThreadAttributeList',
            0,
            stage: LogonStage.process,
          );
        }
        if (_updateProcThreadAttribute(
              attributes,
              0,
              _procThreadAttributeHandleList,
              list.cast(),
              handles.length * 8,
              nullptr,
              nullptr,
            ) ==
            0) {
          throw LogonFailure(
            account,
            'UpdateProcThreadAttribute',
            0,
            stage: LogonStage.process,
          );
        }
        (startup + 104).cast<Pointer<Void>>().value = attributes;
        creation |= _extendedStartupInfoPresent;
      }
      if (environment.isNotEmpty) {
        merged = _mergedBlock(_environment, environment);
        block = merged.cast();
      }
      final created = callReadingError(
        () => _createProcessAsUser(
          _token,
          nullptr,
          command,
          nullptr,
          nullptr,
          handles == null && stdin == null && stdout == null && stderr == null
              ? 0
              : 1,
          creation,
          block,
          directory ?? nullptr,
          startup.cast(),
          processInfo.cast(),
        ),
        (r) => r == 0,
      );
      if (created.value == 0) {
        throw LogonFailure(
          account,
          'CreateProcessAsUserW',
          created.error,
          stage: LogonStage.process,
        );
      }
      return StartedProcess(
        pid: (processInfo + 16).cast<Uint32>().value,
        process: processInfo.cast<IntPtr>().value,
        thread: (processInfo + 8).cast<IntPtr>().value,
      );
    } finally {
      if (attributes != nullptr) {
        _deleteProcThreadAttributeList(attributes);
        calloc.free(attributes);
      }
      if (merged != null) calloc.free(merged);
      calloc
        ..free(startup)
        ..free(processInfo)
        ..free(command)
        ..free(desktopName)
        ..free(listSize);
      if (directory != null) calloc.free(directory);
      if (list != null) calloc.free(list);
    }
  }

  /// Unloads the profile and closes the token. Safe to call twice; the
  /// processes started keep running.
  void close() {
    if (_closed) return;
    _closed = true;
    _destroyEnvironmentBlock(_environment);
    _unloadUserProfile(_token, _profile);
    Win32.instance.closeHandle(_token);
    _closeDesktop(_desktopHandle);
    _closeWindowStation(_stationHandle);
  }
}

/// A process started by [AccountSession.start]; the caller closes both
/// handles.
class StartedProcess {
  const StartedProcess({
    required this.pid,
    required this.process,
    required this.thread,
  });

  final int pid;
  final int process;
  final int thread;
}

/// Creates the window station [station] and its `Default` desktop if they do
/// not exist, and sets their DACL to SYSTEM, Administrators and the account
/// SID (not the per-logon SID, which changes with every logon: an ACL on it
/// would have to grow). An existing object keeps its old descriptor, so it is
/// set every time.
///
/// Returns the two open handles: the caller keeps them until the processes it
/// starts have attached; [AccountSession.close] closes them.
({int station, int desktop}) _prepareDesktop(
  String account,
  String sid,
  String station,
) {
  return withSecurityAttributes(windowObjectSddl(sid), (attributes) {
    final descriptor = (attributes.cast<Uint8>() + 8)
        .cast<Pointer<Void>>()
        .value;
    final information = calloc<Uint32>()
      ..value = 4; // DACL_SECURITY_INFORMATION
    final stationName = station.toNativeUtf16();
    final desktopName = 'Default'.toNativeUtf16();
    var winsta = 0;
    var desk = 0;
    final previous = _getProcessWindowStation();
    try {
      winsta = _createWindowStation(
        stationName,
        0,
        _winstaAllAccess | _readControlWriteDac,
        attributes,
      );
      if (winsta == 0) {
        throw LogonFailure(
          account,
          'CreateWindowStationW',
          Win32.instance.getLastError(),
        );
      }
      _requireTrustedOwner(account, sid, 'station', winsta);
      if (_setUserObjectSecurity(winsta, information, descriptor) == 0) {
        throw LogonFailure(
          account,
          'SetUserObjectSecurity(station)',
          Win32.instance.getLastError(),
        );
      }
      // The desktop is created on the process's current station.
      _setProcessWindowStation(winsta);
      desk = _createDesktop(
        desktopName,
        nullptr,
        nullptr,
        0,
        _desktopAll | _genericAll | _readControlWriteDac,
        attributes,
      );
      final error = desk == 0 ? Win32.instance.getLastError() : 0;
      _setProcessWindowStation(previous);
      if (desk == 0) throw LogonFailure(account, 'CreateDesktopW', error);
      _requireTrustedOwner(account, sid, 'desktop', desk);
      if (_setUserObjectSecurity(desk, information, descriptor) == 0) {
        throw LogonFailure(
          account,
          'SetUserObjectSecurity(desktop)',
          Win32.instance.getLastError(),
        );
      }
      return (station: winsta, desktop: desk);
    } on Object {
      if (desk != 0) _closeDesktop(desk);
      if (winsta != 0) _closeWindowStation(winsta);
      rethrow;
    } finally {
      _setProcessWindowStation(previous);
      calloc
        ..free(information)
        ..free(stationName)
        ..free(desktopName);
    }
  });
}

/// The DACL of a service account's window station or desktop: full access
/// for SYSTEM, Administrators and the account. Narrower rights fail process
/// initialisation (`0xC0000142`); the account owning its own object is
/// harmless (see [untrustedWindowObjectOwner]).
String windowObjectSddl(String sid) =>
    'D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;$sid)';

/// `ERROR_INVALID_OWNER`.
const _errorInvalidOwner = 1307;

/// Refuses a station or desktop that SYSTEM, Administrators or the account
/// itself do not own: it existed already and was made by someone else.
void _requireTrustedOwner(
  String account,
  String accountSid,
  String kind,
  int handle,
) {
  final String owner;
  try {
    final untrusted = untrustedWindowObjectOwner(
      userObjectOwnerSddl(handle),
      accountSid,
    );
    if (untrusted == null) return;
    owner = untrusted;
  } on Win32Error catch (e) {
    throw LogonFailure(account, 'GetUserObjectSecurity($kind)', e.code);
  }
  throw LogonFailure(
    account,
    'the window $kind is owned by $owner, not SYSTEM, Administrators or $account',
    _errorInvalidOwner,
  );
}

int _loadProfile(String account, int token) {
  final user = account.toNativeUtf16();
  // PROFILEINFOW: size, flags, user name, profile path, default path, server,
  // policy path, profile handle.
  final info = calloc<Uint8>(56);
  try {
    info.cast<Uint32>().value = 56;
    (info + 8).cast<Pointer<Utf16>>().value = user;
    final loaded = callReadingError(
      () => _loadUserProfile(token, info),
      (r) => r == 0,
    );
    if (loaded.value == 0) {
      throw LogonFailure(account, 'LoadUserProfileW', loaded.error);
    }
    return (info + 48).cast<IntPtr>().value;
  } finally {
    calloc
      ..free(user)
      ..free(info);
  }
}

Pointer<Void> _environmentBlock(String account, int token) {
  final out = calloc<Pointer<Void>>();
  try {
    final created = callReadingError(
      () => _createEnvironmentBlock(out, token, 0),
      (r) => r == 0,
    );
    if (created.value == 0) {
      throw LogonFailure(account, 'CreateEnvironmentBlock', created.error);
    }
    return out.value;
  } finally {
    calloc.free(out);
  }
}

/// The environment [block] with [extra] added (or replacing), as a new block;
/// the caller frees it.
Pointer<Utf16> _mergedBlock(Pointer<Void> block, Map<String, String> extra) {
  final entries = <String, String>{};
  final units = block.cast<Uint16>();
  var start = 0;
  var i = 0;
  while (true) {
    if (units[i] == 0) {
      if (i == start) break;
      final text = String.fromCharCodes([
        for (var k = start; k < i; k++) units[k],
      ]);
      final eq = text.indexOf('=', 1);
      if (eq > 0) entries[text.substring(0, eq)] = text.substring(eq + 1);
      start = i + 1;
    }
    i++;
  }
  for (final entry in extra.entries) {
    entries.removeWhere((k, _) => k.toUpperCase() == entry.key.toUpperCase());
    entries[entry.key] = entry.value;
  }
  final sorted = entries.entries.toList()
    ..sort((a, b) => a.key.toUpperCase().compareTo(b.key.toUpperCase()));
  final out = <int>[];
  for (final entry in sorted) {
    out
      ..addAll('${entry.key}=${entry.value}'.codeUnits)
      ..add(0);
  }
  out.add(0);
  final merged = calloc<Uint16>(out.length + 1);
  merged.asTypedList(out.length).setAll(0, out);
  return merged.cast();
}
