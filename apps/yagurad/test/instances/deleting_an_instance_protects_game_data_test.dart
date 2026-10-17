import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

/// Puts a world save into the instance directory.
File writeSave(String directory) {
  final file = File(p.join(directory, 'save', 'world.db'));
  file.parent.createSync(recursive: true);
  return file..writeAsStringSync('world');
}

void main() {
  test('delete_an_instance_whose_plugin_is_missing', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    final save = writeSave(instance.directory);
    Directory(p.join(env.pluginsDir, 'valheim')).deleteSync(recursive: true);

    await daemon.instances.reloadPlugins();
    final broken = daemon.instances.get(instance.id);
    expect(broken.state, InstanceState.error);
    expect(broken.stateReason, 'plugin_missing');

    final op = daemon.instances.delete(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(daemon.instances.list(), isEmpty);
    expect(save.existsSync(), isTrue);
  });

  test('delete_keeping_files', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    final save = writeSave(instance.directory);

    final op = daemon.instances.delete(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(daemon.instances.list(), isEmpty);
    expect(save.existsSync(), isTrue);
    // The operation outlives the instance.
    expect(daemon.operations.get(op.id)!.status, OperationStatus.succeeded);
  });

  test('delete_with_wrong_confirmation', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    final save = writeSave(instance.directory);
    final before = daemon.operations.listForInstance(instance.id).length;

    expect(
      () => daemon.instances.delete(
        instance.id,
        deleteFiles: true,
        confirmName: 'not the name',
      ),
      failsWith('confirmation_mismatch'),
    );

    expect(daemon.operations.listForInstance(instance.id), hasLength(before));
    expect(daemon.instances.find(instance.id), isNotNull);
    expect(save.existsSync(), isTrue);
  });

  test('delete_with_files_snapshots_then_marks_then_removes', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(withSnapshotter: true);
    final instance = await createInstalled(daemon, name: 'Friends');
    writeSave(instance.directory);

    final op = daemon.instances.delete(
      instance.id,
      deleteFiles: true,
      confirmName: 'Friends',
    );
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(env.snapshotter.taken.single.reason, 'pre_delete');
    expect(env.snapshotter.taken.single.dataPaths, [
      p.join(instance.directory, 'save'),
    ]);
    expect(Directory(instance.directory).existsSync(), isFalse);
    expect(daemon.instances.list(), isEmpty);
  });

  test('delete_is_refused_while_another_operation_runs', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    env.steam.hold = Completer<void>();
    daemon.instances.install(instance.id);
    await env.steam.reachedDownload.future;

    expect(
      () => daemon.instances.delete(instance.id),
      failsWith('invalid_state'),
    );
    env.steam.hold!.complete();
  });

  test('startup_removes_marked_directories_without_a_row', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final kept = await createInstalled(daemon, name: 'Kept');
    final gone = await createInstalled(
      daemon,
      name: 'Gone',
      ports: {'game': 2556},
    );
    await env.kill(daemon);
    // A crash after the rows were removed: marker present, no row.
    final orphan = Directory(p.join(env.data, 'instances', 'orphan'))
      ..createSync(recursive: true);
    File(p.join(orphan.path, 'junk')).writeAsStringSync('x');
    Directory(p.join(orphan.path, '.yagura')).createSync();
    File(p.join(orphan.path, '.yagura', 'deleting')).writeAsStringSync('');
    // A marker whose rows were never deleted: only the marker goes.
    Directory(p.join(gone.directory, '.yagura')).createSync();
    final marker = File(p.join(gone.directory, '.yagura', 'deleting'))
      ..writeAsStringSync('');

    final restarted = await env.start();

    expect(orphan.existsSync(), isFalse);
    expect(marker.existsSync(), isFalse);
    expect(Directory(gone.directory).existsSync(), isTrue);
    expect(Directory(kept.directory).existsSync(), isTrue);
    expect(
      restarted.instances.list().map((i) => i.name),
      unorderedEquals(['Kept', 'Gone']),
    );
  });

  test('startup_sweeps_marked_directories_below_the_first_level', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final nested = await createValheim(
      daemon,
      name: 'Nested',
      directory: p.join(env.data, 'instances', 'group', 'server'),
    );
    await env.kill(daemon);
    // Rows gone, files left: a nested orphan with a marker.
    final orphan = Directory(p.join(env.data, 'instances', 'group', 'orphan'))
      ..createSync(recursive: true);
    File(p.join(orphan.path, 'junk')).writeAsStringSync('x');
    Directory(p.join(orphan.path, '.yagura')).createSync();
    File(p.join(orphan.path, '.yagura', 'deleting')).writeAsStringSync('');
    // A nested instance whose rows were never deleted: only the marker goes.
    Directory(p.join(nested.directory, '.yagura')).createSync(recursive: true);
    final marker = File(p.join(nested.directory, '.yagura', 'deleting'))
      ..writeAsStringSync('');

    final restarted = await env.start();

    expect(orphan.existsSync(), isFalse);
    expect(marker.existsSync(), isFalse);
    expect(Directory(nested.directory).existsSync(), isTrue);
    expect(restarted.instances.list(), hasLength(1));
  });

  test('delete_with_files_snapshots_first', () async {
    final env = TestEnv();
    env.installValheim();
    var snapshotExistedBeforeRemoval = false;
    late String snapshotDirectory;
    final daemon = await env.start(
      realSnapshots: true,
      removeDirectory: (directory) async {
        // The snapshot is complete on disk before the directory goes.
        final snapshots = Directory(p.join(env.data, 'snapshots'));
        snapshotDirectory = snapshots
            .listSync(recursive: true)
            .whereType<File>()
            .singleWhere((f) => p.basename(f.path) == 'world.db')
            .path;
        snapshotExistedBeforeRemoval = File(snapshotDirectory).existsSync();
        Directory(directory).deleteSync(recursive: true);
      },
    );
    final instance = await createInstalled(daemon, name: 'Friends');
    writeSave(instance.directory);

    final op = daemon.instances.delete(
      instance.id,
      deleteFiles: true,
      confirmName: 'Friends',
    );
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    final orphan = daemon.instances.listOrphanSnapshots().single;
    expect(orphan.reason, 'pre_delete');
    // The result names the snapshot.
    expect(done.resultReason, contains(orphan.id));
    expect(done.resultMessage, contains(orphan.id));
    expect(snapshotExistedBeforeRemoval, isTrue);
    expect(File(snapshotDirectory).readAsStringSync(), 'world');
    expect(Directory(instance.directory).existsSync(), isFalse);

    // WatchOperation still returns that result once the instance is gone.
    final events = await daemon.operations.watch(op.id).toList();
    final finished = events.last as FinishedEvent;
    expect(finished.operation.resultMessage, contains(orphan.id));
    final steps = events.whereType<StepStartedEvent>().map((e) => e.step);
    expect(steps, ['snapshot', 'mark_deleting', 'remove_rows', 'remove_files']);
  });
}
