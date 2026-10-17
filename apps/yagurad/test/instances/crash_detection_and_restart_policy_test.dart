import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/instances/restart_policy.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

/// Crashes the newest launched server with [code] and waits until the
/// daemon started the next one (launch number [launches]).
Future<void> crashAndWaitForRestart(
  TestEnv env,
  Daemon daemon,
  String id,
  int code,
  int launches,
) async {
  env.process.servers.last.exit(code);
  await eventually(
    () =>
        env.process.launches.length == launches &&
        daemon.instances.get(id).state == InstanceState.running,
    reason: 'restart number $launches',
  );
}

int crashRows(TestEnv env, String id) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    return db.sqlite.select(
          'SELECT count(*) AS n FROM crashes WHERE instance_id = ?',
          [id],
        ).single['n']!
        as int;
  } finally {
    db.close();
  }
}

void main() {
  test('crash_is_restarted', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    // Seventy lines in the server's log; the notice carries the last 50.
    File(p.join(instance.directory, 'logs', 'server.log'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${[for (var i = 1; i <= 70; i++) 'server line $i'].join('\n')}\n',
      );
    final crashed = collectNotices(daemon, 'crashed');

    env.process.servers.single.exit(1);

    await eventually(
      () =>
          env.process.launches.length == 2 &&
          daemon.instances.get(instance.id).state == InstanceState.running,
      reason: 'the daemon to start the instance again',
    );
    expect(crashed, hasLength(1));
    expect(crashed.single.exitCode, 1);
    expect(crashed.single.lastLogLines, hasLength(50));
    expect(crashed.single.lastLogLines.first, 'server line 21');
    expect(crashed.single.lastLogLines.last, 'server line 70');
    // "Within 10 s": the production delay is under that.
    final defaults = DaemonConfig(
      dataDirectory: env.data,
      apiPort: apiPort,
      steam: env.steam,
    );
    expect(defaults.restartDelay, lessThan(const Duration(seconds: 10)));
    // The restart is a normal Start operation.
    expect(
      daemon.operations
          .listForInstance(instance.id)
          .where((o) => o.kind == OperationKind.start),
      hasLength(2),
    );
  });

  test('crash_loop_stops_restarting', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    final loops = collectNotices(daemon, 'crash_loop');

    // Crashes one to three are restarted.
    await crashAndWaitForRestart(env, daemon, instance.id, 1, 2);
    await crashAndWaitForRestart(env, daemon, instance.id, 1, 3);
    await crashAndWaitForRestart(env, daemon, instance.id, 1, 4);
    // The fourth within 10 minutes is not.
    env.process.servers.last.exit(1);
    await eventually(
      () => daemon.instances.get(instance.id).state == InstanceState.error,
      reason: 'the crash loop',
    );

    final after = daemon.instances.get(instance.id);
    expect(after.stateReason, crashLoopReason);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(env.process.launches, hasLength(4));
    expect(loops, hasLength(1));
    expect(lastRequestedState(env, instance.id), isEmpty);
    // Start leaves the loop and resets the counter.
    final op = daemon.instances.start(instance.id);
    expect(
      (await daemon.operations.whenDone(op.id)).status,
      OperationStatus.succeeded,
    );
    expect(crashRows(env, instance.id), 0);
    await crashAndWaitForRestart(env, daemon, instance.id, 1, 6);
  });

  test('deleting_during_the_restart_delay_discards_the_restart', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(
      restartDelay: const Duration(milliseconds: 300),
    );
    final instance = await createRunning(daemon);
    final crashed = collectNotices(daemon, 'crashed');

    env.process.servers.single.exit(1);
    await eventually(() => crashed.isNotEmpty, reason: 'the crash notice');

    final op = daemon.instances.delete(instance.id);
    await daemon.operations.whenDone(op.id);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(env.process.launches, hasLength(1));
    expect(daemon.instances.find(instance.id), isNull);
    final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    try {
      expect(
        db.sqlite.select('SELECT id FROM instances WHERE id = ?', [
          instance.id,
        ]),
        isEmpty,
      );
    } finally {
      db.close();
    }
  });

  test('crash_timestamps_survive_a_daemon_restart', () async {
    final env = TestEnv();
    env.installValheim();
    final first = await env.start();
    final instance = await createRunning(first);
    await crashAndWaitForRestart(env, first, instance.id, 1, 2);
    await crashAndWaitForRestart(env, first, instance.id, 1, 3);
    await crashAndWaitForRestart(env, first, instance.id, 1, 4);
    expect(crashRows(env, instance.id), 3);

    // The daemon restarts; autostart brings the instance back (D14).
    await env.kill(first);
    final second = await env.start();
    await eventually(
      () => second.instances.get(instance.id).state == InstanceState.running,
      reason: 'autostart',
    );
    expect(env.process.launches, hasLength(5));

    // One more crash is the fourth within the window: no restart.
    env.process.servers.last.exit(1);
    await eventually(
      () => second.instances.get(instance.id).state == InstanceState.error,
      reason: 'the crash loop across the restart',
    );
    expect(second.instances.get(instance.id).stateReason, crashLoopReason);
    expect(env.process.launches, hasLength(5));
  });

  test('restart_policy_never_stays_stopped', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    daemon.instances.updateSettings(
      UpdateSettingsRequestFor.never(instance.id),
    );

    env.process.servers.single.exit(2);

    await eventually(
      () => daemon.instances.get(instance.id).state == InstanceState.stopped,
      reason: 'the instance to stop',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(env.process.launches, hasLength(1));
    expect(lastRequestedState(env, instance.id), isEmpty);
  });

  group('decideRestart', () {
    final now = DateTime.utc(2026, 10, 17, 12);
    List<DateTime> crashes(int n, {Duration age = Duration.zero}) => [
      for (var i = 0; i < n; i++) now.subtract(age + Duration(seconds: i)),
    ];

    test('the first three crashes restart, the fourth is a loop', () {
      for (final n in [1, 2, 3]) {
        expect(
          decideRestart(
            policy: 'on_crash',
            recentCrashes: crashes(n),
            now: now,
          ),
          RestartAction.restart,
          reason: 'crash $n',
        );
      }
      expect(
        decideRestart(policy: 'on_crash', recentCrashes: crashes(4), now: now),
        RestartAction.crashLoop,
      );
    });

    test('crashes older than ten minutes do not count', () {
      final recent = [...crashes(3, age: const Duration(minutes: 11)), now];
      expect(
        decideRestart(policy: 'on_crash', recentCrashes: recent, now: now),
        RestartAction.restart,
      );
    });

    test('policy never stays stopped', () {
      expect(
        decideRestart(policy: 'never', recentCrashes: crashes(1), now: now),
        RestartAction.stay,
      );
    });
  });
}

/// The `last_requested_state` column of an instance row.
String lastRequestedState(TestEnv env, String id) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    return db.sqlite.select(
          'SELECT last_requested_state FROM instances WHERE id = ?',
          [id],
        ).single['last_requested_state']!
        as String;
  } finally {
    db.close();
  }
}

/// Settings updates for tests that only change the restart policy.
class UpdateSettingsRequestFor {
  static UpdateSettingsRequest never(String id) => UpdateSettingsRequest(
    instanceId: id,
    settings: valheimSettings(),
    restartPolicy: 'never',
  );
}
