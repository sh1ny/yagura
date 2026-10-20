import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';

import '../support/content_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';

void main() {
  test('update_while_running', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    await rig.daemon.operations.whenDone(
      rig.daemon.instances.start(instance.id).id,
    );
    final daemon = rig.daemon;
    expect(
      linksTo(rig.staged(instance, '@CF'), rig.versionDir(cfMod, '1700000000')),
      isTrue,
    );
    // A newer version of the mod appears.
    rig.workshop.items[cfMod]!.timeUpdated = 1700500000;
    await rig.checkUpdates(instance);

    final op = daemon.instances.update(instance.id);
    final events = await daemon.operations.watch(op.id).toList();

    final steps = [
      for (final e in events.whereType<StepStartedEvent>()) e.step,
    ];
    expect(
      steps,
      containsAllInOrder([
        'stop',
        'snapshot',
        'download',
        'update_mods',
        'apply_config',
        'start',
      ]),
    );
    expect(
      (events.last as FinishedEvent).operation.status,
      OperationStatus.succeeded,
      reason: (events.last as FinishedEvent).operation.resultMessage,
    );
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
    expect(rig.env.process.launches, hasLength(2));
    expect(
      linksTo(rig.staged(instance, '@CF'), rig.versionDir(cfMod, '1700500000')),
      isTrue,
    );
    expect((await rig.mod(instance, cfMod)).updateAvailable, isFalse);
  });

  test('mod_update_fails_after_stop', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.item(vppMod, title: 'VPP');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod), ModSpec(vppMod)]);
    await rig.daemon.operations.whenDone(
      rig.daemon.instances.start(instance.id).id,
    );
    final daemon = rig.daemon;
    final cfLink = resolvedTarget(rig.staged(instance, '@CF'));
    final vppLink = resolvedTarget(rig.staged(instance, '@VPP'));
    // VPP has a new version; CF has been taken down.
    rig.workshop.items[vppMod]!.timeUpdated = 1700500000;
    rig.workshop.items[cfMod]!.timeUpdated = 1700500000;
    await rig.checkUpdates(instance);
    rig.steam.failures[cfMod] = YaguraException(
      'workshop_item_unavailable',
      'the item is unavailable',
    );

    final done = await daemon.operations.whenDone(
      daemon.instances.update(instance.id).id,
    );

    // The mods are the last step: the server was stopped and is not started.
    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'workshop_item_unavailable');
    final after = daemon.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(rig.env.process.launches, hasLength(1));
    expect(resolvedTarget(rig.staged(instance, '@CF')), cfLink);
    expect(resolvedTarget(rig.staged(instance, '@VPP')), vppLink);
  });

  test('update_without_mods_while_running', () async {
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
