import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/platform/disk_space.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';

import '../support/daemon_support.dart';

/// Writes the world save of an instance.
File writeSave(String directory, String content) {
  final file = File(p.join(directory, 'save', 'world.db'));
  file.parent.createSync(recursive: true);
  return file..writeAsStringSync(content);
}

String snapshotsRoot(TestEnv env) => p.join(env.data, 'snapshots');

DirectorySnapshotter realSnapshotter(
  TestEnv env, {
  DiskSpaceProbe? diskSpace,
  DateTime Function()? clock,
  Future<void> Function()? beforeCopyingBack,
}) => DirectorySnapshotter(
  root: snapshotsRoot(env),
  clock: clock,
  diskSpace: diskSpace,
  beforeCopyingBack: beforeCopyingBack,
);

/// The file of a snapshot holding `save/world.db`.
File snapshotSave(TestEnv env, SnapshotInfo snapshot) => File(
  p.join(
    snapshotsRoot(env),
    snapshot.instanceId,
    snapshot.id,
    'data',
    '0',
    'world.db',
  ),
);

Future<Operation> update(
  Daemon daemon,
  String id, {
  bool skipSnapshot = false,
}) async {
  final op = daemon.instances.update(id, skipSnapshot: skipSnapshot);
  return daemon.operations.whenDone(op.id);
}

void main() {
  test('snapshot_before_update', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(snapshots: realSnapshotter(env));
    final instance = await createInstalled(daemon);
    writeSave(instance.directory, 'world v1');
    final held = env.steam.hold = Completer<void>();

    final op = daemon.instances.update(instance.id);
    await eventually(
      () => daemon.instances.get(instance.id).state == InstanceState.updating,
      reason: 'the download to begin',
    );

    // The snapshot is listed while the download is still held.
    final snapshots = daemon.instances.listSnapshots(instance.id);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.reason, 'pre_update');
    expect(snapshots.single.instanceName, 'Friends');
    expect(snapshotSave(env, snapshots.single).readAsStringSync(), 'world v1');
    held.complete();
    expect(
      (await daemon.operations.whenDone(op.id)).status,
      OperationStatus.succeeded,
    );
  });

  test('not_enough_space_for_a_snapshot', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(
      snapshots: realSnapshotter(
        env,
        // 1,000 bytes of save need 2,000 free; the volume has 1,999.
        diskSpace: (path) async =>
            const DiskSpace(volume: 'S:\\', freeBytes: 1999),
      ),
    );
    final instance = await createRunning(daemon);
    File(p.join(instance.directory, 'save', 'world.db'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List.filled(1000, 1));
    final runsBefore = env.steam.runs.length;
    final launchesBefore = env.process.launches.length;

    final done = await update(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'insufficient_disk');
    expect(done.resultMessage, contains('S:\\'));
    // Nothing was changed: still running, never stopped, nothing downloaded,
    // no snapshot.
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
    expect(env.process.stops, isEmpty);
    expect(env.process.launches, hasLength(launchesBefore));
    expect(env.steam.runs, hasLength(runsBefore));
    expect(daemon.instances.listSnapshots(instance.id), isEmpty);
  });

  test('restore_a_snapshot', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(snapshots: realSnapshotter(env));
    final instance = await createInstalled(daemon);
    final save = writeSave(instance.directory, 'world v1');
    await update(daemon, instance.id);
    final original = daemon.instances.listSnapshots(instance.id).single;
    save.writeAsStringSync('world v2');

    final op = daemon.instances.restoreSnapshot(instance.id, original.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(done.kind, OperationKind.restore);
    expect(save.readAsStringSync(), 'world v1');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    final snapshots = daemon.instances.listSnapshots(instance.id);
    final preRestore = snapshots.singleWhere((s) => s.reason == 'pre_restore');
    expect(snapshotSave(env, preRestore).readAsStringSync(), 'world v2');
    expect(snapshots.map((s) => s.id), contains(original.id));
  });

  test('restoring_the_oldest_snapshot', () async {
    final env = TestEnv();
    env.installValheim();
    final replacing = Completer<void>();
    final gate = Completer<void>();
    final daemon = await env.start(
      snapshots: realSnapshotter(
        env,
        beforeCopyingBack: () async {
          if (!replacing.isCompleted) replacing.complete();
          await gate.future;
        },
      ),
    );
    final instance = await createInstalled(daemon);
    final save = writeSave(instance.directory, 'gen 0');
    for (var generation = 1; generation <= 3; generation++) {
      await update(daemon, instance.id);
      save.writeAsStringSync('gen $generation');
    }
    final three = daemon.instances.listSnapshots(instance.id);
    expect(three, hasLength(3));
    final oldest = three.last;
    expect(snapshotSave(env, oldest).readAsStringSync(), 'gen 0');

    final op = daemon.instances.restoreSnapshot(instance.id, oldest.id);
    await replacing.future;

    // While the restore replaces data, the source is pinned: nothing was
    // pruned, even though the pre_restore snapshot is a fourth one.
    final during = daemon.instances.listSnapshots(instance.id);
    expect(during, hasLength(4));
    expect(during.map((s) => s.id), contains(oldest.id));

    gate.complete();
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(save.readAsStringSync(), 'gen 0');
    final after = daemon.instances.listSnapshots(instance.id);
    expect(after, hasLength(3));
    expect(after.map((s) => s.id), isNot(contains(oldest.id)));
    expect(after.first.reason, 'pre_restore');
  });

  test('snapshot_skipped_on_request', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(snapshots: realSnapshotter(env));
    final instance = await createInstalled(daemon);
    writeSave(instance.directory, 'world');

    final done = await update(daemon, instance.id, skipSnapshot: true);

    expect(done.status, OperationStatus.succeeded);
    expect(done.resultMessage, contains('snapshot: skipped'));
    expect(daemon.instances.listSnapshots(instance.id), isEmpty);
    final steps = (await daemon.operations.watch(done.id).toList())
        .whereType<StepStartedEvent>()
        .map((e) => e.step);
    expect(steps, isNot(contains('snapshot')));
  });

  test('pre_delete_snapshot_of_a_deleted_instance', () async {
    final env = TestEnv();
    env.installValheim();
    var now = DateTime.utc(2030, 1, 10, 12);
    final daemon = await env.start(realSnapshots: true, clock: () => now);
    final instance = await createInstalled(daemon, name: 'Friends');
    writeSave(instance.directory, 'world');
    final op = daemon.instances.delete(
      instance.id,
      deleteFiles: true,
      confirmName: 'Friends',
    );
    await daemon.operations.whenDone(op.id);

    now = now.add(const Duration(days: 2));
    final orphans = daemon.instances.listOrphanSnapshots();
    expect(orphans, hasLength(1));
    expect(orphans.single.instanceName, 'Friends');
    expect(orphans.single.reason, 'pre_delete');
    expect(snapshotSave(env, orphans.single).readAsStringSync(), 'world');

    // 29 days after the delete it is still there at startup...
    now = DateTime.utc(2030, 1, 10, 12).add(const Duration(days: 29));
    await env.kill(daemon);
    var restarted = await env.start(realSnapshots: true, clock: () => now);
    expect(restarted.instances.listOrphanSnapshots(), hasLength(1));

    // ...and 30 days after the delete a startup removes it.
    await env.kill(restarted);
    now = DateTime.utc(2030, 1, 10, 12).add(const Duration(days: 30));
    restarted = await env.start(realSnapshots: true, clock: () => now);
    expect(restarted.instances.listOrphanSnapshots(), isEmpty);
    expect(Directory(snapshotsRoot(env)).listSync(), isEmpty);
  });

  test('daemon_killed_during_a_restore', () async {
    final env = TestEnv();
    env.installValheim();
    final replacing = Completer<void>();
    final gate = Completer<void>();
    final daemon = await env.start(
      snapshots: realSnapshotter(
        env,
        beforeCopyingBack: () async {
          replacing.complete();
          await gate.future;
        },
      ),
    );
    final instance = await createInstalled(daemon);
    writeSave(instance.directory, 'world v1');
    await update(daemon, instance.id);
    final original = daemon.instances.listSnapshots(instance.id).single;
    final op = daemon.instances.restoreSnapshot(instance.id, original.id);
    await replacing.future; // the data path is removed, nothing copied back

    await env.kill(daemon);
    // The killed daemon's restore ends here, as a dead process would.
    gate.completeError(YaguraException('internal_error', 'killed'));
    final restarted = await env.start(snapshots: realSnapshotter(env));

    expect(
      restarted.operations.get(op.id)!.status,
      OperationStatus.interrupted,
    );
    final after = restarted.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(after.stateReason, 'restore_interrupted');
    expect(
      () => restarted.instances.start(instance.id),
      failsWith('invalid_state'),
    );
    expect(
      restarted.instances
          .listSnapshots(instance.id)
          .map((s) => s.reason)
          .toSet(),
      containsAll(['pre_update', 'pre_restore']),
    );
  });

  test('restore_exits_restore_interrupted', () async {
    final env = TestEnv();
    env.installValheim();
    final replacing = Completer<void>();
    final gate = Completer<void>();
    final daemon = await env.start(
      snapshots: realSnapshotter(
        env,
        beforeCopyingBack: () async {
          if (!replacing.isCompleted) replacing.complete();
          await gate.future;
        },
      ),
    );
    final instance = await createInstalled(daemon);
    final save = writeSave(instance.directory, 'world v1');
    await update(daemon, instance.id);
    final original = daemon.instances.listSnapshots(instance.id).single;
    daemon.instances.restoreSnapshot(instance.id, original.id);
    await replacing.future;
    await env.kill(daemon);
    gate.completeError(YaguraException('internal_error', 'killed'));
    final restarted = await env.start(snapshots: realSnapshotter(env));
    expect(
      restarted.instances.get(instance.id).stateReason,
      'restore_interrupted',
    );
    expect(save.existsSync(), isFalse);

    // Update and Validate are refused from this error; a restore is the exit.
    expect(
      () => restarted.instances.update(instance.id),
      failsWith('invalid_state'),
    );
    final op = restarted.instances.restoreSnapshot(instance.id, original.id);
    final done = await restarted.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(save.readAsStringSync(), 'world v1');
    final after = restarted.instances.get(instance.id);
    expect(after.state, InstanceState.stopped);
    expect(after.stateReason, isEmpty);
  });

  test('restoring_an_unknown_snapshot_is_refused', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(snapshots: realSnapshotter(env));
    final instance = await createInstalled(daemon);

    expect(
      () => daemon.instances.restoreSnapshot(instance.id, 'snap-nope'),
      failsWith('snapshot_not_found'),
    );
  });

  test('acknowledging_restore_interrupted_forgets_the_marker', () async {
    final env = TestEnv();
    env.installValheim();
    final replacing = Completer<void>();
    final gate = Completer<void>();
    final daemon = await env.start(
      snapshots: realSnapshotter(
        env,
        beforeCopyingBack: () async {
          if (!replacing.isCompleted) replacing.complete();
          await gate.future;
        },
      ),
    );
    final instance = await createInstalled(daemon);
    writeSave(instance.directory, 'world v1');
    await update(daemon, instance.id);
    final original = daemon.instances.listSnapshots(instance.id).single;
    daemon.instances.restoreSnapshot(instance.id, original.id);
    await replacing.future;
    await env.kill(daemon);
    gate.completeError(YaguraException('internal_error', 'killed'));
    final restarted = await env.start(snapshots: realSnapshotter(env));

    final after = restarted.instances.acknowledge(instance.id);
    expect(after.state, InstanceState.stopped);
    expect(after.warning, contains('restore was interrupted'));

    // Another restart does not raise the error again.
    await env.kill(restarted);
    final again = await env.start(snapshots: realSnapshotter(env));
    expect(again.instances.get(instance.id).state, InstanceState.stopped);
  });
}
