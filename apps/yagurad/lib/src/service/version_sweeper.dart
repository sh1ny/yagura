import 'dart:io';

import 'package:path/path.dart' as p;

import '../process/run_store.dart';
import 'install_layout.dart';

/// Deletes the version directories nothing uses any more (design D6).
///
/// A relay keeps executing the `yagurad.exe` of the version that started it,
/// so an upgrade leaves the old version directory in place. The daemon
/// deletes it at startup once no unresolved run record names an executable
/// inside it. It deletes only the directories that carry this service's
/// install marker.
class VersionSweeper {
  VersionSweeper({
    required this.layout,
    required this.currentVersion,
    void Function(String path)? delete,
  }) : delete =
           delete ??
           ((path) => layout.deleteVersionDirectory(p.basename(path)));

  final InstallLayout layout;
  final String currentVersion;
  final void Function(String path) delete;

  /// Deletes the unused version directories and returns their names.
  /// A directory that cannot be deleted (a file in it is still locked) stays
  /// and is tried again at the next start.
  List<String> sweep(Iterable<RunRecord> unresolved) {
    final root = Directory(layout.root);
    if (!root.existsSync()) return const [];
    // Only runs that have not ended hold a version: an ended run's relay is
    // gone. A pending run has no relay yet, and this daemon starts it.
    final inUse = [
      for (final run in unresolved)
        if (run.state != RunState.ended)
          if (run.relay case final relay?) relay.executable,
    ];
    final deleted = <String>[];
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (!isVersionName(name) || name == currentVersion) continue;
      // Only what this service's install made: the root may be shared with
      // another service or hold other software's versioned folders.
      if (!layout.ownsVersionDirectory(name)) continue;
      if (inUse.any((exe) => _within(exe, entity.path))) continue;
      try {
        delete(entity.path);
        deleted.add(name);
      } on FileSystemException {
        // A relay or a scan still holds a file; the next start tries again.
      }
    }
    return deleted;
  }

  static bool _within(String file, String directory) {
    final prefix = directory.replaceAll('/', r'\').toLowerCase();
    return file.replaceAll('/', r'\').toLowerCase().startsWith('$prefix\\');
  }
}
