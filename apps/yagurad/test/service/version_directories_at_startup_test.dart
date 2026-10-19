import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/service/install_layout.dart';
import 'package:yagurad/src/service/version_sweeper.dart';

import '../support/daemon_support.dart';

/// An install root with version directories `0.1.0` (old), `0.2.0` (the
/// running one).
InstallLayout _installRoot() {
  final root = Directory.systemTemp.createTempSync('yagurad_install_');
  addTearDown(() => root.deleteSync(recursive: true));
  final layout = InstallLayout(root: root.path);
  for (final v in ['0.1.0', '0.2.0']) {
    File(layout.executable(v))
      ..createSync(recursive: true)
      ..writeAsStringSync(v);
    layout.markVersionDirectory(v);
  }
  return layout;
}

bool _has(InstallLayout layout, String version) =>
    Directory(layout.versionDirectory(version)).existsSync();

void main() {
  test('startup_deletes_an_unused_version_directory', () async {
    final layout = _installRoot();
    final env = TestEnv()..installValheim();

    final daemon = await env.start(
      versionSweeper: VersionSweeper(layout: layout, currentVersion: '0.2.0'),
    );

    expect(_has(layout, '0.1.0'), isFalse);
    expect(_has(layout, '0.2.0'), isTrue);
    expect(daemon.startupNotices, isEmpty);
  });

  test('startup_keeps_the_version_a_re_attached_relay_runs_from', () async {
    final layout = _installRoot();
    final env = TestEnv()..installValheim();
    final first = await env.start();
    await createRunning(first);
    final server = env.process.servers.single;
    await env.kill(first);
    // The relay of that run executes the old version's yagurad.exe.
    final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    try {
      db.sqlite.execute(
        'UPDATE runs SET relay_pid = 777, relay_created = 1, '
        'relay_executable = ?',
        [layout.executable('0.1.0')],
      );
    } finally {
      db.close();
    }
    env.process.survivors.add(server);

    await env.start(
      versionSweeper: VersionSweeper(layout: layout, currentVersion: '0.2.0'),
    );

    expect(_has(layout, '0.1.0'), isTrue, reason: 'a relay still runs from it');
  });

  test('a_sweep_that_fails_is_a_notice_and_not_a_failed_start', () async {
    final layout = _installRoot();
    final env = TestEnv()..installValheim();

    final daemon = await env.start(
      versionSweeper: VersionSweeper(
        layout: layout,
        currentVersion: '0.2.0',
        delete: (_) => throw StateError('disk on fire'),
      ),
    );

    expect(daemon.startupNotices.map((n) => n.step), ['version_directories']);
  });
}
