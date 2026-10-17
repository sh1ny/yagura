import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';

import '../support/daemon_support.dart';

void main() {
  test('update_while_running', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);

    final op = daemon.instances.update(instance.id);
    final events = await daemon.operations.watch(op.id).toList();

    const wanted = {'stop', 'snapshot', 'download', 'apply_config', 'start'};
    final steps = events
        .whereType<StepStartedEvent>()
        .map((e) => e.step)
        .where(wanted.contains);
    expect(steps, ['stop', 'snapshot', 'download', 'apply_config', 'start']);
    expect(
      (events.last as FinishedEvent).operation.status,
      OperationStatus.succeeded,
    );
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
    expect(env.process.stops, hasLength(1));
    expect(env.process.launches, hasLength(2));
    expect(env.snapshotter.taken.single.reason, 'pre_update');
  });

  test('update_of_a_stopped_instance_leaves_it_stopped', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final op = daemon.instances.update(instance.id);
    final events = await daemon.operations.watch(op.id).toList();

    final steps = events.whereType<StepStartedEvent>().map((e) => e.step);
    expect(steps, isNot(contains('stop')));
    expect(steps, isNot(contains('start')));
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.launches, isEmpty);
  });

  test('update_fails_after_stop', () async {
    final env = TestEnv();
    env.installValheim();
    final snapshots = DirectorySnapshotter(root: p.join(env.data, 'snapshots'));
    final daemon = await env.start(snapshots: snapshots);
    final instance = await createRunning(daemon);
    env.steam.failure = YaguraException(
      'steam_stalled',
      'SteamCMD made no progress',
    );

    final op = daemon.instances.update(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'steam_stalled');
    final after = daemon.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(after.stateReason, 'steam_stalled');
    // Not started again, and the snapshot taken before the download is kept.
    expect(env.process.launches, hasLength(1));
    expect(env.process.stops, hasLength(1));
    expect(snapshots.list(instance.id).single.reason, 'pre_update');
  });
}
