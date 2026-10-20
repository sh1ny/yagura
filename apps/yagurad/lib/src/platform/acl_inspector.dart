import 'win32_paths.dart';

export 'win32_paths.dart' show EntrySecurity, PathExists, PathRefused;

/// Reads the owner and DACL of a path (ADR 0015); the real one opens the
/// path by handle without following a link, tests use a fake.
abstract interface class AclInspector {
  /// Throws [PathRefused] when [path] cannot be opened.
  EntrySecurity inspect(String path);
}

class WindowsAclInspector implements AclInspector {
  const WindowsAclInspector();

  @override
  EntrySecurity inspect(String path) => inspectEntrySecurity(path);
}
