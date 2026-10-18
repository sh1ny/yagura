import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../platform/win32_files.dart';
import 'confined_fs.dart';
import 'reparse_tags.dart';

/// [ConfinedFs] on NTFS: the root is opened with `FILE_OPEN_REPARSE_POINT`,
/// refused if it is a reparse point and compared with the stored directory by
/// its final path; every component below it is then opened relative to the
/// handle of its parent (`NtCreateFile` with `RootDirectory`), also without
/// following reparse points, and any that is one fails `sandbox_violation`.
/// Nothing is ever opened by a path that a link could redirect (design D8).
class WindowsConfinedBackend implements ConfinedBackend {
  WindowsConfinedBackend(this.root);

  /// The confined directory (absolute, normalised).
  final String root;

  static final Win32Files _nt = Win32Files.instance;

  static const _read =
      Win32Files.fileTraverse |
      Win32Files.fileReadAttributes |
      Win32Files.synchronize;
  static const _list = _read | Win32Files.fileListDirectory;
  static const _add =
      _read | Win32Files.fileAddFile | Win32Files.fileAddSubdirectory;

  /// Options every open shares: no reparse point is followed, and the handle
  /// is synchronous.
  static const _common =
      Win32Files.fileOpenReparsePoint |
      Win32Files.fileSynchronousIoNonAlert |
      Win32Files.fileOpenForBackupIntent;
  static const _directory = Win32Files.fileDirectoryFile | _common;

  // ---- operations ------------------------------------------------------------

  @override
  ConfinedEntry? stat(ConfinedPath path) {
    if (path.isRoot) {
      final directory = _openDirectory(path, _read);
      if (directory == null) return null;
      try {
        return _entryOf(directory.handle, '', path);
      } finally {
        directory.close();
      }
    }
    final parent = _openDirectory(path.parent, _read);
    if (parent == null) return null;
    try {
      final opened = _create(
        parent.handle,
        path.name,
        access: Win32Files.fileReadAttributes | Win32Files.synchronize,
        disposition: Win32Files.fileOpen,
        options: _common,
      );
      if (_isNotFound(opened.status)) return null;
      if (opened.status < 0) throw _fail(opened.status, path, 'stat');
      try {
        _refuseLink(opened.handle, path, path.parts.length);
        _checkInside(opened.handle, parent.rootFinal, path);
        return _entryOf(opened.handle, path.name, path);
      } finally {
        _nt.ntClose(opened.handle);
      }
    } finally {
      parent.close();
    }
  }

  @override
  List<ConfinedEntry> list(ConfinedPath path) {
    final directory = _openDirectory(path, _list);
    if (directory == null) throw _notFound(path);
    try {
      return _enumerate(directory.handle, path);
    } finally {
      directory.close();
    }
  }

  @override
  ConfinedReader openRead(ConfinedPath path) {
    final parent = _requireParent(path, _read);
    try {
      final handle = _openLeaf(
        parent,
        path,
        access:
            Win32Files.fileReadData |
            Win32Files.fileReadAttributes |
            Win32Files.synchronize,
        disposition: Win32Files.fileOpen,
      ).handle;
      return _Reader(handle, path);
    } finally {
      parent.close();
    }
  }

  @override
  ConfinedWriter openWrite(ConfinedPath path, {required bool exclusive}) {
    if (path.isRoot) throw _notAFile(path);
    final parent = _requireParent(path, _add);
    try {
      final opened = _openLeaf(
        parent,
        path,
        access:
            Win32Files.fileWriteData |
            Win32Files.fileReadAttributes |
            Win32Files.synchronize,
        disposition: exclusive ? Win32Files.fileCreate : Win32Files.fileOpenIf,
      );
      if (!exclusive && opened.information == Win32Files.fileOpened) {
        try {
          _truncate(opened.handle, path);
        } on Object {
          _nt.ntClose(opened.handle);
          rethrow;
        }
      }
      return _Writer(opened.handle, path);
    } finally {
      parent.close();
    }
  }

  @override
  void createDirectory(ConfinedPath path) {
    final rootHandle = _openRootHandle(path, path.isRoot ? _read : _add);
    if (rootHandle == null) throw _notFound(path);
    var current = rootHandle.handle;
    var ownsCurrent = false;
    try {
      for (var i = 0; i < path.parts.length; i++) {
        final opened = _create(
          current,
          path.parts[i],
          access: i == path.parts.length - 1 ? _read : _add,
          disposition: Win32Files.fileOpenIf,
          options: _directory,
        );
        if (opened.status < 0) {
          if (opened.status.toUnsigned(32) == Win32Files.statusNotADirectory) {
            _probeLink(current, path, i);
          }
          throw _fail(opened.status, path, 'create directory');
        }
        if (ownsCurrent) _nt.ntClose(current);
        current = opened.handle;
        ownsCurrent = true;
        _refuseLink(current, path, i + 1);
      }
    } finally {
      if (ownsCurrent) _nt.ntClose(current);
      rootHandle.close();
    }
  }

  @override
  void delete(ConfinedPath path) {
    if (path.isRoot) throw _notAFile(path);
    final parent = _requireParent(path, _read);
    try {
      final opened = _create(
        parent.handle,
        path.name,
        access: _deleteAccess,
        disposition: Win32Files.fileOpen,
        options: _common,
      );
      if (opened.status < 0) throw _fail(opened.status, path, 'delete');
      try {
        _dispose(opened.handle, path);
      } finally {
        _nt.ntClose(opened.handle);
      }
    } finally {
      parent.close();
    }
  }

  @override
  void deleteTree(ConfinedPath path) {
    if (path.isRoot) {
      final directory = _openDirectory(path, _deleteAccess | _list);
      if (directory == null) return;
      try {
        _deleteChildren(directory.handle, path);
        _dispose(directory.handle, path);
      } finally {
        directory.close();
      }
      return;
    }
    final parent = _openDirectory(path.parent, _read);
    if (parent == null) return;
    try {
      _deleteEntry(parent.handle, path.name, path);
    } finally {
      parent.close();
    }
  }

  @override
  void rename(ConfinedPath from, ConfinedPath to) {
    if (from.isRoot || to.isRoot) throw _notAFile(from.isRoot ? from : to);
    final source = _requireParent(from, _read);
    try {
      final target = _openDirectory(to.parent, _add);
      if (target == null) throw _notFound(to);
      try {
        final opened = _create(
          source.handle,
          from.name,
          access:
              Win32Files.delete |
              Win32Files.fileReadAttributes |
              Win32Files.synchronize,
          disposition: Win32Files.fileOpen,
          options: _common,
        );
        if (opened.status < 0) throw _fail(opened.status, from, 'rename');
        try {
          _rename(opened.handle, target.handle, to);
        } finally {
          _nt.ntClose(opened.handle);
        }
      } finally {
        target.close();
      }
    } finally {
      source.close();
    }
  }

  // ---- opening ---------------------------------------------------------------

  static const _deleteAccess =
      Win32Files.delete |
      Win32Files.fileReadAttributes |
      Win32Files.fileWriteAttributes |
      Win32Files.synchronize;

  /// The `\??\` object name of the root.
  String get _ntRootName {
    if (root.startsWith(r'\\?\')) return r'\??\' + root.substring(4);
    if (root.startsWith(r'\\')) return r'\??\UNC\' + root.substring(2);
    return r'\??\' + root;
  }

  /// Opens the root without following it, refuses it if it is a reparse
  /// point, and checks that it is where it should be. Null when it does not
  /// exist.
  _Root? _openRootHandle(ConfinedPath path, int access) {
    final opened = _create(
      0,
      _ntRootName,
      access: access,
      disposition: Win32Files.fileOpen,
      options: _directory,
    );
    if (_isNotFound(opened.status)) return null;
    if (opened.status < 0) throw _fail(opened.status, path, 'open directory');
    try {
      if (_isLink(opened.handle, path)) {
        throw confinedViolation(
          path.requested,
          'the directory "$root" is a link or junction',
        );
      }
      final actual = _finalPath(opened.handle);
      if (!_sameLocation(actual)) {
        throw confinedViolation(
          path.requested,
          'the directory "$root" resolves to "$actual"',
        );
      }
      return _Root(opened.handle, actual);
    } on Object {
      _nt.ntClose(opened.handle);
      rethrow;
    }
  }

  /// Opens the directory [path] below the root, one component at a time from
  /// its parent. [access] applies to the directory itself; the root and the
  /// directories on the way are opened for traversal only. Null when it does
  /// not exist.
  _Directory? _openDirectory(ConfinedPath path, int access) {
    final rootHandle = _openRootHandle(path, path.isRoot ? access : _read);
    if (rootHandle == null) return null;
    var current = rootHandle.handle;
    var ownsCurrent = false;
    try {
      for (var i = 0; i < path.parts.length; i++) {
        final opened = _create(
          current,
          path.parts[i],
          access: i == path.parts.length - 1 ? access : _read,
          disposition: Win32Files.fileOpen,
          options: _directory,
        );
        if (opened.status < 0) {
          final notADirectory =
              opened.status.toUnsigned(32) == Win32Files.statusNotADirectory;
          // Not a directory: a link planted where one was expected is a
          // violation, anything else just is not there.
          if (notADirectory) _probeLink(current, path, i);
          if (notADirectory || _isNotFound(opened.status)) {
            if (ownsCurrent) _nt.ntClose(current);
            rootHandle.close();
            return null;
          }
          throw _fail(opened.status, path, 'open directory');
        }
        if (ownsCurrent) _nt.ntClose(current);
        current = opened.handle;
        ownsCurrent = true;
        _refuseLink(current, path, i + 1);
      }
      if (!path.isRoot) _checkInside(current, rootHandle.finalPath, path);
      return _Directory(current, rootHandle);
    } on Object {
      if (ownsCurrent) _nt.ntClose(current);
      rootHandle.close();
      rethrow;
    }
  }

  _Directory _requireParent(ConfinedPath path, int access) {
    if (path.isRoot) throw _notAFile(path);
    return _openDirectory(path.parent, access) ?? (throw _notFound(path));
  }

  /// Opens the file [path.name] of [parent] and checks that it is no link.
  _Opened _openLeaf(
    _Directory parent,
    ConfinedPath path, {
    required int access,
    required int disposition,
  }) {
    final opened = _create(
      parent.handle,
      path.name,
      access: access,
      disposition: disposition,
      options: _common,
    );
    if (opened.status < 0) throw _fail(opened.status, path, 'open');
    try {
      _refuseLink(opened.handle, path, path.parts.length);
      _checkInside(opened.handle, parent.rootFinal, path);
      if (_attributes(opened.handle, path) & Win32Files.attributeDirectory !=
          0) {
        throw FileSystemException(
          'is a directory',
          path.toString(),
          const OSError('Is a directory', 21),
        );
      }
      return opened;
    } on Object {
      _nt.ntClose(opened.handle);
      rethrow;
    }
  }

  /// Fails `sandbox_violation` when the component [index] of [path], looked
  /// up in the directory [parent], is a link (of any kind).
  void _probeLink(int parent, ConfinedPath path, int index) {
    final probe = _create(
      parent,
      path.parts[index],
      access: Win32Files.fileReadAttributes | Win32Files.synchronize,
      disposition: Win32Files.fileOpen,
      options: _common,
    );
    if (probe.status < 0) return;
    try {
      _refuseLink(probe.handle, path, index + 1);
    } finally {
      _nt.ntClose(probe.handle);
    }
  }

  // ---- checks ----------------------------------------------------------------

  /// Fails `sandbox_violation` naming the first [count] components of [path]
  /// when [handle] is a reparse point. The caller closes [handle].
  void _refuseLink(int handle, ConfinedPath path, int count) {
    final (attributes, tag) = _attributeTag(handle, path);
    if (!_linkLike(attributes, tag)) return;
    final isDirectory = attributes & Win32Files.attributeDirectory != 0;
    throw confinedViolation(
      path.requested,
      '"${path.prefix(count)}${isDirectory ? '/' : ''}" is a link or junction'
      ' (${describeReparseTag(tag)})',
    );
  }

  /// Fails `sandbox_violation` unless the final path of [handle] lies below
  /// [rootFinal], the final path of the root.
  void _checkInside(int handle, String rootFinal, ConfinedPath path) {
    final actual = _finalPath(handle);
    if (!_startsWith(actual, '${_trim(rootFinal)}\\')) {
      throw confinedViolation(
        path.requested,
        'it resolves to "$actual", outside the directory "$root"',
      );
    }
  }

  bool _sameLocation(String actual) {
    final want = _trim(root);
    if (_equal(actual, want)) return true;
    final long = _longPath(want);
    return long != null && _equal(actual, long);
  }

  static String _trim(String path) => path.length > 3 && path.endsWith(r'\')
      ? path.substring(0, path.length - 1)
      : path;

  static bool _equal(String a, String b) =>
      _trim(a).toLowerCase() == _trim(b).toLowerCase();

  static bool _startsWith(String path, String prefix) =>
      path.toLowerCase().startsWith(prefix.toLowerCase());

  /// [path] with its 8.3 short names expanded; lexical, no link is followed.
  String? _longPath(String path) => using((arena) {
    const capacity = 32768;
    final buffer = arena<Uint16>(capacity).cast<Utf16>();
    final length = _nt.getLongPathName(
      path.toNativeUtf16(allocator: arena),
      buffer,
      capacity,
    );
    if (length == 0 || length > capacity) return null;
    return buffer.toDartString(length: length);
  });

  /// The path [handle] was opened as, in its normalised long form without the
  /// `\\?\` prefix.
  String _finalPath(int handle) => using((arena) {
    const capacity = 32768;
    final buffer = arena<Uint16>(capacity).cast<Utf16>();
    final length = _nt.getFinalPathNameByHandle(handle, buffer, capacity, 0);
    if (length == 0 || length > capacity) {
      throw FileSystemException('cannot get the final path of a handle');
    }
    final text = buffer.toDartString(length: length);
    if (text.startsWith(r'\\?\UNC\')) return '\\\\${text.substring(8)}';
    if (text.startsWith(r'\\?\')) return text.substring(4);
    return text;
  });

  // ---- native calls ----------------------------------------------------------

  /// `NtCreateFile` for [name] relative to the directory [parent] (0 for an
  /// absolute `\??\` name).
  _Opened _create(
    int parent,
    String name, {
    required int access,
    required int disposition,
    required int options,
  }) => using((arena) {
    final length = name.length * 2;
    final text = name.toNativeUtf16(allocator: arena);
    final unicode = arena<Uint8>(16);
    unicode.cast<Uint16>().value = length;
    (unicode + 2).cast<Uint16>().value = length + 2;
    (unicode + 8).cast<IntPtr>().value = text.address;
    final attributes = arena<Uint8>(48);
    attributes.cast<Uint32>().value = 48;
    (attributes + 8).cast<IntPtr>().value = parent;
    (attributes + 16).cast<IntPtr>().value = unicode.address;
    (attributes + 24).cast<Uint32>().value = Win32Files.objCaseInsensitive;
    final handle = arena<IntPtr>();
    final block = arena<Uint8>(16);
    final status = _nt.ntCreateFile(
      handle,
      access,
      attributes.cast(),
      block.cast(),
      nullptr,
      0,
      7,
      disposition,
      options,
      nullptr,
      0,
    );
    return _Opened(
      status,
      status >= 0 ? handle.value : 0,
      status >= 0 ? (block + 8).cast<IntPtr>().value : 0,
    );
  });

  /// Whether a name with these [attributes] and reparse [tag] redirects
  /// (design D8); a data-only reparse point (WOF, dedup) is a plain file.
  static bool _linkLike(int attributes, int tag) =>
      attributes & Win32Files.attributeReparsePoint != 0 &&
      isLinkReparseTag(tag);

  bool _isLink(int handle, ConfinedPath path) {
    final (attributes, tag) = _attributeTag(handle, path);
    return _linkLike(attributes, tag);
  }

  int _attributes(int handle, ConfinedPath path) =>
      _attributeTag(handle, path).$1;

  /// The file attributes of [handle] and, for a reparse point, its tag.
  (int, int) _attributeTag(int handle, ConfinedPath path) => using((arena) {
    final block = arena<Uint8>(16);
    final info = arena<Uint8>(8);
    final status = _nt.ntQueryInformationFile(
      handle,
      block.cast(),
      info.cast(),
      8,
      Win32Files.fileAttributeTagInformation,
    );
    if (status < 0) throw _fail(status, path, 'query attributes');
    return (info.cast<Uint32>().value, (info + 4).cast<Uint32>().value);
  });

  ConfinedEntry _entryOf(int handle, String name, ConfinedPath path) =>
      using((arena) {
        final (attributes, tag) = _attributeTag(handle, path);
        final block = arena<Uint8>(16);
        final basic = arena<Uint8>(40);
        var status = _nt.ntQueryInformationFile(
          handle,
          block.cast(),
          basic.cast(),
          40,
          Win32Files.fileBasicInformation,
        );
        if (status < 0) throw _fail(status, path, 'query times');
        final standard = arena<Uint8>(24);
        status = _nt.ntQueryInformationFile(
          handle,
          block.cast(),
          standard.cast(),
          24,
          Win32Files.fileStandardInformation,
        );
        if (status < 0) throw _fail(status, path, 'query size');
        final isDirectory = attributes & Win32Files.attributeDirectory != 0;
        return ConfinedEntry(
          name: name,
          isDirectory: isDirectory,
          isLink: _linkLike(attributes, tag),
          size: isDirectory ? 0 : (standard + 8).cast<Int64>().value,
          modified: _time((basic + 16).cast<Int64>().value),
          created: _time(basic.cast<Int64>().value),
        );
      });

  static DateTime _time(int fileTime) => DateTime.fromMicrosecondsSinceEpoch(
    (fileTime - 116444736000000000) ~/ 10,
    isUtc: true,
  );

  /// The entries of the directory [handle], links reported and not followed.
  List<ConfinedEntry> _enumerate(int handle, ConfinedPath path) => using((
    arena,
  ) {
    const capacity = 64 * 1024;
    final buffer = arena<Uint8>(capacity);
    final block = arena<Uint8>(16);
    final entries = <ConfinedEntry>[];
    var restart = 1;
    while (true) {
      final status = _nt.ntQueryDirectoryFile(
        handle,
        0,
        nullptr,
        nullptr,
        block.cast(),
        buffer.cast(),
        capacity,
        Win32Files.fileFullDirectoryInformation,
        0,
        nullptr,
        restart,
      );
      restart = 0;
      if (status.toUnsigned(32) == Win32Files.statusNoMoreFiles) break;
      if (status < 0) throw _fail(status, path, 'list');
      var offset = 0;
      while (true) {
        final entry = buffer + offset;
        final next = entry.cast<Uint32>().value;
        final attributes = (entry + 56).cast<Uint32>().value;
        final nameBytes = (entry + 60).cast<Uint32>().value;
        // For a reparse point, `EaSize` holds the reparse tag.
        final tag = (entry + 64).cast<Uint32>().value;
        final name = (entry + 68).cast<Utf16>().toDartString(
          length: nameBytes ~/ 2,
        );
        if (name != '.' && name != '..') {
          final isDirectory = attributes & Win32Files.attributeDirectory != 0;
          final isLink = _linkLike(attributes, tag);
          entries.add(
            ConfinedEntry(
              name: name,
              isDirectory: isDirectory,
              isLink: isLink,
              size: isDirectory || isLink
                  ? 0
                  : (entry + 40).cast<Int64>().value,
              modified: _time((entry + 24).cast<Int64>().value),
              created: _time((entry + 8).cast<Int64>().value),
            ),
          );
        }
        if (next == 0) break;
        offset += next;
      }
    }
    return entries;
  });

  void _truncate(int handle, ConfinedPath path) => using((arena) {
    final block = arena<Uint8>(16);
    final info = arena<Int64>();
    final status = _nt.ntSetInformationFile(
      handle,
      block.cast(),
      info.cast(),
      8,
      Win32Files.fileEndOfFileInformation,
    );
    if (status < 0) throw _fail(status, path, 'truncate');
  });

  /// Marks [handle] for deletion: the name goes at once, links included
  /// (a link is removed itself, never followed).
  void _dispose(int handle, ConfinedPath path) => using((arena) {
    final block = arena<Uint8>(16);
    final flags = arena<Uint32>()..value = 0x1 | 0x2 | 0x10;
    var status = _nt.ntSetInformationFile(
      handle,
      block.cast(),
      flags.cast(),
      4,
      Win32Files.fileDispositionInformationEx,
    );
    if (status >= 0) return;
    final code = status.toUnsigned(32);
    // Not supported by this Windows (before 1809): plain disposition.
    if (code != 0xC0000003 && code != 0xC00000BB && code != 0xC000000D) {
      throw _fail(status, path, 'delete');
    }
    final mark = arena<Uint8>()..value = 1;
    status = _nt.ntSetInformationFile(
      handle,
      block.cast(),
      mark.cast(),
      1,
      Win32Files.fileDispositionInformation,
    );
    if (status.toUnsigned(32) == Win32Files.statusCannotDelete) {
      // A read-only file: clear the attribute and try again.
      final basic = arena<Uint8>(40);
      (basic + 32).cast<Uint32>().value = Win32Files.attributeNormal;
      _nt.ntSetInformationFile(
        handle,
        block.cast(),
        basic.cast(),
        40,
        Win32Files.fileBasicInformation,
      );
      status = _nt.ntSetInformationFile(
        handle,
        block.cast(),
        mark.cast(),
        1,
        Win32Files.fileDispositionInformation,
      );
    }
    if (status < 0) throw _fail(status, path, 'delete');
  });

  void _rename(int handle, int directory, ConfinedPath to) => using((arena) {
    final name = to.name;
    final nameBytes = name.length * 2;
    final info = arena<Uint8>(24 + nameBytes);
    info.value = 1; // ReplaceIfExists
    (info + 8).cast<IntPtr>().value = directory;
    (info + 16).cast<Uint32>().value = nameBytes;
    final text = (info + 20).cast<Uint16>();
    for (var i = 0; i < name.length; i++) {
      text[i] = name.codeUnitAt(i);
    }
    final block = arena<Uint8>(16);
    final status = _nt.ntSetInformationFile(
      handle,
      block.cast(),
      info.cast(),
      20 + nameBytes,
      Win32Files.fileRenameInformation,
    );
    if (status < 0) throw _fail(status, to, 'rename');
  });

  // ---- deleting --------------------------------------------------------------

  /// Deletes the child [name] of [parent]: a link is removed itself and never
  /// entered, a directory is emptied first. Missing is fine.
  void _deleteEntry(int parent, String name, ConfinedPath path) {
    final opened = _create(
      parent,
      name,
      access: _deleteAccess,
      disposition: Win32Files.fileOpen,
      options: _common,
    );
    if (_isNotFound(opened.status)) return;
    if (opened.status < 0) throw _fail(opened.status, path, 'delete');
    try {
      final (attributes, tag) = _attributeTag(opened.handle, path);
      final isDirectory = attributes & Win32Files.attributeDirectory != 0;
      final isLink = _linkLike(attributes, tag);
      if (isDirectory && !isLink) {
        final listing = _create(
          parent,
          name,
          access: _list,
          disposition: Win32Files.fileOpen,
          options: _directory,
        );
        if (listing.status < 0) throw _fail(listing.status, path, 'delete');
        try {
          // The directory may have been swapped for a link since it was
          // opened for deletion: look again, on the handle used to list.
          if (!_isLink(listing.handle, path)) {
            _deleteChildren(listing.handle, path);
          }
        } finally {
          _nt.ntClose(listing.handle);
        }
      }
      _dispose(opened.handle, path);
    } finally {
      _nt.ntClose(opened.handle);
    }
  }

  void _deleteChildren(int directory, ConfinedPath path) {
    for (final child in _enumerate(directory, path)) {
      _deleteEntry(directory, child.name, path.child(child.name));
    }
  }

  // ---- errors ----------------------------------------------------------------

  static bool _isNotFound(int status) => const {
    Win32Files.statusObjectNameNotFound,
    Win32Files.statusObjectPathNotFound,
    Win32Files.statusNoSuchFile,
  }.contains(status.toUnsigned(32));

  FileSystemException _notFound(ConfinedPath path) => FileSystemException(
    'no such file or directory',
    path.isRoot ? root : path.toString(),
    const OSError('The system cannot find the file specified.', 2),
  );

  FileSystemException _notAFile(ConfinedPath path) => FileSystemException(
    'not a file',
    path.isRoot ? root : path.toString(),
    const OSError('Access is denied.', 5),
  );

  FileSystemException _fail(int status, ConfinedPath path, String operation) {
    final code = _nt.rtlNtStatusToDosError(status);
    final message = switch (code) {
      2 => 'The system cannot find the file specified.',
      3 => 'The system cannot find the path specified.',
      5 => 'Access is denied.',
      32 =>
        'The process cannot access the file because it is being used by '
            'another process.',
      80 || 183 => 'The file exists.',
      145 => 'The directory is not empty.',
      _ =>
        'Windows error $code (NTSTATUS 0x'
            '${status.toUnsigned(32).toRadixString(16)})',
    };
    return FileSystemException(
      '$operation failed',
      path.isRoot ? root : path.toString(),
      OSError(message, code),
    );
  }
}

class _Opened {
  const _Opened(this.status, this.handle, this.information);

  final int status;
  final int handle;
  final int information;
}

class _Root {
  _Root(this.handle, this.finalPath);

  final int handle;

  /// The root's own final path, which everything below must stay under.
  final String finalPath;

  void close() => Win32Files.instance.ntClose(handle);
}

/// A directory handle together with the root handle it was reached from.
class _Directory {
  _Directory(this.handle, this._root);

  final int handle;
  final _Root _root;

  String get rootFinal => _root.finalPath;

  void close() {
    if (handle != _root.handle) Win32Files.instance.ntClose(handle);
    _root.close();
  }
}

class _Reader implements ConfinedReader {
  _Reader(this._handle, this._path);

  int _handle;
  final ConfinedPath _path;

  @override
  int get length => using((arena) {
    final block = arena<Uint8>(16);
    final standard = arena<Uint8>(24);
    final status = Win32Files.instance.ntQueryInformationFile(
      _handle,
      block.cast(),
      standard.cast(),
      24,
      Win32Files.fileStandardInformation,
    );
    if (status < 0) throw _statusError(status, _path, 'query size');
    return (standard + 8).cast<Int64>().value;
  });

  @override
  Uint8List readAt(int offset, int count) {
    if (count <= 0) return Uint8List(0);
    return using((arena) {
      final buffer = arena<Uint8>(count);
      final block = arena<Uint8>(16);
      final at = arena<Int64>()..value = offset;
      final status = Win32Files.instance.ntReadFile(
        _handle,
        0,
        nullptr,
        nullptr,
        block.cast(),
        buffer,
        count,
        at,
        nullptr,
      );
      if (status.toUnsigned(32) == Win32Files.statusEndOfFile) {
        return Uint8List(0);
      }
      if (status < 0) throw _statusError(status, _path, 'read');
      final read = (block + 8).cast<IntPtr>().value;
      return Uint8List.fromList(buffer.asTypedList(read));
    });
  }

  @override
  void close() {
    if (_handle == 0) return;
    Win32Files.instance.ntClose(_handle);
    _handle = 0;
  }
}

class _Writer implements ConfinedWriter {
  _Writer(this._handle, this._path);

  int _handle;
  final ConfinedPath _path;

  @override
  void add(List<int> bytes) {
    const chunk = 1024 * 1024;
    for (var start = 0; start < bytes.length; start += chunk) {
      final end = start + chunk < bytes.length ? start + chunk : bytes.length;
      using((arena) {
        final count = end - start;
        final buffer = arena<Uint8>(count);
        buffer.asTypedList(count).setRange(0, count, bytes, start);
        final block = arena<Uint8>(16);
        final status = Win32Files.instance.ntWriteFile(
          _handle,
          0,
          nullptr,
          nullptr,
          block.cast(),
          buffer,
          count,
          nullptr,
          nullptr,
        );
        if (status < 0) throw _statusError(status, _path, 'write');
      });
    }
  }

  @override
  void close() {
    if (_handle == 0) return;
    final handle = _handle;
    _handle = 0;
    try {
      using((arena) {
        final block = arena<Uint8>(16);
        final status = Win32Files.instance.ntFlushBuffersFile(
          handle,
          block.cast(),
        );
        if (status < 0) throw _statusError(status, _path, 'flush');
      });
    } finally {
      Win32Files.instance.ntClose(handle);
    }
  }
}

FileSystemException _statusError(
  int status,
  ConfinedPath path,
  String operation,
) {
  final code = Win32Files.instance.rtlNtStatusToDosError(status);
  return FileSystemException(
    '$operation failed',
    path.toString(),
    OSError('Windows error $code', code),
  );
}
