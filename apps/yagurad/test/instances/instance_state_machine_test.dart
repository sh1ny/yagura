import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('start_from_stopped', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    expect(instance.state, InstanceState.stopped);
    final states = <InstanceState>[];
    daemon.instances.events.listen((e) {
      if (e is InstanceChanged && e.instance.id == instance.id) {
        states.add(e.instance.state);
      }
    });

    final op = daemon.instances.start(instance.id);
    final done = await daemon.operations.whenDone(op.id);
    await Future<void>.delayed(Duration.zero);

    expect(done.status, OperationStatus.succeeded);
    expect(states, [InstanceState.starting, InstanceState.running]);
    final running = daemon.instances.get(instance.id);
    expect(running.state, InstanceState.running);
    expect(running.pid, env.process.servers.single.pid);
    final launch = env.process.launches.single;
    expect(launch.instanceId, instance.id);
    expect(launch.executable.endsWith('valheim_server.exe'), isTrue);
    expect(
      launch.args,
      containsAllInOrder(['-name', 'Friends', '-port', '2456']),
    );
  });

  test('start_while_not_installed', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);

    expect(
      () => daemon.instances.start(instance.id),
      failsWith('not_installed'),
    );

    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);
    expect(daemon.operations.listForInstance(instance.id), isEmpty);
    expect(env.process.launches, isEmpty);
  });

  test('stop_ends_a_running_instance', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);

    final op = daemon.instances.stop(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(done.resultReason, 'stopped_by:graceful');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.stops.single.grace, const Duration(seconds: 30));
  });

  test('a_failed_launch_leaves_the_instance_stopped', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    env.process.launchError = YaguraException(
      'launch_failed',
      'CreateProcess failed',
    );

    final op = daemon.instances.start(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'launch_failed');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });
}
