import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';

/// The daemon's data directory (`host-service` spec): the database, SteamCMD
/// installations, plugins, instances, snapshots and daemon logs.
class DataDirectory {
  DataDirectory._(this.path);

  /// Absolute, normalised path of the data directory.
  final String path;

  String get databasePath => p.join(path, 'yagura.db');
  String get lockPath => p.join(path, 'yagurad.lock');
  String get steamcmdPath => p.join(path, 'steamcmd');
  String get pluginsPath => p.join(path, 'plugins');
  String get instancesPath => p.join(path, 'instances');
  String get snapshotsPath => p.join(path, 'snapshots');
  String get logsPath => p.join(path, 'logs');

  /// Creates the directory and its layout and checks that it is writable.
  /// Throws `data_dir_unwritable` naming the path when it is not. With
  /// [probe] false the write check is left to [checkWritable]: the service
  /// runs it once the directory is protected, so a link planted at the probe
  /// file cannot redirect the write.
  static DataDirectory prepare(String path, {bool probe = true}) {
    final directory = DataDirectory._(p.normalize(p.absolute(path)));
    try {
      for (final folder in [
        directory.path,
        directory.steamcmdPath,
        directory.pluginsPath,
        directory.instancesPath,
        directory.snapshotsPath,
        directory.logsPath,
      ]) {
        Directory(folder).createSync(recursive: true);
      }
    } on FileSystemException catch (e) {
      throw directory._unwritable(e);
    }
    if (probe) directory.checkWritable();
    return directory;
  }

  /// Writes and deletes a probe file; throws `data_dir_unwritable`.
  void checkWritable() {
    try {
      final probe = File(p.join(path, '.write-test'));
      probe.writeAsStringSync('');
      probe.deleteSync();
    } on FileSystemException catch (e) {
      throw _unwritable(e);
    }
  }

  YaguraException _unwritable(FileSystemException e) => YaguraException(
    'data_dir_unwritable',
    'the data directory $path cannot be created or written: '
        '${e.osError?.message ?? e.message}',
    details: {'path': path},
  );
}

/// The data directory when `--data-dir` is not given: `%ProgramData%\Yagura`
/// on Windows, `/var/lib/yagura` elsewhere.
String defaultDataDirectory() {
  if (Platform.isWindows) {
    final base = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    return p.join(base, 'Yagura');
  }
  return '/var/lib/yagura';
}
