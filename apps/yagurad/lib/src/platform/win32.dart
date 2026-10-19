import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// How often [callReadingError] repeats a failed call whose error reads 0.
const errorReadAttempts = 5;

/// Calls [call], a Win32 call that has no effect when it fails, and reads
/// `GetLastError` right after a failure ([failed] tells one).
///
/// `GetLastError` through `dart:ffi` sometimes reads 0 after the first
/// failure of a call in a process, whatever is done in between (seen under
/// load); a repeat of the failed call reads the true code. So a failure that
/// reads 0 is repeated, up to [errorReadAttempts] times. Do not use this for a
/// call that has an effect when it fails or that may succeed the second time
/// for another reason. [readError] is for tests.
({T value, int error}) callReadingError<T>(
  T Function() call,
  bool Function(T value) failed, {
  int Function()? readError,
}) {
  final read = readError ?? Win32.instance.getLastError;
  late T value;
  var error = 0;
  for (var attempt = 0; attempt < errorReadAttempts; attempt++) {
    value = call();
    if (!failed(value)) return (value: value, error: 0);
    error = read();
    if (error != 0) break;
  }
  return (value: value, error: error);
}

/// The few kernel32 calls the daemon needs (job objects, suspended spawn,
/// process enumeration, disk space), bound by hand with `dart:ffi`: a handful
/// of functions does not justify a Win32 binding package. All structure
/// layouts are the 64-bit ones (Dart on Windows is 64-bit only).
///
/// Only touch [instance] on Windows.
class Win32 {
  Win32._() : this._open(DynamicLibrary.open('kernel32.dll'));

  Win32._open(this._kernel)
    // Bound at once: binding it after a failed call (lazily) would reset the
    // error it is about to read.
    : getLastError = _kernel.lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
        isLeaf: true,
      ) {
    // The first call of a binding compiles its stub, which would reset the
    // error a failed call left: do that now.
    getLastError();
  }

  final DynamicLibrary _kernel;

  static final Win32 instance = Win32._();

  late final int Function(Pointer<Void>, Pointer<Utf16>) createJobObject =
      _kernel.lookupFunction<
        IntPtr Function(Pointer<Void>, Pointer<Utf16>),
        int Function(Pointer<Void>, Pointer<Utf16>)
      >('CreateJobObjectW');

  late final int Function(int, int, Pointer<Void>, int)
  setInformationJobObject = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('SetInformationJobObject');

  late final int Function(int, int) assignProcessToJobObject = _kernel
      .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
        'AssignProcessToJobObject',
      );

  late final int Function(int, int) terminateJobObject = _kernel
      .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
        'TerminateJobObject',
      );

  late final int Function(
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
  createProcess = _kernel
      .lookupFunction<
        Int32 Function(
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
      >('CreateProcessW');

  late final int Function(int) resumeThread = _kernel
      .lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
        'ResumeThread',
      );

  late final int Function(int) closeHandle = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  late final int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)
  createPipe = _kernel
      .lookupFunction<
        Int32 Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, Uint32),
        int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)
      >('CreatePipe');

  late final int Function(int, int, int) setHandleInformation = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Uint32),
        int Function(int, int, int)
      >('SetHandleInformation');

  late final int Function(
    Pointer<Utf16>,
    int,
    int,
    Pointer<Void>,
    int,
    int,
    int,
  )
  createFile = _kernel
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');

  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  readFile = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile');

  late final int Function(int, int) waitForSingleObject = _kernel
      .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
        'WaitForSingleObject',
      );

  late final int Function(int, Pointer<Uint32>) getExitCodeProcess = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetExitCodeProcess');

  late final int Function(int, int) terminateProcess = _kernel
      .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
        'TerminateProcess',
      );

  late final int Function(int, int, int) openProcess = _kernel
      .lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)
      >('OpenProcess');

  late final int Function(int, int, Pointer<Utf16>, Pointer<Uint32>)
  queryFullProcessImageName = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>),
        int Function(int, int, Pointer<Utf16>, Pointer<Uint32>)
      >('QueryFullProcessImageNameW');

  late final int Function(int, int) createToolhelp32Snapshot = _kernel
      .lookupFunction<IntPtr Function(Uint32, Uint32), int Function(int, int)>(
        'CreateToolhelp32Snapshot',
      );

  late final int Function(int, Pointer<Void>) process32First = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>),
        int Function(int, Pointer<Void>)
      >('Process32FirstW');

  late final int Function(int, Pointer<Void>) process32Next = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>),
        int Function(int, Pointer<Void>)
      >('Process32NextW');

  late final int Function(
    Pointer<Utf16>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
  )
  getDiskFreeSpaceEx = _kernel
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        ),
        int Function(
          Pointer<Utf16>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )
      >('GetDiskFreeSpaceExW');

  late final int Function(Pointer<Utf16>, Pointer<Utf16>, int)
  getVolumePathName = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('GetVolumePathNameW');

  late final int Function() getCurrentProcess = _kernel
      .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');

  late final int Function(int, int, Pointer<Int32>) isProcessInJob = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, IntPtr, Pointer<Int32>),
        int Function(int, int, Pointer<Int32>)
      >('IsProcessInJob');

  late final int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
  queryInformationJobObject = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
        int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
      >('QueryInformationJobObject');

  late final int Function(
    int,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint64>,
  )
  getProcessTimes = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        ),
        int Function(
          int,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )
      >('GetProcessTimes');

  late final int Function(Pointer<Void>, int) setConsoleCtrlHandler = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('SetConsoleCtrlHandler');

  late final int Function(int) attachConsole = _kernel
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'AttachConsole',
      );

  late final int Function() freeConsole = _kernel
      .lookupFunction<Int32 Function(), int Function()>('FreeConsole');

  late final int Function(int, int) generateConsoleCtrlEvent = _kernel
      .lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>(
        'GenerateConsoleCtrlEvent',
      );

  late final int Function(
    int,
    Pointer<Void>,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
  peekNamedPipe = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Void>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Void>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('PeekNamedPipe');

  /// `GetLastError`.
  final int Function() getLastError;

  late final int Function(Pointer<Void>) _localFree = _kernel
      .lookupFunction<
        IntPtr Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('LocalFree');

  /// Frees memory the system allocated with `LocalAlloc` (SID strings,
  /// security descriptors, DPAPI output).
  void localFree(Pointer<Void> memory) => _localFree(memory);

  // advapi32: tokens, SIDs and security descriptors.
  late final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');

  late final int Function(int, int, Pointer<IntPtr>) openProcessToken = _advapi
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
        int Function(int, int, Pointer<IntPtr>)
      >('OpenProcessToken');

  late final int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
  getTokenInformation = _advapi
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
        int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
      >('GetTokenInformation');

  late final int Function(Pointer<Void>, Pointer<Pointer<Utf16>>)
  convertSidToStringSid = _advapi
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Utf16>>),
        int Function(Pointer<Void>, Pointer<Pointer<Utf16>>)
      >('ConvertSidToStringSidW');

  late final int Function(Pointer<Utf16>, Pointer<Pointer<Void>>)
  convertStringSidToSid = _advapi
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>),
        int Function(Pointer<Utf16>, Pointer<Pointer<Void>>)
      >('ConvertStringSidToSidW');

  late final int Function(Pointer<Void>) getLengthSid = _advapi
      .lookupFunction<
        Uint32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('GetLengthSid');

  late final int Function(
    Pointer<Utf16>,
    int,
    Pointer<Pointer<Void>>,
    Pointer<Uint32>,
  )
  convertStringSecurityDescriptorToSecurityDescriptor = _advapi
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Uint32>,
        )
      >('ConvertStringSecurityDescriptorToSecurityDescriptorW');

  late final int Function(int, int, Pointer<Void>) setKernelObjectSecurity =
      _advapi.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>),
        int Function(int, int, Pointer<Void>)
      >('SetKernelObjectSecurity');

  late final int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
  getKernelObjectSecurity = _advapi
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32, Pointer<Uint32>),
        int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)
      >('GetKernelObjectSecurity');

  late final int Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Int32>)
  getSecurityDescriptorOwner = _advapi
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Int32>),
        int Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Int32>)
      >('GetSecurityDescriptorOwner');

  // crypt32: DPAPI. A `DATA_BLOB` is 16 bytes: `cbData` (Uint32) at 0 and
  // `pbData` (pointer) at 8.
  late final DynamicLibrary _crypt = DynamicLibrary.open('crypt32.dll');

  late final int Function(
    Pointer<Void>,
    Pointer<Utf16>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<Void>,
  )
  cryptProtectData = _crypt
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Uint32,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          Pointer<Void>,
        )
      >('CryptProtectData');

  late final int Function(
    Pointer<Void>,
    Pointer<Pointer<Utf16>>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<Void>,
  )
  cryptUnprotectData = _crypt
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Utf16>>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Uint32,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Utf16>>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          Pointer<Void>,
        )
      >('CryptUnprotectData');

  static const invalidHandle = -1;
  static const waitObject0 = 0;

  // Process creation flags.
  static const createSuspended = 0x00000004;
  static const createNewConsole = 0x00000010;
  static const detachedProcess = 0x00000008;
  static const createBreakawayFromJob = 0x01000000;
  static const createUnicodeEnvironment = 0x00000400;
  static const createNoWindow = 0x08000000;

  // Access rights.
  static const processTerminate = 0x0001;
  static const synchronize = 0x00100000;
  static const processQueryLimitedInformation = 0x1000;

  /// `TOKEN_QUERY` and the `TokenUser` information class.
  static const tokenQuery = 0x0008;
  static const tokenUser = 1;

  /// `SDDL_REVISION_1`.
  static const sddlRevision1 = 1;

  /// `SECURITY_INFORMATION` bits for [setKernelObjectSecurity].
  static const ownerSecurityInformation = 0x1;
  static const daclSecurityInformation = 0x4;
  static const protectedDaclSecurityInformation = 0x80000000;
  static const unprotectedDaclSecurityInformation = 0x20000000;

  /// `WRITE_DAC` and `GENERIC_WRITE`-free open of a file for a DACL change.
  static const writeDac = 0x00040000;

  /// `FILE_FLAG_BACKUP_SEMANTICS` and `FILE_FLAG_OPEN_REPARSE_POINT`.
  static const fileFlagBackupSemantics = 0x02000000;
  static const fileFlagOpenReparsePoint = 0x00200000;

  /// `JOB_OBJECT_LIMIT_BREAKAWAY_OK`.
  static const jobBreakawayOk = 0x800;

  /// `JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK`: children start outside the job
  /// (this machine's tool shell has it); `CREATE_BREAKAWAY_FROM_JOB` works.
  static const jobSilentBreakawayOk = 0x1000;

  /// `STARTF_USESHOWWINDOW` and `SW_HIDE`.
  static const startfUseShowWindow = 0x1;
  static const swHide = 0;

  /// `GENERIC_READ`, `FILE_SHARE_READ | FILE_SHARE_WRITE`, `OPEN_EXISTING`.
  static const genericRead = 0x80000000;
  static const fileShareReadWrite = 0x3;
  static const openExisting = 3;
  static const handleFlagInherit = 1;

  /// `WAIT_TIMEOUT`.
  static const waitTimeout = 0x102;

  /// `STILL_ACTIVE`, the exit code of a process that has not ended.
  static const stillActive = 259;

  /// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
  static const jobKillOnClose = 0x2000;

  /// `JobObjectExtendedLimitInformation`.
  static const jobExtendedLimitInformation = 9;

  /// `JobObjectBasicAccountingInformation`, 48 bytes with `ActiveProcesses`
  /// at 40.
  static const jobBasicAccountingInformation = 1;
  static const jobBasicAccountingSize = 48;
  static const jobActiveProcessesOffset = 40;

  /// Size of `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` (64-bit).
  static const jobExtendedLimitSize = 144;

  /// Offset of `BasicLimitInformation.LimitFlags`.
  static const jobLimitFlagsOffset = 16;

  /// `STARTUPINFOW` (size 104): `cb` at 0, `dwFlags` at 60, the three standard
  /// handles at 80, 88 and 96.
  static const startupInfoSize = 104;
  static const startfUseStdHandles = 0x100;

  /// `PROCESS_INFORMATION` (size 24): process handle at 0, thread handle at 8,
  /// process id at 16.
  static const processInformationSize = 24;

  /// `SECURITY_ATTRIBUTES` (size 24) with the inherit flag at 16.
  static const securityAttributesSize = 24;

  /// `PROCESSENTRY32W`: size 568, pid at 8, executable name (WCHAR[260]) at 44.
  static const processEntrySize = 568;
  static const snapProcess = 2;
}
