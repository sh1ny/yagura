import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Design D8: every file operation on an instance directory or on
// `<data>/steamcmd` goes through ConfinedFs, so a link planted by a game
// server cannot lead the daemon out of the directory. This test is the
// enforcement: it scans `lib/src` for `dart:io` file calls and fails on any
// file that is not listed here with the reason its calls are allowed.

/// The calls that touch the file system through `dart:io`.
final _fileCall = RegExp(
  r'\b(File|Directory|Link|RandomAccessFile)\(|'
  r'\bFileSystemEntity\.(type|is|identical)|'
  r'\.(openSync|readAsBytesSync|readAsStringSync|readAsLinesSync|'
  r'writeAsStringSync|writeAsBytesSync|listSync|existsSync|deleteSync|'
  r'createSync|renameSync|statSync|lengthSync|createTempSync|copySync|'
  r'readAsString|readAsBytes|readAsLines|writeAsString|writeAsBytes)\b',
);

/// Files under `lib/src` allowed to make those calls, and why.
const _allowed = <String, String>{
  // Daemon-owned locations, none of them inside an instance directory.
  'host/data_dir_lock.dart': 'the lock file in the data directory',
  'host/data_directory.dart': 'the data directory itself',
  'host/database.dart': 'the database backup in the data directory',
  'plugins/plugin_registry.dart': 'the plugin folders in the data directory',
  'snapshots/directory_snapshotter.dart':
      'the snapshot folders in the data directory; instance data is read and '
      'written through InstanceFs',
  'steam/stray_processes.dart': '/proc, to find stray SteamCMD processes',
  'host/data_dir_protector.dart':
      'creates the parent of the data directory itself (no instance path); the '
      'directory and everything in it go through ConfinedFs',
  'platform/disk_space.dart':
      'looks for the nearest existing folder to ask its volume for free space; '
      'reads no file',
  'instances/instance_manager.dart':
      'lists the instances root (not an instance) in the marked-directory '
      'sweep; everything below an instance goes through InstanceFs',
  // The run files. The daemon builds them with RunFiles.forRun (or an
  // InstanceFs), so its reads and writes of launch.json, relay.json, exit.json
  // and cancel.json go through the instance's ConfinedFs. What stays here is
  // the by-path branch used when no fs is given: the relay (a separate
  // process, which can reach only what its own account can already write) and
  // the tests. The 'the daemon builds RunFiles only with an fs' test below
  // keeps the daemon off that branch.
  'process/run_files.dart':
      'the by-path branch (no fs) used by the relay and the tests',
  // The relay is a separate process that owns the server's pipes; it writes
  // its own files by path and runs as the server's account after group 9.
  'process/relay_run_files.dart':
      'relay.json and exit.json, written by the '
      'relay process',
  'logs/capture_writer.dart': 'the stdout capture written by the relay',
  // The service installer works on the install directory and the bundle, and
  // the purge on the database in the data directory: no instance path.
  'cli/service_command.dart': 'the installed service configuration',
  'service/account_purger.dart': 'the database in the data directory',
  'service/bundle.dart': 'the unpacked bundle being installed',
  'service/service_installer.dart':
      'the install directory (program files), the bundle and the WinSW'
      ' configuration',
  'service/install_layout.dart':
      'the marker file inside a version folder of the install directory',
  'service/version_sweeper.dart': 'version folders in the install directory',
};

List<File> _sources() => [
  for (final entity in Directory(
    p.join('lib', 'src'),
  ).listSync(recursive: true, followLinks: false))
    if (entity is File && entity.path.endsWith('.dart')) entity,
];

String _key(File file) =>
    p.posix.joinAll(p.split(p.relative(file.path, from: p.join('lib', 'src'))));

bool _callsFiles(File file) {
  for (final line in file.readAsLinesSync()) {
    final code = line.trimLeft();
    if (code.startsWith('//')) continue;
    if (_fileCall.hasMatch(code)) return true;
  }
  return false;
}

void main() {
  test('no dart:io file call outside the ConfinedFs files', () {
    final offenders = <String>[];
    for (final file in _sources()) {
      final key = _key(file);
      if (key.startsWith('files/confined_fs') ||
          key == 'files/instance_fs.dart' ||
          key == 'platform/win32_files.dart') {
        continue;
      }
      if (_allowed.containsKey(key)) continue;
      if (_callsFiles(file)) offenders.add(key);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these files call dart:io file APIs; route instance and steamcmd '
          'paths through InstanceFs/ConfinedFs, or list the file in _allowed '
          'with the reason it never takes such a path',
    );
  });

  test('every exemption is still needed', () {
    final stale = <String>[];
    for (final MapEntry(key: key) in _allowed.entries) {
      final file = File(p.join('lib', 'src', key));
      if (!file.existsSync() || !_callsFiles(file)) stale.add(key);
    }
    expect(stale, isEmpty, reason: 'remove these from _allowed');
  });

  test('the daemon-side run files only read through dart:io', () {
    // Writes are in process/relay_run_files.dart (the relay) or go through
    // the instance's ConfinedFs.
    final source = File(p.join('lib', 'src', 'process', 'run_files.dart'))
        .readAsStringSync();
    for (final write in [
      'writeAs',
      'renameSync',
      'createSync',
      'deleteSync',
      'openWrite',
    ]) {
      expect(source, isNot(contains(write)), reason: write);
    }
  });

  test('the daemon builds RunFiles only with an fs', () {
    // The relay (launcher_modes.dart) reads and writes by path; everything
    // else must pass `fs:` or use RunFiles.forRun.
    final offenders = <String>[];
    for (final file in _sources()) {
      final key = _key(file);
      if (key == 'process/run_files.dart' ||
          key == 'process/launcher_modes.dart') {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (!RegExp(r'(?<![\w.])RunFiles\(').hasMatch(lines[i])) continue;
        final call = lines.skip(i).take(4).join(' ');
        if (!call.contains('fs:')) offenders.add('$key:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'use RunFiles.forRun or pass fs:');
  });

  test('the unconfined InstanceRoot is gone', () {
    expect(
      File(p.join('lib', 'src', 'files', 'instance_root.dart')).existsSync(),
      isFalse,
    );
    for (final file in _sources()) {
      expect(file.readAsStringSync(), isNot(contains('InstanceRoot')));
    }
  });

  test('the confined files are used by the callers D8 names', () {
    String source(String path) =>
        File(p.join('lib', 'src', path)).readAsStringSync();
    expect(source('steam/steamcmd_service.dart'), contains('ConfinedFs'));
    expect(source('steam/steamcmd_bootstrap.dart'), contains('ConfinedFs'));
    expect(source('logs/source_tailer.dart'), contains('ConfinedFs'));
    expect(source('instances/instance_file.dart'), contains('InstanceFs'));
    expect(source('instances/lifecycle.dart'), contains('InstanceFs'));
    expect(source('hooks/host_api.dart'), contains('ConfinedFs'));
    expect(source('files/file_edit_writer.dart'), contains('ConfinedFs'));
  });
}
