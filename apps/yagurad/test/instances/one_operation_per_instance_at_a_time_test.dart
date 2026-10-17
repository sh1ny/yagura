import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('concurrent_requests_on_one_instance', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    final held = env.steam.hold = Completer<void>();
    final install = daemon.instances.install(instance.id);
    await env.steam.reachedDownload.future;

    final update = daemon.instances.update(instance.id);

    expect(update.status, OperationStatus.queued);
    expect(update.queuePosition, 1);
    expect(daemon.operations.get(install.id)!.status, OperationStatus.running);
    expect(env.steam.runs, hasLength(1));
    held.complete();
    expect(
      (await daemon.operations.whenDone(install.id)).status,
      OperationStatus.succeeded,
    );
    final done = await daemon.operations.whenDone(update.id);
    expect(done.status, OperationStatus.succeeded);
    expect(
      done.startedAt!.isBefore(daemon.operations.get(install.id)!.endedAt!),
      isFalse,
    );
    expect(env.steam.runs, hasLength(2));
  });

  test('stop_requested_while_starting', () async {
    final env = TestEnv();
    env.installValheim(hooks: 'exports.onPreStart = () => ({});');
    final hooks = GatedHookHost();
    final daemon = await env.start(hookHost: hooks.host);
    final instance = await createInstalled(daemon);
    final start = daemon.instances.start(instance.id);
    await eventually(() => hooks.workers.isNotEmpty, reason: 'hook running');
    expect(daemon.operations.get(start.id)!.currentStep, 'hook:onPreStart');

    final stop = daemon.instances.stop(instance.id);
    hooks.workers.single.release();

    final started = await daemon.operations.whenDone(start.id);
    final stopped = await daemon.operations.whenDone(stop.id);
    expect(started.status, OperationStatus.cancelled);
    expect(stopped.status, OperationStatus.succeeded);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.launches, isEmpty);
  });

  test('queued_operation_becomes_invalid', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    env.steam.hold = Completer<void>();
    final install = daemon.instances.install(instance.id);
    await env.steam.reachedDownload.future;
    final start = daemon.instances.start(instance.id);
    expect(start.status, OperationStatus.queued);

    daemon.operations.cancel(install.id);

    expect(
      (await daemon.operations.whenDone(install.id)).status,
      OperationStatus.cancelled,
    );
    final failed = await daemon.operations.whenDone(start.id);
    expect(failed.status, OperationStatus.failed);
    expect(failed.resultReason, 'invalid_state');
    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);
  });

  test('queue_full', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    final held = env.steam.hold = Completer<void>();
    daemon.instances.install(instance.id);
    await env.steam.reachedDownload.future;
    for (var i = 0; i < 10; i++) {
      daemon.instances.update(instance.id);
    }
    expect(daemon.operations.queuedCount(instance.id), 10);
    final before = daemon.operations.listForInstance(instance.id).length;

    expect(() => daemon.instances.update(instance.id), failsWith('queue_full'));

    expect(daemon.operations.listForInstance(instance.id), hasLength(before));
    held.complete();
  });

  test('anonymous_installs_serialise_on_the_steamcmd_lock', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final held = env.steam.hold = Completer<void>();
    final instances = [
      for (var i = 0; i < 3; i++)
        await createValheim(
          daemon,
          name: 'Heavy $i',
          ports: {'game': 3000 + i * 10},
          directory: p.join(env.data, 'instances', 'heavy$i'),
        ),
    ];
    final ops = [for (final i in instances) daemon.instances.install(i.id)];

    await env.steam.reachedDownload.future;
    await eventually(
      () => ops
          .skip(1)
          .every(
            (o) =>
                daemon.operations.get(o.id)!.currentStep ==
                'waiting_for_steamcmd',
          ),
      reason: 'the others wait for SteamCMD',
    );
    expect(env.steam.runs, hasLength(1));

    held.complete();
    for (final op in ops) {
      expect(
        (await daemon.operations.whenDone(op.id)).status,
        OperationStatus.succeeded,
      );
    }
    expect(env.steam.runs, hasLength(3));
  });

  test('stop_during_the_health_wait', () async {
    final env = TestEnv();
    // The port never opens and the start timeout is far away.
    env.installValheimHealth(
      'type: port\n  port: game\n  start_timeout_seconds: 120',
    );
    final daemon = await env.start();
    final instance = await createValheim(
      daemon,
      ports: {'game': await freePort()},
    );
    await daemon.operations.whenDone(daemon.instances.install(instance.id).id);
    final start = daemon.instances.start(instance.id);
    await eventually(
      () => daemon.operations.get(start.id)!.currentStep == 'health',
      reason: 'the health wait',
    );
    expect(env.process.servers, hasLength(1));
    final asked = Stopwatch()..start();

    final stop = daemon.instances.stop(instance.id);
    final stopped = await daemon.operations.whenDone(stop.id);
    final started = await daemon.operations.whenDone(start.id);

    // The wait ended at once, not at the 120 s timeout, and the server is
    // gone through the plugin's stop plan (grace period 30 s).
    expect(asked.elapsed, lessThan(const Duration(seconds: 5)));
    expect(started.status, OperationStatus.cancelled);
    expect(stopped.status, OperationStatus.succeeded);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.stops.single.grace, const Duration(seconds: 30));
    await expectLater(env.process.servers.single.exitCode, completes);
  });
}
