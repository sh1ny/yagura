import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'win32.dart';

/// Free space on the volume holding a path.
class DiskSpace {
  const DiskSpace({required this.volume, required this.freeBytes});

  /// The volume's root (`C:\`) or mount point (`/var`).
  final String volume;
  final int freeBytes;

  @override
  String toString() => 'DiskSpace($volume, $freeBytes free)';
}

/// Reports the free space of the volume that holds a path. Injectable so
/// tests can make a volume look full.
typedef DiskSpaceProbe = Future<DiskSpace> Function(String path);

/// The free space of the volume holding [path] (which need not exist: its
/// nearest existing ancestor is used).
Future<DiskSpace> probeDiskSpace(String path) async {
  var existing = p.normalize(p.absolute(path));
  while (!Directory(existing).existsSync()) {
    final parent = p.dirname(existing);
    if (parent == existing) break;
    existing = parent;
  }
  return Platform.isWindows ? _windows(existing) : await _posix(existing);
}

DiskSpace _windows(String path) {
  final win = Win32.instance;
  final native = path.toNativeUtf16();
  final root = calloc<Uint16>(520).cast<Utf16>();
  final free = calloc<Uint64>();
  final total = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  try {
    var volume = path;
    if (win.getVolumePathName(native, root, 260) != 0) {
      volume = root.toDartString();
    }
    if (win.getDiskFreeSpaceEx(native, free, total, totalFree) == 0) {
      throw FileSystemException('cannot read the free space', path);
    }
    return DiskSpace(volume: volume, freeBytes: free.value);
  } finally {
    calloc
      ..free(native)
      ..free(root)
      ..free(free)
      ..free(total)
      ..free(totalFree);
  }
}

Future<DiskSpace> _posix(String path) async {
  final result = await Process.run('df', ['-Pk', path]);
  if (result.exitCode != 0) {
    throw FileSystemException('df failed: ${result.stderr}', path);
  }
  // Filesystem 1024-blocks Used Available Capacity Mounted-on
  final lines = (result.stdout as String).trim().split('\n');
  final columns = lines.last.trim().split(RegExp(r'\s+'));
  if (columns.length < 6) {
    throw FileSystemException('unreadable df output', path);
  }
  return DiskSpace(
    volume: columns.sublist(5).join(' '),
    freeBytes: int.parse(columns[3]) * 1024,
  );
}
