import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The few kernel32 calls the daemon needs (job objects, suspended spawn,
/// process enumeration, disk space), bound by hand with `dart:ffi`: a handful
/// of functions does not justify a Win32 binding package. All structure
/// layouts are the 64-bit ones (Dart on Windows is 64-bit only).
///
/// Only touch [instance] on Windows.
class Win32 {
  Win32._() : _kernel = DynamicLibrary.open('kernel32.dll');

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

  static const invalidHandle = -1;
  static const waitObject0 = 0;

  // Process creation flags.
  static const createSuspended = 0x00000004;
  static const createUnicodeEnvironment = 0x00000400;
  static const createNoWindow = 0x08000000;

  // Access rights.
  static const processTerminate = 0x0001;
  static const synchronize = 0x00100000;
  static const processQueryLimitedInformation = 0x1000;

  /// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
  static const jobKillOnClose = 0x2000;

  /// `JobObjectExtendedLimitInformation`.
  static const jobExtendedLimitInformation = 9;

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
