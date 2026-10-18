import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/process/process_host.dart';
import 'package:yagurad/src/process/run_store.dart';
import 'package:yagurad/src/service/install_layout.dart';
import 'package:yagurad/src/service/version_sweeper.dart';

/// An install root with the given version directories (each holding a
/// `bin\yagurad.exe`) and some directories that are not versions.
class _Root {
  _Root(List<String> versions) {
    root = Directory.systemTemp.createTempSync('yagurad_versions_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    layout = InstallLayout(root: root.path);
    for (final v in versions) {
      File(layout.executable(v))
        ..createSync(recursive: true)
        ..writeAsStringSync(v);
    }
    for (final other in ['logs', 'backup', 'v1']) {
      Directory(p.join(root.path, other)).createSync();
    }
  }

  late final Directory root;
  late final InstallLayout layout;

  bool has(String name) => Directory(p.join(root.path, name)).existsSync();
}

RunRecord _run(
  String relayExecutable, {
  RunState state = RunState.running,
  String? serverExecutable,
}) => RunRecord(
  runId: 'r',
  instanceId: 'i',
  directory: 'd',
  state: state,
  createdAt: DateTime(2026),
  relay: ProcessIdentity(pid: 10, executable: relayExecutable, created: 1),
  server: ProcessIdentity(
    pid: 11,
    executable: serverExecutable ?? r'C:\servers\valheim.exe',
    created: 2,
  ),
);

void main() {
  test('deletes_the_versions_nothing_runs_from', () {
    final r = _Root(['0.1.0', '0.2.0', '0.3.0']);

    final deleted = VersionSweeper(
      layout: r.layout,
      currentVersion: '0.3.0',
    ).sweep(const []);

    expect(deleted, unorderedEquals(['0.1.0', '0.2.0']));
    expect(r.has('0.3.0'), isTrue);
    expect(r.has('0.1.0'), isFalse);
    expect(r.has('0.2.0'), isFalse);
  });

  test('keeps_a_version_a_running_relay_executes', () {
    final r = _Root(['0.1.0', '0.2.0', '0.3.0']);
    final relay = r.layout.executable('0.1.0').toUpperCase();

    final deleted = VersionSweeper(
      layout: r.layout,
      currentVersion: '0.3.0',
    ).sweep([_run(relay)]);

    expect(deleted, ['0.2.0']);
    expect(r.has('0.1.0'), isTrue, reason: 'a relay runs from it');
  });

  test('a_pending_or_ended_run_does_not_hold_a_version', () {
    final r = _Root(['0.1.0', '0.2.0']);

    final deleted = VersionSweeper(
      layout: r.layout,
      currentVersion: '0.2.0',
    ).sweep([_run(r.layout.executable('0.1.0'), state: RunState.ended)]);

    expect(deleted, ['0.1.0']);
  });

  test('a_version_name_that_is_a_prefix_is_not_the_same_directory', () {
    final r = _Root(['0.1.0', '0.1.0-rc.1', '0.2.0']);

    final deleted = VersionSweeper(
      layout: r.layout,
      currentVersion: '0.2.0',
    ).sweep([_run(r.layout.executable('0.1.0'))]);

    expect(deleted, ['0.1.0-rc.1']);
    expect(r.has('0.1.0'), isTrue);
  });

  test('leaves_directories_that_are_not_versions', () {
    final r = _Root(['0.1.0', '0.2.0']);

    VersionSweeper(layout: r.layout, currentVersion: '0.2.0').sweep(const []);

    expect(r.has('logs'), isTrue);
    expect(r.has('backup'), isTrue);
    expect(r.has('v1'), isTrue);
  });

  test('a_directory_that_cannot_be_deleted_stays_and_the_rest_go', () {
    final r = _Root(['0.1.0', '0.2.0', '0.3.0']);
    final attempts = <String>[];

    final deleted = VersionSweeper(
      layout: r.layout,
      currentVersion: '0.3.0',
      delete: (path) {
        attempts.add(p.basename(path));
        if (p.basename(path) == '0.1.0') {
          throw const FileSystemException('in use');
        }
        Directory(path).deleteSync(recursive: true);
      },
    ).sweep(const []);

    expect(attempts, unorderedEquals(['0.1.0', '0.2.0']));
    expect(deleted, ['0.2.0']);
    expect(r.has('0.1.0'), isTrue, reason: 'tried again at the next start');
  });

  test('a_missing_install_root_is_nothing_to_do', () {
    final sweeper = VersionSweeper(
      layout: const InstallLayout(root: r'C:\does\not\exist\Yagura'),
      currentVersion: '0.1.0',
    );

    expect(sweeper.sweep(const []), isEmpty);
  });
}
