import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The native calls behind the handle-relative file walk (design D8), bound by
/// hand with `dart:ffi` like [Win32]: `NtCreateFile` and the other `ntdll`
/// file calls, which take a `RootDirectory` handle so a path is opened one
/// component at a time from its parent, plus `GetFinalPathNameByHandleW` and
/// `GetLongPathNameW`. Structure layouts are the 64-bit ones.
///
/// Only touch [instance] on Windows.
class Win32Files {
  Win32Files._()
    : _ntdll = DynamicLibrary.open('ntdll.dll'),
      _kernel = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _ntdll;
  final DynamicLibrary _kernel;

  static final Win32Files instance = Win32Files._();

  /// `NtCreateFile(&handle, access, &objectAttributes, &ioStatus, null,
  /// attributes, share, disposition, options, null, 0)`; returns the
  /// `NTSTATUS`.
  late final int Function(
    Pointer<IntPtr>,
    int,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    int,
    int,
    int,
    Pointer<Void>,
    int,
  )
  ntCreateFile = _ntdll
      .lookupFunction<
        Int32 Function(
          Pointer<IntPtr>,
          Uint32,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
        ),
        int Function(
          Pointer<IntPtr>,
          int,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          int,
          int,
          int,
          Pointer<Void>,
          int,
        )
      >('NtCreateFile');

  late final int Function(int) ntClose = _ntdll
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('NtClose');

  /// `NtReadFile(file, null, null, null, &ioStatus, buffer, length, offset,
  /// null)`.
  late final int Function(
    int,
    int,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Int64>,
    Pointer<Uint32>,
  )
  ntReadFile = _ntdll
      .lookupFunction<
        Int32 Function(
          IntPtr,
          IntPtr,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Int64>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          int,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Uint8>,
          int,
          Pointer<Int64>,
          Pointer<Uint32>,
        )
      >('NtReadFile');

  late final int Function(
    int,
    int,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Int64>,
    Pointer<Uint32>,
  )
  ntWriteFile = _ntdll
      .lookupFunction<
        Int32 Function(
          IntPtr,
          IntPtr,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Int64>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          int,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Uint8>,
          int,
          Pointer<Int64>,
          Pointer<Uint32>,
        )
      >('NtWriteFile');

  late final int Function(int, Pointer<Void>) ntFlushBuffersFile = _ntdll
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>),
        int Function(int, Pointer<Void>)
      >('NtFlushBuffersFile');

  /// `NtQueryDirectoryFile(dir, null, null, null, &ioStatus, buffer, length,
  /// class, returnSingle, null, restart)`.
  late final int Function(
    int,
    int,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    int,
    int,
    Pointer<Void>,
    int,
  )
  ntQueryDirectoryFile = _ntdll
      .lookupFunction<
        Int32 Function(
          IntPtr,
          IntPtr,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Uint32,
          Int32,
          Uint8,
          Pointer<Void>,
          Uint8,
        ),
        int Function(
          int,
          int,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          int,
          int,
          Pointer<Void>,
          int,
        )
      >('NtQueryDirectoryFile');

  late final int Function(int, Pointer<Void>, Pointer<Void>, int, int)
  ntQueryInformationFile = _ntdll
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>, Pointer<Void>, Uint32, Int32),
        int Function(int, Pointer<Void>, Pointer<Void>, int, int)
      >('NtQueryInformationFile');

  late final int Function(int, Pointer<Void>, Pointer<Void>, int, int)
  ntSetInformationFile = _ntdll
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>, Pointer<Void>, Uint32, Int32),
        int Function(int, Pointer<Void>, Pointer<Void>, int, int)
      >('NtSetInformationFile');

  /// The Win32 error code (`ERROR_*`) an `NTSTATUS` stands for.
  late final int Function(int) rtlNtStatusToDosError = _ntdll
      .lookupFunction<Uint32 Function(Int32), int Function(int)>(
        'RtlNtStatusToDosError',
      );

  /// `GetFinalPathNameByHandleW(handle, buffer, length, flags)`: the number
  /// of characters written, or the size needed, or 0.
  late final int Function(int, Pointer<Utf16>, int, int)
  getFinalPathNameByHandle = _kernel
      .lookupFunction<
        Uint32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32),
        int Function(int, Pointer<Utf16>, int, int)
      >('GetFinalPathNameByHandleW');

  late final int Function(Pointer<Utf16>, Pointer<Utf16>, int) getLongPathName =
      _kernel.lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('GetLongPathNameW');

  // ---- NTSTATUS values (as unsigned 32-bit) ----------------------------------

  static const statusNoSuchFile = 0xC000000F;
  static const statusEndOfFile = 0xC0000011;
  static const statusObjectNameInvalid = 0xC0000033;
  static const statusObjectNameNotFound = 0xC0000034;
  static const statusObjectNameCollision = 0xC0000035;
  static const statusObjectPathNotFound = 0xC000003A;
  static const statusObjectPathSyntaxBad = 0xC000003B;
  static const statusNotADirectory = 0xC0000103;
  static const statusNoMoreFiles = 0x80000006;
  static const statusCannotDelete = 0xC0000121;
  static const statusFileIsADirectory = 0xC00000BA;

  // ---- access rights ---------------------------------------------------------

  static const fileListDirectory = 0x1;
  static const fileReadData = 0x1;
  static const fileWriteData = 0x2;
  static const fileAddFile = 0x2;
  static const fileAddSubdirectory = 0x4;
  static const fileTraverse = 0x20;
  static const fileReadAttributes = 0x80;
  static const fileWriteAttributes = 0x100;
  static const delete = 0x10000;
  static const synchronize = 0x100000;

  // ---- dispositions and create options ---------------------------------------

  static const fileOpen = 1;
  static const fileCreate = 2;
  static const fileOpenIf = 3;

  static const fileDirectoryFile = 0x1;
  static const fileSynchronousIoNonAlert = 0x20;
  static const fileNonDirectoryFile = 0x40;
  static const fileOpenForBackupIntent = 0x4000;
  static const fileOpenReparsePoint = 0x200000;

  /// `IO_STATUS_BLOCK.Information` after an open that found the file.
  static const fileOpened = 1;

  // ---- information classes ---------------------------------------------------

  static const fileDirectoryInformation = 1;
  static const fileBasicInformation = 4;
  static const fileStandardInformation = 5;
  static const fileRenameInformation = 10;
  static const fileDispositionInformation = 13;
  static const fileEndOfFileInformation = 20;
  static const fileAttributeTagInformation = 35;
  static const fileDispositionInformationEx = 64;

  // ---- file attributes -------------------------------------------------------

  static const attributeReadonly = 0x1;
  static const attributeDirectory = 0x10;
  static const attributeNormal = 0x80;
  static const attributeReparsePoint = 0x400;

  /// `OBJ_CASE_INSENSITIVE`.
  static const objCaseInsensitive = 0x40;
}
