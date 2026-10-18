import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'confined_fs.dart';

/// [ConfinedFs] with `dart:io` only, for hosts without the handle-relative
/// walk (the Linux host arrives in M5, which replaces this with `openat`).
///
/// Every component of a path, the root included, is looked at without
/// following links before it is used, and a link fails `sandbox_violation`.
/// Unlike the Windows walk the check and the use are separate steps, so a link
/// planted in between is not caught: this guards against stray links, not a
/// racing hostile process.
class PortableConfinedBackend implements ConfinedBackend {
  PortableConfinedBackend(this.root);

  /// The confined directory (absolute, normalised).
  final String root;

  /// The absolute path of [path] when every component that exists is a plain
  /// directory or file; null when the path or a directory above it is
  /// missing. Fails `sandbox_violation` on a link, the root included.
  String? _checked(ConfinedPath path) {
    var current = root;
    switch (FileSystemEntity.typeSync(current, followLinks: false)) {
      case FileSystemEntityType.link:
        throw confinedViolation(
          path.requested,
          'the directory "$root" is a link or junction',
        );
      case FileSystemEntityType.notFound:
        return null;
      default:
    }
    for (var i = 0; i < path.parts.length; i++) {
      current = p.join(current, path.parts[i]);
      switch (FileSystemEntity.typeSync(current, followLinks: false)) {
        case FileSystemEntityType.link:
          throw confinedViolation(
            path.requested,
            '"${path.prefix(i + 1)}" is a link or junction',
          );
        case FileSystemEntityType.notFound:
          return i == path.parts.length - 1 ? current : null;
        default:
      }
    }
    return current;
  }

  /// [path] checked, as a path that must exist.
  String _existing(ConfinedPath path) {
    final checked = _checked(path);
    if (checked == null ||
        FileSystemEntity.typeSync(checked, followLinks: false) ==
            FileSystemEntityType.notFound) {
      throw FileSystemException(
        'no such file or directory',
        path.isRoot ? root : path.toString(),
        const OSError('No such file or directory', 2),
      );
    }
    return checked;
  }

  /// The checked path of the parent directory of [path], which must exist.
  String _parent(ConfinedPath path) => _existing(path.parent);

  ConfinedEntry _entry(String name, FileSystemEntity entity) {
    final stat = entity.statSync();
    return ConfinedEntry(
      name: name,
      isDirectory: stat.type == FileSystemEntityType.directory,
      isLink: entity is Link,
      size: stat.type == FileSystemEntityType.file ? stat.size : 0,
      modified: stat.modified,
      created: stat.changed,
    );
  }

  @override
  ConfinedEntry? stat(ConfinedPath path) {
    final checked = _checked(path);
    if (checked == null) return null;
    final type = FileSystemEntity.typeSync(checked, followLinks: false);
    return switch (type) {
      FileSystemEntityType.notFound => null,
      FileSystemEntityType.directory => _entry(
        path.isRoot ? '' : path.name,
        Directory(checked),
      ),
      _ => _entry(path.name, File(checked)),
    };
  }

  @override
  List<ConfinedEntry> list(ConfinedPath path) {
    final directory = _existing(path);
    return [
      for (final entity in Directory(directory).listSync(followLinks: false))
        if (entity is Link)
          ConfinedEntry(
            name: p.basename(entity.path),
            isDirectory: false,
            isLink: true,
            size: 0,
            modified: entity.statSync().modified,
            created: entity.statSync().changed,
          )
        else
          _entry(p.basename(entity.path), entity),
    ];
  }

  @override
  ConfinedReader openRead(ConfinedPath path) {
    final file = _existing(path);
    if (FileSystemEntity.isDirectorySync(file)) {
      throw FileSystemException(
        'is a directory',
        path.toString(),
        const OSError('Is a directory', 21),
      );
    }
    return _Reader(File(file).openSync());
  }

  @override
  ConfinedWriter openWrite(ConfinedPath path, {required bool exclusive}) {
    if (path.isRoot) {
      throw FileSystemException('not a file', root);
    }
    final file = p.join(_parent(path), path.name);
    // Checked above for links except the leaf, which `_checked` handles.
    _checked(path);
    if (exclusive) File(file).createSync(exclusive: true);
    return _Writer(File(file).openSync(mode: FileMode.write));
  }

  @override
  void createDirectory(ConfinedPath path) {
    var current = root;
    if (_checked(ConfinedPath.root(path.requested)) == null) {
      throw FileSystemException('no such directory', root);
    }
    for (var i = 0; i < path.parts.length; i++) {
      current = p.join(current, path.parts[i]);
      switch (FileSystemEntity.typeSync(current, followLinks: false)) {
        case FileSystemEntityType.link:
          throw confinedViolation(
            path.requested,
            '"${path.prefix(i + 1)}" is a link or junction',
          );
        case FileSystemEntityType.notFound:
          Directory(current).createSync();
        default:
      }
    }
  }

  @override
  void delete(ConfinedPath path) {
    if (path.isRoot) throw FileSystemException('not a file', root);
    final parent = _parent(path);
    final target = p.join(parent, path.name);
    switch (FileSystemEntity.typeSync(target, followLinks: false)) {
      case FileSystemEntityType.link:
        Link(target).deleteSync();
      case FileSystemEntityType.directory:
        Directory(target).deleteSync();
      case FileSystemEntityType.notFound:
        throw FileSystemException(
          'no such file or directory',
          path.toString(),
          const OSError('No such file or directory', 2),
        );
      default:
        File(target).deleteSync();
    }
  }

  @override
  void deleteTree(ConfinedPath path) {
    final String target;
    if (path.isRoot) {
      if (FileSystemEntity.typeSync(root, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return;
      }
      if (_checked(path) == null) return;
      target = root;
    } else {
      final parent = _checked(path.parent);
      if (parent == null) return;
      target = p.join(parent, path.name);
    }
    _deleteEntry(target);
  }

  /// Deletes [target]: a link is removed itself and never entered.
  void _deleteEntry(String target) {
    switch (FileSystemEntity.typeSync(target, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.link:
        Link(target).deleteSync();
      case FileSystemEntityType.directory:
        for (final child in Directory(target).listSync(followLinks: false)) {
          _deleteEntry(child.path);
        }
        Directory(target).deleteSync();
      default:
        File(target).deleteSync();
    }
  }

  @override
  void rename(ConfinedPath from, ConfinedPath to) {
    if (from.isRoot || to.isRoot) {
      throw FileSystemException('not a file', root);
    }
    final source = p.join(_parent(from), from.name);
    final target = p.join(_parent(to), to.name);
    if (FileSystemEntity.isDirectorySync(source)) {
      Directory(source).renameSync(target);
    } else {
      File(source).renameSync(target);
    }
  }
}

class _Reader implements ConfinedReader {
  _Reader(this._file);

  final RandomAccessFile _file;

  @override
  int get length => _file.lengthSync();

  @override
  Uint8List readAt(int offset, int count) {
    _file.setPositionSync(offset);
    return _file.readSync(count);
  }

  @override
  void close() => _file.closeSync();
}

class _Writer implements ConfinedWriter {
  _Writer(this._file);

  final RandomAccessFile _file;

  @override
  void add(List<int> bytes) => _file.writeFromSync(bytes);

  @override
  void close() {
    try {
      _file.flushSync();
    } finally {
      _file.closeSync();
    }
  }
}
