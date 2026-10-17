import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

/// The `last_requested_state` column of an instance row.
String lastRequestedState(TestEnv env, String id) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    final rows = db.sqlite.select(
      'SELECT last_requested_state FROM instances WHERE id = ?',
      [id],
    );
    return rows.single['last_requested_state']! as String;
  } finally {
    db.close();
  }
}

void main() {
  test('cancelled_update_not_autostarted', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    expect(lastRequestedState(env, instance.id), 'running');
    env.steam.hold = Completer<void>();

    final op = daemon.instances.update(instance.id);
    await eventually(
      () => daemon.instances.get(instance.id).state == InstanceState.updating,
      reason: 'the update to pass its stop step',
    );
    // The internal stop of an update keeps the last requested state (D14)...
    expect(lastRequestedState(env, instance.id), 'running');
    daemon.operations.cancel(op.id);
    final done = await daemon.operations.whenDone(op.id);

    // ...and an update that ends with the server stopped clears it.
    expect(done.status, OperationStatus.cancelled);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(lastRequestedState(env, instance.id), isEmpty);

    await env.kill(daemon);
    final restarted = await env.start();
    expect(restarted.instances.get(instance.id).state, InstanceState.stopped);
    expect(lastRequestedState(env, instance.id), isEmpty);
  });

  test('host_rebooted', () async {
    final env = TestEnv();
    env.installValheim();
    final first = await env.start();
    final a = await createRunning(first, name: 'A');
    // Valheim's default ports collide; the second instance gets its own.
    final bInstall = await createInstalled(
      first,
      name: 'B',
      ports: {'game': 2556},
    );
    await runStart(first, bInstall.id);
    expect(env.process.launches, hasLength(2));
    // The host reboots: both processes are gone, nothing was recorded.
    await env.kill(first);

    const gap = Duration(milliseconds: 300);
    final second = await env.start(autostartInterval: gap);

    await eventually(
      () => env.process.launches.length == 4,
      reason: 'both instances to start again',
    );
    await eventually(
      () => second.instances.list().every(
        (i) => i.state == InstanceState.running,
      ),
      reason: 'both to be running',
    );
    final notices = second.instances.recoveryNotices
        .where((n) => n.kind == 'autostarted')
        .map((n) => n.instanceId);
    expect(notices, unorderedEquals([a.id, bInstall.id]));
    // Started 10 s apart in production; here the configured gap.
    final stamps = env.process.servers.skip(2).map((s) => s.startedAt).toList();
    expect(stamps[1].difference(stamps[0]), greaterThanOrEqualTo(gap));
    final defaults = DaemonConfig(
      dataDirectory: env.data,
      apiPort: apiPort,
      steam: env.steam,
    );
    expect(defaults.autostartInterval, const Duration(seconds: 10));
  });

  test('instance_stopped_by_the_admin_before_the_reboot', () async {
    final env = TestEnv();
    env.installValheim();
    final first = await env.start();
    final instance = await createRunning(first);
    await runStop(first, instance.id);
    await env.kill(first);

    final second = await env.start();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(second.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.launches, hasLength(1));
    expect(lastRequestedState(env, instance.id), isEmpty);
  });

  test('crash_looped_instance_not_autostarted', () async {
    final env = TestEnv();
    env.installValheim();
    final first = await env.start();
    final instance = await createRunning(first);
    expect(lastRequestedState(env, instance.id), 'running');
    // The daemon restarts with the instance in error: crash_loop.
    final second = await reopenWithState(
      env,
      first,
      instance.id,
      InstanceState.error,
      crashLoopReason,
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = second.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(after.stateReason, crashLoopReason);
    expect(env.process.launches, hasLength(1));
  });

  test('autostart_fails', () async {
    final env = TestEnv();
    env.installValheim();
    final first = await env.start();
    final instance = await createRunning(first);
    await env.kill(first);
    env.process.launchError = YaguraException(
      'launch_failed',
      'CreateProcess failed',
    );

    final second = await env.start();

    await eventually(
      () => env.process.launches.length == 2,
      reason: 'the autostart attempt',
    );
    await eventually(
      () => second.instances.get(instance.id).state == InstanceState.stopped,
      reason: 'the failed start to end',
    );
    // Handled like any failed Start: not retried, now or after another
    // restart.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(env.process.launches, hasLength(2));
    expect(second.instances.get(instance.id).state, InstanceState.stopped);
    await env.kill(second);
    env.process.launchError = null;
    final third = await env.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(env.process.launches, hasLength(2));
    expect(third.instances.get(instance.id).state, InstanceState.stopped);
  });
}
