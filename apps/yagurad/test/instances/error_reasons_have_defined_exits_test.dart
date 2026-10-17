import 'package:test/test.dart';
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
}
