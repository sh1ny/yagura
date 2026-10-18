import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'win32.dart';
import 'win32_files.dart';
import 'win32_security.dart' show Win32Error;

/// A path that cannot be used as asked, with the reason.
class PathRefused implements Exception {
  PathRefused(this.path, this.why);

  final String path;
  final String why;

  @override
  String toString() => '$path: $why';
}

const _readControl = 0x00020000;
const _writeOwner = 0x00080000;
const _errorFileNotFound = 2;
const _errorPathNotFound = 3;
const _errorInvalidName = 123;
const _errorNotADirectory = 267;

/// Share read and write, but not delete: nobody can delete or rename the
/// directory while it is held.
const _shareReadWrite = 0x3;
const _shareAll = 0x7;

/// `FILE_ATTRIBUTE_DIRECTORY`, `FILE_ATTRIBUTE_REPARSE_POINT`.
const _attributeDirectory = 0x10;
const _attributeReparsePoint = 0x400;

/// Opens [path]; with [followLink] false a link at the end is opened itself.
({int handle, int error}) _open(
  String path, {
  required int access,
  required int share,
  required bool followLink,
}) {
  final text = path.toNativeUtf16();
  try {
    final call = callReadingError(
      () => Win32.instance.createFile(
        text,
        access,
        share,
        nullptr,
        Win32.openExisting,
        Win32.fileFlagBackupSemantics |
            (followLink ? 0 : Win32.fileFlagOpenReparsePoint),
        0,
      ),
      (h) => h == Win32.invalidHandle,
    );
    return (handle: call.value, error: call.error);
  } finally {
    calloc.free(text);
  }
}

/// The name [handle] was opened as, in its normalised long form, without the
/// `\\?\` prefix: links in the path are resolved, short names are expanded
/// and the case is the one on disk.
String finalPathOfHandle(int handle) => using((arena) {
  const capacity = 32768;
  final buffer = arena<Uint16>(capacity).cast<Utf16>();
  final length = Win32Files.instance.getFinalPathNameByHandle(
    handle,
    buffer,
    capacity,
    0,
  );
  if (length == 0 || length > capacity) {
    throw Win32Error('GetFinalPathNameByHandleW', 0);
  }
  final text = buffer.toDartString(length: length);
  if (text.startsWith(r'\\?\UNC\')) return '\\\\${text.substring(8)}';
  if (text.startsWith(r'\\?\')) return text.substring(4);
  return text;
});

/// [path] with its 8.3 short names expanded; lexical, no link is followed.
String? _longPath(String path) => using((arena) {
  const capacity = 32768;
  final buffer = arena<Uint16>(capacity).cast<Utf16>();
  final length = Win32Files.instance.getLongPathName(
    path.toNativeUtf16(allocator: arena),
    buffer,
    capacity,
  );
  if (length == 0 || length > capacity) return null;
  return buffer.toDartString(length: length);
});

/// [path] as the file system names it: links in the folders above are
/// resolved, short names expanded, the case that is on disk. The part that
/// does not exist yet is kept as given. A path that cannot be resolved is
/// returned as it is.
String resolveExistingPrefix(String path) {
  var current = path;
  final rest = <String>[];
  while (true) {
    final opened = _open(
      current,
      access: Win32Files.fileReadAttributes | Win32Files.synchronize,
      share: _shareAll,
      followLink: true,
    );
    if (opened.handle != Win32.invalidHandle) {
      try {
        final resolved = finalPathOfHandle(opened.handle);
        return rest.isEmpty
            ? resolved
            : p.joinAll([resolved, ...rest.reversed]);
      } on Win32Error {
        return path;
      } finally {
        Win32.instance.closeHandle(opened.handle);
      }
    }
    if (opened.error != _errorFileNotFound &&
        opened.error != _errorPathNotFound &&
        opened.error != _errorNotADirectory) {
      return path;
    }
    final parent = p.dirname(current);
    if (parent == current) return path;
    rest.add(p.basename(current));
    current = parent;
  }
}

/// A directory held open for checking and then protecting.
class OpenedDirectory {
  OpenedDirectory._(this.handle, this.path);

  final int handle;

  /// The directory's real name.
  final String path;

  void close() => Win32.instance.closeHandle(handle);
}

/// Opens the directory [path] (absolute, normalised) by handle, for reading
/// and writing its security, so that what is checked is what is changed:
///
///  * a link at [path] is opened itself, and refused;
///  * a link in a folder above it makes the name the handle reports differ
///    from [path], and is refused;
///  * what is not a directory is refused;
///  * nobody can delete or rename it while the handle is held (no
///    `FILE_SHARE_DELETE`).
OpenedDirectory openDirectoryForProtection(String path) {
  final opened = _open(
    path,
    // Listing is data access: a handle with attribute and security access
    // only takes no part in sharing checks, and would not stop a rename.
    access:
        Win32Files.fileListDirectory |
        Win32Files.fileReadAttributes |
        Win32Files.synchronize |
        _readControl |
        Win32.writeDac |
        _writeOwner,
    share: _shareReadWrite,
    followLink: false,
  );
  final handle = opened.handle;
  if (handle == Win32.invalidHandle) {
    final why = switch (opened.error) {
      _errorFileNotFound || _errorPathNotFound => 'it does not exist',
      _errorInvalidName => 'it is not a valid name',
      5 => 'access is denied (administrator rights are needed)',
      _ => 'it cannot be opened (error ${opened.error})',
    };
    throw PathRefused(path, why);
  }
  try {
    final info = calloc<Uint8>(52);
    try {
      if (Win32Files.instance.getFileInformationByHandle(handle, info) == 0) {
        throw PathRefused(path, 'its attributes cannot be read');
      }
      final attributes = info.cast<Uint32>().value;
      if (attributes & _attributeReparsePoint != 0) {
        throw PathRefused(path, 'it is a link, not a directory');
      }
      if (attributes & _attributeDirectory == 0) {
        throw PathRefused(path, 'it is not a directory');
      }
    } finally {
      calloc.free(info);
    }
    final real = finalPathOfHandle(handle);
    final asked = _longPath(path) ?? path;
    if (real.toLowerCase() != asked.toLowerCase()) {
      throw PathRefused(
        path,
        'a folder in its path is a link (it leads to $real)',
      );
    }
    return OpenedDirectory._(handle, real);
  } on Object {
    Win32.instance.closeHandle(handle);
    rethrow;
  }
}
