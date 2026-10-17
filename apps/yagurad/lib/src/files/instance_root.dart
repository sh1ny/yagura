import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';

/// An instance directory and the rule that every file access inside it
/// resolves its final path, following links, and stays within it (design
/// D22). Guards against mistakes and stray links, not against a hostile race.
class InstanceRoot {
  InstanceRoot(String path) : path = p.normalize(p.absolute(path));

  /// The instance root as given (absolute, normalised).
  final String path;

  late final String _real = Directory(path).resolveSymbolicLinksSync();

  /// The resolved path of the root itself.
  String get resolvedPath => _real;

  /// Resolves [relative] (a path relative to the root, or an absolute path)
  /// to the final path it points at, following links.
  ///
  /// The target need not exist: the nearest existing ancestor is resolved and
  /// the rest appended. Throws `sandbox_violation` when the result is outside
  /// the root.
  String resolve(String relative) {
    if (relative.contains('\u0000')) {
      throw _violation(relative, 'the path contains a NUL character');
    }
    final candidate = p.normalize(p.absolute(p.join(_real, relative)));
    // An absolute path may name the root another way (a Windows 8.3 short
    // name such as `RUNNER~1`), so only the resolved path below decides.
    if (!p.isAbsolute(relative) && !_inside(candidate)) {
      throw _violation(relative, 'the path leaves the instance root');
    }
    var existing = candidate;
    final tail = <String>[];
    while (FileSystemEntity.typeSync(existing, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(existing);
      if (parent == existing) break;
      tail.insert(0, p.basename(existing));
      existing = parent;
    }
    final String resolvedExisting;
    try {
      resolvedExisting = _resolveLinks(existing);
    } on FileSystemException {
      throw _violation(relative, 'a link on the path cannot be resolved');
    }
    final resolved = p.joinAll([resolvedExisting, ...tail]);
    if (!_inside(resolved)) {
      throw _violation(relative, 'a link on the path leads outside the root');
    }
    return resolved;
  }

  /// The path relative to the root, for messages and results.
  String relativeTo(String resolved) => p.relative(resolved, from: _real);

  bool _inside(String candidate) =>
      p.equals(candidate, _real) || p.isWithin(_real, candidate);

  static String _resolveLinks(String existing) {
    return switch (FileSystemEntity.typeSync(existing)) {
      FileSystemEntityType.directory => Directory(
        existing,
      ).resolveSymbolicLinksSync(),
      _ => File(existing).resolveSymbolicLinksSync(),
    };
  }

  YaguraException _violation(String requested, String why) => YaguraException(
    'sandbox_violation',
    'path "$requested" is refused: $why',
    details: {'path': requested},
  );
}
