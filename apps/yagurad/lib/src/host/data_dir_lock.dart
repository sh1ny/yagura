import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../platform/win32_lock_file.dart';
import 'data_dir_protector.dart' show dataDirNotProtected;

/// The OS exclusive lock on `yagurad.lock` (design D9).
///
/// The holder writes its PID at offset 0 and locks the single byte at offset
/// 2^32, far past the PID, so a refused daemon can still read the PID (a
/// byte-range lock blocks access to the locked range only). The OS releases
/// the lock when the holder dies, so a file left behind by a crashed daemon
/// does not block a new one.
///
/// On Windows the file is opened with `CreateFileW` and
/// `FILE_FLAG_OPEN_REPARSE_POINT` and locked with `LockFileEx`
/// ([Win32LockFile]): a link at the path is never followed, and a link, a
/// directory or a file with several names is refused with
/// `data_dir_not_protected` before anything is locked or written (design D6:
/// the file is opened before the data directory is protected).
///
/// On Linux `dart:io` locks with `fcntl`, whose locks belong to the process:
/// a second lock from the same process succeeds, and closing any handle to
/// the file drops the lock. Locks this process holds are therefore also kept
/// in [_held] and checked before the file is opened.
class DataDirLock {
  DataDirLock._(this._file, this._native);

  /// Offset of the locked byte.
  static const lockOffset = 1 << 32;

  /// Canonical paths of the lock files this process holds.
  static final _held = <String>{};

  final RandomAccessFile? _file;
  final Win32LockFile? _native;
  late final String _key;
  var _released = false;

  /// Takes the lock and records this process's PID. Throws `data_dir_locked`
  /// with the holder's PID in `details['pid']` when another process holds it.
  static DataDirLock acquire(String lockPath) {
    final key = _canonical(lockPath);
    if (_held.contains(key)) throw _locked(lockPath, pid);
    final DataDirLock lock;
    if (Platform.isWindows) {
      final Win32LockFile native;
      try {
        native = Win32LockFile.open(lockPath, offset: lockOffset);
      } on LockFileLocked {
        throw _locked(lockPath, _readPid(lockPath));
      } on LockFileRefused catch (e) {
        throw dataDirNotProtected(lockPath, 'the lock file: ${e.why}');
      } on LockFileFailed catch (e) {
        throw lockFileUnusable(lockPath, e);
      }
      try {
        native.writeText('$pid\n');
      } on LockFileFailed catch (e) {
        native.close(offset: lockOffset);
        throw lockFileUnusable(lockPath, e);
      } on Object {
        native.close(offset: lockOffset);
        rethrow;
      }
      lock = DataDirLock._(null, native);
    } else {
      // Append mode creates the file without truncating the holder's PID.
      final file = File(lockPath).openSync(mode: FileMode.append);
      try {
        file.lockSync(FileLock.exclusive, lockOffset, lockOffset + 1);
      } on FileSystemException {
        file.closeSync();
        throw _locked(lockPath, _readPid(lockPath));
      }
      file
        ..truncateSync(0)
        // Append mode leaves the position at the old end on Linux.
        ..setPositionSync(0)
        ..writeStringSync('$pid\n')
        ..flushSync();
      lock = DataDirLock._(file, null);
    }
    _held.add(key);
    return lock.._key = key;
  }

  /// The `data_dir_unwritable` for a lock file that could not be opened,
  /// locked or written, naming the file and the Win32 error.
  static YaguraException lockFileUnusable(
    String lockPath,
    LockFileFailed failure,
  ) => YaguraException(
    'data_dir_unwritable',
    'the data directory lock file cannot be used: $lockPath: $failure',
    details: {'path': lockPath, 'error': failure.error},
  );

  static YaguraException _locked(String lockPath, int? holder) =>
      YaguraException(
        'data_dir_locked',
        'another yagurad holds the data directory lock'
            '${holder == null ? '' : ' (PID $holder)'}: $lockPath',
        details: {'path': lockPath, 'pid': ?holder},
      );

  static String _canonical(String lockPath) {
    final absolute = p.normalize(p.absolute(lockPath));
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  static int? _readPid(String lockPath) {
    try {
      return int.tryParse(File(lockPath).readAsStringSync().trim());
    } on FileSystemException {
      return null;
    }
  }

  /// Releases the lock (the OS does so anyway when the process ends).
  void release() {
    if (_released) return;
    _released = true;
    if (_native case final native?) {
      native.close(offset: lockOffset);
    } else if (_file case final file?) {
      try {
        file.unlockSync(lockOffset, lockOffset + 1);
      } on FileSystemException {
        // Closing the file releases it.
      }
      file.closeSync();
    }
    _held.remove(_key);
  }
}
