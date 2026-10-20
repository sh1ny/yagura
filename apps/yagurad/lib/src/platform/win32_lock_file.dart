import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'win32.dart';
import 'win32_files.dart';

/// Why a lock file is refused: it is a link, a directory or a file with several
/// names, so nothing was locked or written.
class LockFileRefused implements Exception {
  const LockFileRefused(this.why);

  final String why;

  @override
  String toString() => why;
}

/// A call on the lock file failed with a Win32 error (a read-only volume, a
/// full disk, access denied, a sharing violation): the file is not a danger,
/// it cannot be used.
class LockFileFailed implements Exception {
  const LockFileFailed(this.call, this.error);

  final String call;
  final int error;

  @override
  String toString() => '$call failed with error $error';
}

/// The lock file is locked by another process.
class LockFileLocked implements Exception {
  const LockFileLocked();
}

/// A file opened and byte-range locked through `CreateFileW` and `LockFileEx`
/// (design D6, D9). The open uses `FILE_FLAG_OPEN_REPARSE_POINT`, so a link
/// at the path is opened itself, never followed; the handle is checked (not a
/// reparse point, not a directory, one name) before anything is locked or
/// written. Windows only.
class Win32LockFile {
  Win32LockFile._(this._handle);

  static final _kernel = DynamicLibrary.open('kernel32.dll');

  static final _lockFileEx = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Uint32, Uint32, Uint32, Pointer<Void>),
        int Function(int, int, int, int, int, Pointer<Void>)
      >('LockFileEx');
  static final _unlockFileEx = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Uint32, Uint32, Pointer<Void>),
        int Function(int, int, int, int, Pointer<Void>)
      >('UnlockFileEx');
  static final _setFilePointerEx = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Int64, Pointer<Int64>, Uint32),
        int Function(int, int, Pointer<Int64>, int)
      >('SetFilePointerEx');
  static final _setEndOfFile = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetEndOfFile',
      );
  static final _writeFile = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');
  static final _flush = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'FlushFileBuffers',
      );

  static const _genericReadWrite = 0xC0000000;
  static const _openAlways = 4;
  static const _lockFailImmediately = 1;
  static const _lockExclusive = 2;
  static const _errorLockViolation = 33;
  static const _attributeDirectory = 0x10;
  static const _attributeReparsePoint = 0x400;

  final int _handle;
  var _closed = false;

  /// Opens or creates [path] without following a link, refuses a link, a
  /// directory and a file with several names, and locks the byte at [offset]
  /// exclusively. Throws [LockFileRefused] or [LockFileLocked]; the file is
  /// not written.
  static Win32LockFile open(String path, {required int offset}) {
    final win32 = Win32.instance;
    final name = path.toNativeUtf16();
    try {
      final opened = callReadingError(
        () => win32.createFile(
          name,
          _genericReadWrite,
          Win32.fileShareReadWrite,
          nullptr,
          _openAlways,
          Win32.fileFlagOpenReparsePoint,
          0,
        ),
        (h) => h == Win32.invalidHandle,
      );
      if (opened.value == Win32.invalidHandle) {
        throw LockFileFailed('CreateFileW', opened.error);
      }
      final handle = opened.value;
      try {
        final info = calloc<Uint8>(52);
        try {
          if (Win32Files.instance.getFileInformationByHandle(handle, info) ==
              0) {
            throw LockFileFailed(
              'GetFileInformationByHandle',
              win32.getLastError(),
            );
          }
          final attributes = info.cast<Uint32>().value;
          // BY_HANDLE_FILE_INFORMATION.nNumberOfLinks is at byte 40.
          final links = (info + 40).cast<Uint32>().value;
          if (attributes & _attributeReparsePoint != 0) {
            throw const LockFileRefused('it is a link');
          }
          if (attributes & _attributeDirectory != 0) {
            throw const LockFileRefused('it is a directory');
          }
          if (links != 1) {
            throw const LockFileRefused('it is a file with several hard links');
          }
        } finally {
          calloc.free(info);
        }
        final overlapped = _overlappedAt(offset);
        try {
          final lock = callReadingError(
            () => _lockFileEx(
              handle,
              _lockExclusive | _lockFailImmediately,
              0,
              1,
              0,
              overlapped.cast(),
            ),
            (r) => r == 0,
          );
          if (lock.value == 0) {
            if (lock.error == _errorLockViolation) {
              throw const LockFileLocked();
            }
            throw LockFileFailed('LockFileEx', lock.error);
          }
        } finally {
          calloc.free(overlapped);
        }
      } on Object {
        win32.closeHandle(handle);
        rethrow;
      }
      return Win32LockFile._(handle);
    } finally {
      calloc.free(name);
    }
  }

  static Pointer<Uint8> _overlappedAt(int offset) {
    // OVERLAPPED: Internal, InternalHigh (8 bytes each), Offset, OffsetHigh,
    // hEvent; 32 bytes on 64-bit.
    final overlapped = calloc<Uint8>(32);
    (overlapped + 16).cast<Uint32>().value = offset & 0xFFFFFFFF;
    (overlapped + 20).cast<Uint32>().value = offset >> 32;
    return overlapped;
  }

  /// Replaces the content with [text] (the lock itself is far past it).
  void writeText(String text) {
    final bytes = text.codeUnits;
    final buffer = calloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      if (_setFilePointerEx(_handle, 0, nullptr, 0) == 0 ||
          _setEndOfFile(_handle) == 0 ||
          _writeFile(_handle, buffer, bytes.length, written, nullptr) == 0) {
        throw LockFileFailed('WriteFile', Win32.instance.getLastError());
      }
      _flush(_handle);
    } finally {
      calloc.free(buffer);
      calloc.free(written);
    }
  }

  /// Unlocks the byte at [offset] and closes the handle.
  void close({required int offset}) {
    if (_closed) return;
    _closed = true;
    final overlapped = _overlappedAt(offset);
    try {
      _unlockFileEx(_handle, 0, 1, 0, overlapped.cast());
    } finally {
      calloc.free(overlapped);
      Win32.instance.closeHandle(_handle);
    }
  }
}
