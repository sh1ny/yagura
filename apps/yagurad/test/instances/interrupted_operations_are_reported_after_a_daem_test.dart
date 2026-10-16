import 'dart:async';

import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('daemon_killed_during_install', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    env.steam.hold = Completer<void>(); // the download never ends
    final op = daemon.instances.install(instance.id);
    await env.steam.reachedDownload.future;
    expect(daemon.instances.get(instance.id).state, InstanceState.installing);

    await env.kill(daemon);
    final restarted = await env.start();

    expect(
      restarted.operations.get(op.id)!.status,
      OperationStatus.interrupted,
    );
    expect(restarted.operations.get(op.id)!.endedAt, isNotNull);
    expect(
      restarted.instances.get(instance.id).state,
      InstanceState.notInstalled,
    );
    expect(
      restarted.instances.recoveryNotices.map((n) => (n.instanceId, n.kind)),
      contains((instance.id, 'install_interrupted')),
    );

    // A new install can be started.
    env.steam.hold = null;
    final again = restarted.instances.install(instance.id);
    final done = await restarted.operations.whenDone(again.id);
    expect(done.status, OperationStatus.succeeded);
    expect(restarted.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('daemon_killed_during_an_update', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    final held = env.steam.hold = Completer<void>();
    final op = daemon.instances.update(instance.id);
    await eventually(
      () => daemon.instances.get(instance.id).state == InstanceState.updating,
      reason: 'updating',
    );

    await env.kill(daemon);
    held.complete();
    final restarted = await env.start();

    expect(
      restarted.operations.get(op.id)!.status,
      OperationStatus.interrupted,
    );
    final after = restarted.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(after.stateReason, 'update_interrupted');
    expect(
      restarted.instances.recoveryNotices.map((n) => n.kind),
      contains('update_interrupted'),
    );
  });
}
