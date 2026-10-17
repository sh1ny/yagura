import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';

void main() {
  late Directory temp;
  late String instanceDir;
  late DirectorySnapshotter snapshotter;
  var now = DateTime.utc(2030, 1, 1);

  SnapshotRequest request(String reason) => SnapshotRequest(
    instanceId: 'inst-1',
    instanceName: 'Friends',
    instanceDirectory: instanceDir,
    dataPaths: [p.join(instanceDir, 'save'), p.join(instanceDir, 'extra.cfg')],
    reason: reason,
  );

  setUp(() {
    now = DateTime.utc(2030, 1, 1);
    temp = Directory.systemTemp.createTempSync('yagurad_snap_');
    addTearDown(() => temp.deleteSync(recursive: true));
    instanceDir = p.join(temp.path, 'instance');
    Directory(p.join(instanceDir, 'save')).createSync(recursive: true);
    File(p.join(instanceDir, 'save', 'world.db')).writeAsStringSync('world');
    snapshotter = DirectorySnapshotter(
      root: p.join(temp.path, 'snapshots'),
      clock: () => now,
    );
  });

  test('keeps the last three snapshots, newest first', () async {
    final ids = <String>[];
    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(minutes: 1));
      ids.add(await snapshotter.take(request('pre_update')));
    }

    final listed = snapshotter.list('inst-1');

    expect(listed.map((s) => s.id), ids.reversed.take(3));
    expect(listed.first.sizeBytes, 'world'.length);
  });

  test('a snapshot with the same clock reading stays ordered', () async {
    final first = await snapshotter.take(request('pre_update'));
    final second = await snapshotter.take(request('pre_update'));

    expect(snapshotter.list('inst-1').map((s) => s.id), [second, first]);
  });

  test('restore removes a data path that the snapshot did not have', () async {
    final id = await snapshotter.take(request('pre_update'));
    // `extra.cfg` did not exist then; it appears later.
    final extra = File(p.join(instanceDir, 'extra.cfg'))
      ..writeAsStringSync('new');
    File(p.join(instanceDir, 'save', 'world.db')).writeAsStringSync('changed');

    await snapshotter.restore(
      RestoreRequest(
        instanceId: 'inst-1',
        instanceName: 'Friends',
        instanceDirectory: instanceDir,
        dataPaths: request('x').dataPaths,
        snapshotId: id,
      ),
      onStep: (_) {},
      checkCancelled: () {},
    );

    expect(extra.existsSync(), isFalse);
    expect(
      File(p.join(instanceDir, 'save', 'world.db')).readAsStringSync(),
      'world',
    );
    expect(snapshotter.interruptedRestores(), isEmpty);
  });

  test('a cancelled restore changes nothing and leaves no marker', () async {
    final id = await snapshotter.take(request('pre_update'));
    File(p.join(instanceDir, 'save', 'world.db')).writeAsStringSync('changed');
    var asked = 0;

    await expectLater(
      snapshotter.restore(
        RestoreRequest(
          instanceId: 'inst-1',
          instanceName: 'Friends',
          instanceDirectory: instanceDir,
          dataPaths: request('x').dataPaths,
          snapshotId: id,
        ),
        onStep: (_) {},
        checkCancelled: () {
          // Cancelled at the second check, after pre_restore, before replacing.
          if (++asked == 2) throw StateError('cancelled');
        },
      ),
      throwsStateError,
    );

    expect(
      File(p.join(instanceDir, 'save', 'world.db')).readAsStringSync(),
      'changed',
    );
    expect(snapshotter.interruptedRestores(), isEmpty);
    expect(snapshotter.list('inst-1').map((s) => s.reason), [
      'pre_restore',
      'pre_update',
    ]);
  });

  test('purge removes half-written snapshots at startup', () async {
    await snapshotter.take(request('pre_update'));
    final partial = Directory(
      p.join(temp.path, 'snapshots', 'inst-1', 'snap-x.partial'),
    )..createSync(recursive: true);

    await snapshotter.purgeExpired({'inst-1'});

    expect(partial.existsSync(), isFalse);
    expect(snapshotter.list('inst-1'), hasLength(1));
  });
}
