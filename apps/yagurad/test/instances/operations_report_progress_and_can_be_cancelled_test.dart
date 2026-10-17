import 'dart:async';

import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('install_progress_streamed', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final events = await daemon.operations.watch(op.id).toList();

    final steps = events.whereType<StepStartedEvent>().map((e) => e.step);
    expect(steps, ['steam_login', 'download', 'post_install']);
    final progress = events.whereType<ProgressEvent>().toList();
    expect(progress.map((e) => e.step).toSet(), {'download'});
    expect(progress.first.percent, 10);
    expect(progress.first.bytesDone, 500);
    expect(progress.first.bytesTotal, 5000);
    expect(progress.last.percent, 100);
    expect(progress.last.bytesDone, 5000);
    final finished = events.last as FinishedEvent;
    expect(finished.operation.status, OperationStatus.succeeded);
    // Sequence numbers are strictly increasing from 1.
    expect(events.map((e) => e.sequence), [
      for (var i = 1; i <= events.length; i++) i,
    ]);
    expect(finished.operation.lastSequence, events.last.sequence);
  });

  test('install_cancelled_mid_download', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    env.steam.hold = Completer<void>();
    final op = daemon.instances.install(instance.id);
    await env.steam.reachedDownload.future;

    daemon.operations.cancel(op.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.cancelled);
    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);
  });

  test('stop_cancels_queued_starts', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    final held = env.steam.hold = Completer<void>();
    final running = daemon.instances.update(instance.id);
    await eventually(
      () =>
          daemon.operations.get(running.id)!.status == OperationStatus.running,
      reason: 'update running',
    );
    final start = daemon.instances.start(instance.id);
    final restart = daemon.instances.restart(instance.id);
    final laterUpdate = daemon.instances.update(instance.id);

    final stop = daemon.instances.stop(instance.id);

    expect(daemon.operations.get(start.id)!.status, OperationStatus.cancelled);
    expect(
      daemon.operations.get(restart.id)!.status,
      OperationStatus.cancelled,
    );
    expect(daemon.operations.get(stop.id)!.queuePosition, 1);
    expect(daemon.operations.get(laterUpdate.id)!.queuePosition, 2);
    held.complete();
    expect(
      (await daemon.operations.whenDone(stop.id)).status,
      OperationStatus.succeeded,
    );
    expect(
      (await daemon.operations.whenDone(laterUpdate.id)).status,
      OperationStatus.succeeded,
    );
  });

  test('progress_is_coalesced_and_a_resume_gets_the_latest', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    final op = daemon.instances.install(instance.id);
    await daemon.operations.whenDone(op.id);

    final replay = await daemon.operations.watch(op.id).toList();

    final progress = replay.whereType<ProgressEvent>().toList();
    expect(progress, hasLength(1));
    expect(progress.single.percent, 100);
    expect(replay.whereType<EventsDroppedEvent>(), isEmpty);
    expect(replay.last, isA<FinishedEvent>());
    // A resume after the last progress gets only what came later.
    final tail = await daemon.operations
        .watch(op.id, afterSequence: progress.single.sequence)
        .toList();
    expect(tail.map((e) => e.runtimeType), [StepStartedEvent, FinishedEvent]);
  });

  test('update_cancelled_after_the_server_was_stopped', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    env.steam.hold = Completer<void>();
    final op = daemon.instances.update(instance.id);
    await eventually(
      () => daemon.instances.get(instance.id).state == InstanceState.updating,
      reason: 'the download to begin',
    );
    expect(env.process.stops, hasLength(1));

    daemon.operations.cancel(op.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.cancelled);
    // The server stays stopped: a cancel never restarts it.
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.launches, hasLength(1));
    final steps = (await daemon.operations.watch(op.id).toList())
        .whereType<StepStartedEvent>()
        .map((e) => e.step);
    expect(steps, isNot(contains('start')));
  });
}
