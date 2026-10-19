import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('acknowledge_a_crash_loop', () async {
    final env = TestEnv();
    env.installValheim();
    var daemon = await env.start();
    final instance = await createInstalled(daemon);
    daemon = await reopenWithState(
      env,
      daemon,
      instance.id,
      InstanceState.error,
      'crash_loop',
    );
    expect(daemon.instances.get(instance.id).state, InstanceState.error);

    final acknowledged = daemon.instances.acknowledge(instance.id);

    expect(acknowledged.state, InstanceState.stopped);
    expect(acknowledged.stateReason, isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('start_refused_with_invalid_settings', () async {
    final env = TestEnv();
    env.installValheim();
    var daemon = await env.start();
    final instance = await createInstalled(daemon);
    daemon = await reopenWithState(
      env,
      daemon,
      instance.id,
      InstanceState.error,
      'settings_invalid',
    );

    expect(
      () => daemon.instances.start(instance.id),
      failsWith('invalid_state', messageHas: ['settings_invalid']),
    );

    final after = daemon.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(after.stateReason, 'settings_invalid');
    expect(daemon.operations.listForInstance(instance.id).map((o) => o.kind), [
      OperationKind.install,
    ]);
  });

  test('update_clears_an_interrupted_update', () async {
    final env = TestEnv();
    env.installValheim();
    var daemon = await env.start();
    final instance = await createInstalled(daemon);
    daemon = await reopenWithState(
      env,
      daemon,
      instance.id,
      InstanceState.error,
      'update_interrupted',
    );

    final op = daemon.instances.update(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    final after = daemon.instances.get(instance.id);
    expect(after.state, InstanceState.stopped);
    expect(after.stateReason, isEmpty);
  });

  test('stop_and_delete_are_the_only_other_exits_from_any_error', () async {
    final env = TestEnv();
    env.installValheim();
    var daemon = await env.start();
    final instance = await createInstalled(daemon);
    daemon = await reopenWithState(
      env,
      daemon,
      instance.id,
      InstanceState.error,
      'crash_loop',
    );

    expect(
      () => daemon.instances.update(instance.id),
      failsWith('invalid_state'),
    );
    expect(
      () => daemon.instances.install(instance.id),
      failsWith('invalid_state'),
    );
    final stop = daemon.instances.stop(instance.id);
    expect(
      (await daemon.operations.whenDone(stop.id)).status,
      OperationStatus.succeeded,
    );
    expect(daemon.instances.get(instance.id).state, InstanceState.error);
    final delete = daemon.instances.delete(instance.id);
    expect(
      (await daemon.operations.whenDone(delete.id)).status,
      OperationStatus.succeeded,
    );
  });

  test('settings_fixed_by_valid_settings_leave_settings_invalid', () async {
    final env = TestEnv();
    env.installValheim();
    var daemon = await env.start();
    final instance = await createInstalled(daemon);
    daemon = await reopenWithState(
      env,
      daemon,
      instance.id,
      InstanceState.error,
      'settings_invalid',
    );

    final fixed = daemon.instances.updateSettings(
      UpdateSettingsRequest(
        instanceId: instance.id,
        settings: {'serverName': 'Fixed'},
      ),
    );

    expect(fixed.state, InstanceState.stopped);
    expect(fixed.stateReason, isEmpty);
  });

  group('a rejected run record', () {
    Future<(TestEnv, Daemon, String)> rejected() async {
      final env = TestEnv();
      env.installValheim();
      final first = await env.start();
      final instance = await createRunning(first);
      await env.kill(first);
      env.process.rejectedRelayPid = 4242;
      final daemon = await env.start();
      return (env, daemon, instance.id);
    }

    test('acknowledge_a_rejected_run_record', () async {
      final (_, daemon, id) = await rejected();
      final before = daemon.instances.get(id);
      expect(before.state, InstanceState.error);
      expect(before.stateReason, 'run_record_rejected');
      expect(daemon.instances.runs.unresolvedFor(id), hasLength(1));

      final acknowledged = daemon.instances.acknowledge(id);

      expect(acknowledged.state, InstanceState.stopped);
      expect(acknowledged.stateReason, isEmpty);
      expect(acknowledged.warning, contains('4242'));
      expect(daemon.instances.runs.unresolvedFor(id), isEmpty);
      expect(
        daemon.instances.runs.all(id).last.endReason,
        'run_record_rejected',
      );
    });

    test('start_refused_after_a_rejected_run_record', () async {
      final (_, daemon, id) = await rejected();

      expect(
        () => daemon.instances.start(id),
        failsWith('invalid_state', messageHas: ['run_record_rejected']),
      );
      expect(daemon.instances.get(id).state, InstanceState.error);
    });

    test('stop_retries_the_verification', () async {
      final (env, daemon, id) = await rejected();
      final server = env.process.servers.single;

      final refused = await runStop(daemon, id);
      expect(refused.status, OperationStatus.failed);
      expect(refused.resultReason, 'run_record_rejected');
      expect(daemon.instances.get(id).state, InstanceState.error);

      env.process
        ..rejectedRelayPid = null
        ..survivors.add(server);
      final done = await runStop(daemon, id);

      expect(done.status, OperationStatus.succeeded);
      expect(daemon.instances.get(id).state, InstanceState.stopped);
      expect(daemon.instances.runs.unresolvedFor(id), isEmpty);
    });
  });
}
