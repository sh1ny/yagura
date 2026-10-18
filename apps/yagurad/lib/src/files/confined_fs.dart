import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../errors.dart';
import 'confined_fs_portable.dart';
import 'confined_fs_windows.dart';

/// What a [ConfinedFs] knows about one entry of a directory it confines.
class ConfinedEntry {
  const ConfinedEntry({
    required this.name,
    required this.isDirectory,
    required this.isLink,
    required this.size,
    required this.modified,
    required this.created,
  });

  /// The entry's own name (no directory part).
  final String name;
  final bool isDirectory;

  /// Whether the entry is a symbolic link, a junction or any other reparse
  /// point. A link is reported by [ConfinedFs.list] and refused by every other
  /// operation.
  final bool isLink;

  /// The size in bytes; 0 for a directory or a link.
  final int size;
  final DateTime modified;

  /// When the entry was created (the status-change time where the host has
  /// no creation time).
  final DateTime created;

  @override
  String toString() => 'ConfinedEntry($name)';
}

/// A file opened for reading through a [ConfinedFs].
abstract interface class ConfinedReader {
  /// The file's size in bytes when it was last asked.
  int get length;

  /// Up to [count] bytes at [offset]; fewer (or none) at the end of the file.
  Uint8List readAt(int offset, int count);

  void close();
}

/// A file opened for writing through a [ConfinedFs].
abstract interface class ConfinedWriter {
  void add(List<int> bytes);

  /// Flushes the data to disk and closes the file.
  void close();
}

/// A validated relative path: the components of [requested], with nothing in
/// them that leaves the root.
class ConfinedPath {
  const ConfinedPath._(this.requested, this.parts);

  /// The root, named as [requested] in messages.
  const ConfinedPath.root(this.requested) : parts = const [];

  /// The path as the caller wrote it, for messages.
  final String requested;
  final List<String> parts;

  bool get isRoot => parts.isEmpty;
  String get name => parts.last;
  ConfinedPath get parent =>
      ConfinedPath._(requested, parts.sublist(0, parts.length - 1));
  ConfinedPath child(String name) => ConfinedPath._(
    requested.isEmpty ? name : '$requested/$name',
    [...parts, name],
  );
  ConfinedPath sibling(String name) =>
      ConfinedPath._(requested, [...parts.sublist(0, parts.length - 1), name]);

  /// The first [count] components joined with `/`, for messages.
  String prefix(int count) => parts.take(count).join('/');

  @override
  String toString() => parts.join('/');
}

/// The primitive operations a platform provides to [ConfinedFs]. Every method
/// refuses a symbolic link or junction on the path, including the root, with
/// `sandbox_violation`, and reports other failures as a [FileSystemException].
abstract interface class ConfinedBackend {
  /// The entry at [path], or null when it (or a directory above it) does not
  /// exist. The root itself is a directory.
  ConfinedEntry? stat(ConfinedPath path);

  /// The entries of the directory [path], links included and not followed.
  List<ConfinedEntry> list(ConfinedPath path);

  ConfinedReader openRead(ConfinedPath path);

  /// Opens [path] for writing, creating or truncating it; with [exclusive] it
  /// fails if anything is there already.
  ConfinedWriter openWrite(ConfinedPath path, {required bool exclusive});

  /// Creates the directory [path] and the missing directories above it.
  void createDirectory(ConfinedPath path);

  /// Deletes one file, link or empty directory.
  void delete(ConfinedPath path);

  /// Deletes [path] and everything below it. A link is removed itself and
  /// never entered. The root, when [path] is the root, goes last.
  void deleteTree(ConfinedPath path);

  /// Renames [from] to [to] within the root, replacing a file at [to].
  void rename(ConfinedPath from, ConfinedPath to);
}

/// File access confined to one directory (design D8, ADR 0013).
///
/// Every operation opens the root and walks the path from it one component at
/// a time, and refuses any symbolic link or junction on the way, the root
/// itself included, with `sandbox_violation` naming the path. On Windows the
/// walk is handle-relative (`NtCreateFile` with `RootDirectory` and
/// `FILE_OPEN_REPARSE_POINT`), so a link planted after the check cannot be
/// followed; elsewhere it is a best-effort check with `dart:io` (the Linux
/// host is M5).
///
/// Paths are relative to the root and use `/` or `\` as separators. A path that
/// is absolute, contains `..` or names an alternate data stream is a
/// `sandbox_violation`. [relative] turns an absolute path inside the root into
/// a relative one.
class ConfinedFs {
  /// Confines to the directory [root].
  ConfinedFs(String root)
    : this._(
        p.normalize(p.absolute(root)),
        Platform.isWindows
            ? WindowsConfinedBackend(p.normalize(p.absolute(root)))
            : PortableConfinedBackend(p.normalize(p.absolute(root))),
      );

  /// Confines to [root] with a backend of the caller's choosing.
  ConfinedFs.withBackend(String root, ConfinedBackend backend)
    : this._(p.normalize(p.absolute(root)), backend);

  ConfinedFs._(this.root, this._backend);

  /// The confined directory (absolute, normalised).
  final String root;
  final ConfinedBackend _backend;

  static final _random = Random.secure();

  /// Creates the directory [directory], and the directories above it, so that
  /// a [ConfinedFs] can be rooted in it. Returns whether it did not exist
  /// before. A link where the directory belongs fails `sandbox_violation`.
  static bool create(String directory) {
    final path = p.normalize(p.absolute(directory));
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.link:
        throw confinedViolation(
          path,
          'the directory "$path" is a link or junction',
        );
      case FileSystemEntityType.notFound:
        Directory(path).createSync(recursive: true);
        return true;
      default:
        return false;
    }
  }

  // ---- paths -----------------------------------------------------------------

  /// Validates [path] as a path relative to the root.
  ConfinedPath parse(String path) {
    if (path.contains('\u0000')) {
      throw _violation(path, 'the path contains a NUL character');
    }
    if (path.startsWith('/') ||
        path.startsWith(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(path)) {
      throw _violation(path, 'the path is not relative to the root');
    }
    final parts = <String>[];
    for (final part in path.split(RegExp(r'[/\\]'))) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        throw _violation(path, 'the path leaves the root');
      }
      if (part.contains(':')) {
        throw _violation(path, 'the path names a stream or a drive');
      }
      parts.add(part);
    }
    return ConfinedPath._(path, parts);
  }

  /// The path of [absolute] relative to the root. Throws `sandbox_violation`
  /// when it lies elsewhere.
  String relative(String absolute) {
    final candidate = p.normalize(p.absolute(absolute));
    if (p.equals(candidate, root)) return '';
    if (!p.isWithin(root, candidate)) {
      throw _violation(absolute, 'the path is outside the root');
    }
    return p.relative(candidate, from: root);
  }

  /// The absolute path of [path], for handing to a process; the file is not
  /// opened through it.
  String absolute(String path) => p.joinAll([root, ...parse(path).parts]);

  // ---- reading ---------------------------------------------------------------

  /// The entry at [path], or null when it does not exist.
  ConfinedEntry? stat(String path) => _backend.stat(parse(path));

  bool exists(String path) => stat(path) != null;

  /// The entries of the directory [path]; links are listed, not followed.
  List<ConfinedEntry> list(String path) => _backend.list(parse(path));

  ConfinedReader openRead(String path) => _backend.openRead(parse(path));

  /// The whole file. A file over [maxBytes] fails with `file_too_large`.
  Uint8List readBytes(String path, {int? maxBytes}) {
    final reader = openRead(path);
    try {
      if (maxBytes != null && reader.length > maxBytes) {
        throw _tooLarge(path, maxBytes);
      }
      final out = BytesBuilder(copy: false);
      var offset = 0;
      while (true) {
        final chunk = reader.readAt(offset, 64 * 1024);
        if (chunk.isEmpty) return out.takeBytes();
        offset += chunk.length;
        out.add(chunk);
        // The file may have grown since its length was read.
        if (maxBytes != null && offset > maxBytes) {
          throw _tooLarge(path, maxBytes);
        }
      }
    } finally {
      reader.close();
    }
  }

  YaguraException _tooLarge(String path, int maxBytes) => YaguraException(
    'file_too_large',
    '"$path" is over the $maxBytes byte limit',
    details: {'path': path},
  );

  // ---- writing ---------------------------------------------------------------

  ConfinedWriter openWrite(String path, {bool exclusive = false}) =>
      _backend.openWrite(parse(path), exclusive: exclusive);

  /// Creates or replaces the file [path] with [bytes].
  void writeBytes(String path, List<int> bytes) {
    final writer = openWrite(path);
    try {
      writer.add(bytes);
    } finally {
      writer.close();
    }
  }

  /// Replaces the file [path] atomically: [bytes] go to a temporary sibling
  /// that is renamed over it, so a reader sees all or nothing.
  void writeAtomic(
    String path,
    List<int> bytes, {
    void Function(String temporary, String target)? rename,
  }) {
    final target = parse(path);
    if (target.isRoot) throw _violation(path, 'the root is not a file');
    final temporary = _temporaryFor(target);
    final writer = _backend.openWrite(temporary, exclusive: true);
    try {
      try {
        writer.add(bytes);
      } finally {
        writer.close();
      }
      if (rename != null) {
        rename(temporary.toString(), target.toString());
      } else {
        _backend.rename(temporary, target);
      }
    } on Object {
      try {
        _backend.delete(temporary);
      } on Object {
        // Best effort: the temporary file is not the target.
      }
      rethrow;
    }
  }

  /// A path next to [target] that nothing occupies yet.
  ConfinedPath _temporaryFor(ConfinedPath target) => target.sibling(
    '.${target.name}.yagura-${_random.nextInt(1 << 31).toRadixString(16)}.tmp',
  );

  /// A fresh name for a temporary file next to [path], as a relative path.
  /// Nothing is created.
  String temporaryFor(String path) {
    final target = parse(path);
    if (target.isRoot) throw _violation(path, 'the root is not a file');
    return _temporaryFor(target).toString();
  }

  /// Creates the directory [path] and any missing directory above it.
  void createDirectory(String path) => _backend.createDirectory(parse(path));

  // ---- removing and moving ---------------------------------------------------

  /// Deletes one file, link or empty directory.
  void delete(String path) => _backend.delete(parse(path));

  /// Deletes [path] and all below it. A link met on the way is removed itself
  /// and never entered. `''` deletes the root too.
  void deleteTree(String path) => _backend.deleteTree(parse(path));

  /// Renames [from] to [to], replacing a file there.
  void rename(String from, String to) =>
      _backend.rename(parse(from), parse(to));

  // ---- copying ---------------------------------------------------------------

  /// The number of bytes below [path]. A link fails with `sandbox_violation`.
  int treeSize(String path) => _treeSize(parse(path));

  int _treeSize(ConfinedPath path) {
    final entry = _backend.stat(path);
    if (entry == null) return 0;
    if (!entry.isDirectory) return entry.size;
    var total = 0;
    for (final child in _backend.list(path)) {
      if (child.isLink) throw _linkMet(path.child(child.name));
      total += child.isDirectory
          ? _treeSize(path.child(child.name))
          : child.size;
    }
    return total;
  }

  /// Copies the file or directory [path] to [destination], outside the root,
  /// and returns the bytes copied. A link fails with `sandbox_violation`.
  int copyOut(String path, String destination) =>
      _copyOut(parse(path), destination);

  int _copyOut(ConfinedPath path, String destination) {
    final entry = _backend.stat(path);
    if (entry == null) {
      throw FileSystemException('no such file or directory', path.toString());
    }
    if (!entry.isDirectory) {
      Directory(p.dirname(destination)).createSync(recursive: true);
      final reader = _backend.openRead(path);
      final sink = File(destination).openSync(mode: FileMode.write);
      try {
        var offset = 0;
        while (true) {
          final chunk = reader.readAt(offset, 256 * 1024);
          if (chunk.isEmpty) break;
          sink.writeFromSync(chunk);
          offset += chunk.length;
        }
        return offset;
      } finally {
        sink.closeSync();
        reader.close();
      }
    }
    Directory(destination).createSync(recursive: true);
    var bytes = 0;
    for (final child in _backend.list(path)) {
      final childPath = path.child(child.name);
      if (child.isLink) throw _linkMet(childPath);
      bytes += _copyOut(childPath, p.join(destination, child.name));
    }
    return bytes;
  }

  /// Copies the file or directory [source], outside the root, to [path] and
  /// returns the bytes copied. Links in [source] are skipped.
  int copyIn(String source, String path) => _copyIn(source, parse(path));

  int _copyIn(String source, ConfinedPath path) {
    final type = FileSystemEntity.typeSync(source, followLinks: false);
    if (type == FileSystemEntityType.file) {
      final parent = path.parent;
      if (!parent.isRoot) _backend.createDirectory(parent);
      final input = File(source).openSync();
      final writer = _backend.openWrite(path, exclusive: false);
      try {
        var bytes = 0;
        while (true) {
          final chunk = input.readSync(256 * 1024);
          if (chunk.isEmpty) return bytes;
          writer.add(chunk);
          bytes += chunk.length;
        }
      } finally {
        writer.close();
        input.closeSync();
      }
    }
    if (type != FileSystemEntityType.directory) return 0;
    if (!path.isRoot) _backend.createDirectory(path);
    var bytes = 0;
    for (final entity in Directory(source).listSync(followLinks: false)) {
      bytes += _copyIn(entity.path, path.child(p.basename(entity.path)));
    }
    return bytes;
  }

  // ---- errors ----------------------------------------------------------------

  YaguraException _linkMet(ConfinedPath path) =>
      _violation(path.toString(), '"$path" is a link or junction');

  YaguraException _violation(String requested, String why) =>
      confinedViolation(requested, why);
}

/// The `sandbox_violation` for [requested], which is refused because of [why].
YaguraException confinedViolation(String requested, String why) =>
    YaguraException(
      'sandbox_violation',
      'path "$requested" is refused: $why',
      details: {'path': requested},
    );
