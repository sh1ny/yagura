import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/data_directory.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/content_support.dart';
import '../support/daemon_support.dart';

/// Every file below [dir] with its bytes, by relative path.
Map<String, List<int>> _tree(String dir) => {
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File) p.relative(e.path, from: dir): e.readAsBytesSync(),
};

bool _alive(int pid) => Process.killPid(pid);

void main() {
  const day = Duration(days: 1);

  test('two_instances_share_one_download', () async {
    final rig = await ContentRig.start(
      fakeEnvironment: {
        'FAKE_STEAMCMD_DELAY_MS': '150',
        'FAKE_STEAMCMD_WORKSHOP_PROGRESS': '1',
      },
    );
    rig.item(cfMod);

    final a = rig.acquire('inst-a', [cfMod], requireAll: true);
    await eventually(
      () => rig.workshopRuns().isNotEmpty,
      reason: 'the download is running',
    );
    final b = rig.acquire('inst-b', [cfMod], requireAll: true);

    expect((await rig.finished(a)).status, OperationStatus.succeeded);
    expect((await rig.finished(b)).status, OperationStatus.succeeded);

    expect(rig.workshopRuns(), hasLength(1), reason: 'one download');
    expect(rig.results[a.id]![cfMod].version, '1700000000');
    expect(
      rig.results[b.id]![cfMod].version,
      rig.results[a.id]![cfMod].version,
      reason: 'both pin the same version',
    );
    expect(rig.results[b.id]![cfMod].path, rig.results[a.id]![cfMod].path);
    expect(rig.publishedVersions(cfMod), ['1700000000']);
    expect(rig.rows(), ['$cfMod/1700000000']);
    // The run's progress reached both waiting operations.
    for (final op in [a, b]) {
      final events = await rig.runner.watch(op.id).toList();
      expect(
        events.whereType<ProgressEvent>().map((e) => e.step),
        contains('download'),
        reason: 'operation ${op.id} saw the shared run',
      );
    }
  });

  test('update_while_another_instance_runs', () async {
    final rig = await ContentRig.start();
    final item = rig.item(cfMod, updated: 1700000000);
    final first = rig.acquire('inst-a', [cfMod], requireAll: true);
    await rig.finished(first);
    final v1 = rig.results[first.id]![cfMod].path;
    // Instance B runs on the old version.
    rig.reference('inst-b', cfMod, staged: '1700000000', desired: '1700000000');
    final before = _tree(v1);

    item.timeUpdated = 1700005000;
    final second = rig.acquire('inst-a', [cfMod], requireAll: true);
    expect((await rig.finished(second)).status, OperationStatus.succeeded);

    final v2 = rig.results[second.id]![cfMod];
    expect(v2.version, '1700005000');
    expect(rig.publishedVersions(cfMod), [
      '1700000000',
      '1700005000',
    ], reason: 'the new version is published next to the old one');
    expect(_tree(v1), before, reason: 'the old version is not touched');
    expect(_tree(v2.path), isNotEmpty);
    expect(rig.rows(), ['$cfMod/1700000000', '$cfMod/1700005000']);
    // The running instance keeps its version through collection.
    rig.clock.advance(day * 30);
    rig.store.collect();
    rig.clock.advance(day * 30);
    rig.store.collect();
    expect(Directory(v1).existsSync(), isTrue);
  });

  test('update_requested_for_a_running_instance', () async {
    final rig = await ContentRig.start();
    final item = rig.item(cfMod, updated: 1700000000);
    final first = rig.acquire('inst-a', [cfMod], requireAll: true);
    await rig.finished(first);
    final v1 = rig.results[first.id]![cfMod].path;
    rig.reference('inst-a', cfMod, staged: '1700000000', desired: '1700000000');

    // UpdateMods on the running instance: the new version is downloaded and
    // becomes desired; the staged one stays.
    item.timeUpdated = 1700005000;
    final update = rig.acquire('inst-a', [cfMod], requireAll: true);
    await rig.finished(update);
    final v2 = rig.results[update.id]![cfMod].path;
    rig.reference('inst-a', cfMod, staged: '1700000000', desired: '1700005000');

    rig.clock.advance(day * 30);
    rig.store.collect();
    rig.clock.advance(day * 30);
    rig.store.collect();
    expect(
      Directory(v1).existsSync(),
      isTrue,
      reason: 'the staged version is kept',
    );
    expect(Directory(v2).existsSync(), isTrue, reason: 'so is the desired one');

    // The restart re-links: only then does the old version age out.
    rig.reference('inst-a', cfMod, staged: '1700005000', desired: '1700005000');
    rig.store.collect();
    rig.clock.advance(day * 6);
    rig.store.collect();
    expect(Directory(v1).existsSync(), isTrue, reason: 'less than 7 days');
    rig.clock.advance(day * 2);
    rig.store.collect();
    expect(Directory(v1).existsSync(), isFalse);
    expect(Directory(v2).existsSync(), isTrue);
  });

  test('one_of_two_waiters_cancels', () async {
    final rig = await ContentRig.start(
      fakeEnvironment: {
        'FAKE_STEAMCMD_DELAY_MS': '200',
        'FAKE_STEAMCMD_WORKSHOP_PROGRESS': '1',
      },
    );
    rig.item(cfMod);
    final a = rig.acquire('inst-a', [cfMod], requireAll: true);
    final b = rig.acquire('inst-b', [cfMod], requireAll: true);
    await eventually(
      () => rig.workshopRuns().isNotEmpty && rig.api.requests.length >= 2,
      reason: 'both wait on the running download',
    );
    // Let b register on the key before a leaves.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    rig.runner.cancel(a.id);
    final cancelled = await rig.finished(a);

    expect(cancelled.status, OperationStatus.cancelled);
    expect(
      rig.runner.get(b.id)!.status.isTerminal,
      isFalse,
      reason: 'the cancelled operation ended at once, the download goes on',
    );
    expect((await rig.finished(b)).status, OperationStatus.succeeded);
    expect(rig.workshopRuns(), hasLength(1));
    expect(rig.results[b.id]![cfMod].ok, isTrue);
    expect(rig.publishedVersions(cfMod), ['1700000000']);
  });

  test('interrupted_download', () async {
    // The daemon died with a copy half done in the staging area.
    final env = TestEnv();
    final data = DataDirectory.prepare(env.data);
    final dead = Directory(p.join(data.contentStagingPath, 'run-dead', '111'))
      ..createSync(recursive: true);
    File(p.join(dead.path, 'addons.pbo')).writeAsBytesSync(List.filled(64, 1));
    File(p.join(data.contentStagingPath, 'stray.txt')).writeAsStringSync('x');

    await env.start();

    expect(
      Directory(data.contentStagingPath).existsSync(),
      isTrue,
      reason: 'the staging area itself is kept',
    );
    expect(
      Directory(data.contentStagingPath).listSync(),
      isEmpty,
      reason: 'the leftovers are deleted at startup',
    );
    expect(
      Directory(p.join(data.contentPath, 'steam_workshop')).existsSync(),
      isFalse,
      reason: 'no partial version directory was published',
    );
  });

  test('a_cancelled_download_publishes_nothing', () async {
    final rig = await ContentRig.start(
      fakeEnvironment: {'FAKE_STEAMCMD_ITEM_$cfMod': 'stall'},
    );
    rig.item(cfMod);
    final op = rig.acquire('inst-a', [cfMod]);
    await eventually(
      () => rig.workshopRuns().isNotEmpty,
      reason: 'SteamCMD started',
    );
    final pid = rig.workshopRuns().single['pid']! as int;
    expect(_alive(pid), isTrue);

    rig.runner.cancel(op.id);
    expect((await rig.finished(op)).status, OperationStatus.cancelled);

    await eventually(() => !_alive(pid), reason: 'the last waiter left');
    expect(rig.publishedVersions(cfMod), isEmpty);
    expect(rig.rows(), isEmpty);
    expect(rig.stagingLeftovers(), isEmpty);
  });

  test('removing_a_mod_from_one_instance', () async {
    final rig = await ContentRig.start();
    rig.item(cfMod);
    final op = rig.acquire('inst-a', [cfMod], requireAll: true);
    await rig.finished(op);
    final path = rig.results[op.id]![cfMod].path;
    rig.reference('inst-a', cfMod, staged: '1700000000', desired: '1700000000');
    rig.reference('inst-b', cfMod, staged: '1700000000', desired: '1700000000');
    final before = _tree(path);

    // inst-a removes the mod: its row goes, the content stays.
    rig.unreference('inst-a');
    rig.store.collect();
    rig.clock.advance(day * 30);
    rig.store.collect();

    expect(Directory(path).existsSync(), isTrue);
    expect(_tree(path), before, reason: 'inst-b still resolves its files');
    expect(rig.rows(), ['$cfMod/1700000000']);

    // Only when the last instance lets go does the clock start.
    rig.unreference('inst-b');
    rig.store.collect();
    rig.clock.advance(day * 8);
    rig.store.collect();
    expect(Directory(path).existsSync(), isFalse);
  });

  test('unreferenced_version_collected', () async {
    final rig = await ContentRig.start();
    rig.item('501');
    rig.item('502');
    final op = rig.acquire('inst-a', ['501', '502'], requireAll: true);
    await rig.finished(op);
    final gone = rig.results[op.id]!['501'].path;
    final kept = rig.results[op.id]!['502'].path;

    // Day 0: neither is referenced; the clock starts.
    rig.store.collect();
    expect(rig.store.versions().map((v) => v.unreferencedSince), [
      isNotNull,
      isNotNull,
    ]);
    // Day 3: 502 is used again, which clears its clock.
    rig.clock.advance(day * 3);
    rig.reference('inst-a', '502', staged: '1700000000', desired: '1700000000');
    rig.store.collect();
    expect(
      rig.store
          .find('steam_workshop', dayzWorkshopApp, '502', '1700000000')!
          .unreferencedSince,
      isNull,
    );
    // Day 6.9: less than 7 days since 501 was first seen unreferenced.
    rig.clock.advance(const Duration(days: 3, hours: 21));
    expect(rig.store.collect(), 0);
    expect(Directory(gone).existsSync(), isTrue);
    // Day 7.1: more than 7 days.
    rig.clock.advance(const Duration(hours: 5));
    expect(rig.store.collect(), 1);

    expect(Directory(gone).existsSync(), isFalse);
    expect(Directory(kept).existsSync(), isTrue);
    expect(rig.rows(), ['502/1700000000']);
  });

  test('not_enough_disk_for_a_mod', () async {
    // 4096 bytes reported: twice that is 8192, and 5000 are free.
    final rig = await ContentRig.start(freeBytes: 5000);
    rig.item(cfMod, size: 4096);

    final op = rig.acquire('inst-a', [cfMod]);
    await rig.finished(op);

    final failure = rig.results[op.id]![cfMod].error!;
    expect(failure.reason, 'insufficient_disk');
    expect(failure.message, allOf(contains(r'V:\'), contains('5000')));
    expect(failure.message, contains('8192'));
    expect(failure.details, {
      'volume': r'V:\',
      'freeBytes': 5000,
      'requiredBytes': 8192,
      'item': cfMod,
    });
    expect(
      rig.workshopRuns(),
      isEmpty,
      reason: 'checked before SteamCMD downloads',
    );
    expect(rig.publishedVersions(cfMod), isEmpty);
    expect(rig.stagingLeftovers(), isEmpty);
  });
}
