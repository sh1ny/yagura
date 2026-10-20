import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../fixtures/fake_workshop_api.dart';
import '../support/content_support.dart';

SteamAccountUse _account(String id) =>
    SteamAccountUse(id, 'srvadmin', () => null);

void main() {
  test('workshop_item_downloaded', () async {
    final rig = await ContentRig.start();
    final account = rig.installAccount('acct_0123456789ab');
    rig.item(
      cfMod,
      title: 'Community Framework',
      size: 4096,
      updated: 1700000123,
    );

    final op = rig.acquire(
      'inst-a',
      [cfMod],
      account: _account(account),
      requireAll: true,
    );
    expect((await rig.finished(op)).status, OperationStatus.succeeded);

    final got = rig.results[op.id]![cfMod];
    expect(got.ok, isTrue);
    expect(got.version, '1700000123', reason: 'the version is time_updated');
    expect(got.title, 'Community Framework', reason: 'the title is returned');
    expect(got.sizeBytes, greaterThan(0));
    final published = p.join(
      rig.data.contentPath,
      'steam_workshop',
      dayzWorkshopApp,
      cfMod,
      '1700000123',
    );
    expect(got.path, published);
    expect(File(p.join(published, 'meta.cpp')).existsSync(), isTrue);
    expect(
      File(p.join(published, 'keys', '$cfMod.bikey')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(published, 'addons', '$cfMod.pbo')).existsSync(),
      isTrue,
    );
    expect(rig.rows(), ['$cfMod/1700000123']);
    expect(rig.stagingLeftovers(), isEmpty);

    // Metadata first, then one run with the account's login in the account's
    // own installation; SteamCMD's tree stays as the download cache.
    expect(rig.api.requests.first.ids, [cfMod]);
    final run = rig.workshopRuns().single;
    final args = (run['args']! as List).cast<String>();
    expect(args, containsAllInOrder(['+login', 'srvadmin']));
    expect(
      args,
      containsAllInOrder(['+workshop_download_item', dayzWorkshopApp, cfMod]),
    );
    expect(p.basename(run['cwd']! as String), account);
    expect(
      File(
        p.join(
          rig.steam.root,
          account,
          'steamapps',
          'workshop',
          'content',
          dayzWorkshopApp,
          cfMod,
          'meta.cpp',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('item_removed_from_the_workshop', () async {
    final rig = await ContentRig.start();
    // 111 does not exist, 222 is private, 333 is fine.
    rig.api.add(FakeWorkshopItem('222', result: 15, visibility: 2));
    rig.item('333', title: 'Fine');

    final op = rig.acquire('inst-a', ['111', '222', '333'], requireAll: true);
    final done = await rig.finished(op);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'workshop_item_unavailable');
    expect(done.resultMessage, allOf(contains('111'), contains('222')));
    final result = rig.results[op.id]!;
    expect(
      [for (final f in result.failures) f.item],
      ['111', '222'],
      reason: 'the unavailable items are marked, in request order',
    );
    for (final failure in result.failures) {
      expect(failure.error!.reason, 'workshop_item_unavailable');
    }
    expect(result['333'].ok, isTrue, reason: 'the other items go on');
    expect(rig.publishedVersions('333'), ['1700000000']);
    final args = (rig.workshopRuns().single['args']! as List).cast<String>();
    expect(args, contains('333'));
    expect(args, isNot(contains('111')));
    expect(args, isNot(contains('222')));
  });

  test('a_private_item_is_unavailable_even_when_the_api_answers', () async {
    final rig = await ContentRig.start();
    rig.item('444').visibility = 2;

    final op = rig.acquire('inst-a', ['444']);
    await rig.finished(op);

    expect(
      rig.results[op.id]!['444'].error!.reason,
      'workshop_item_unavailable',
    );
    expect(rig.workshopRuns(), isEmpty);
  });

  test('anonymous_download_uses_the_anonymous_installation', () async {
    final rig = await ContentRig.start();
    rig.item(cfMod);

    await rig.finished(rig.acquire('inst-a', [cfMod], requireAll: true));

    final run = rig.workshopRuns().single;
    expect(p.basename(run['cwd']! as String), 'anonymous');
    expect(run['login'], 'anonymous');
  });

  test('the_version_is_read_again_after_the_download', () async {
    final rig = await ContentRig.start();
    final item = rig.item(cfMod, updated: 1700000000);
    // The second request is the re-read after the first run.
    rig.api.onRequest = (request) {
      if (rig.api.requests.length == 2) item.timeUpdated = 1700000900;
    };

    final op = rig.acquire('inst-a', [cfMod], requireAll: true);
    expect((await rig.finished(op)).status, OperationStatus.succeeded);

    expect(rig.workshopRuns(), hasLength(2), reason: 'downloaded once more');
    expect(rig.results[op.id]![cfMod].version, '1700000900');
    expect(rig.publishedVersions(cfMod), ['1700000900']);
    expect(rig.rows(), ['$cfMod/1700000900']);
  });

  test('an_item_that_changes_twice_fails_as_changing', () async {
    final rig = await ContentRig.start();
    final item = rig.item(cfMod, updated: 1700000000);
    rig.api.onRequest = (request) {
      // Requests: 1 before the run, 2 and 3 after the two runs.
      final n = rig.api.requests.length;
      if (n == 2) item.timeUpdated = 1700000900;
      if (n == 3) item.timeUpdated = 1700001800;
    };

    final op = rig.acquire('inst-a', [cfMod], requireAll: true);
    final done = await rig.finished(op);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'workshop_item_changing');
    expect(done.resultMessage, contains(cfMod));
    expect(rig.workshopRuns(), hasLength(2));
    expect(rig.publishedVersions(cfMod), isEmpty);
    expect(rig.rows(), isEmpty);
    expect(rig.stagingLeftovers(), isEmpty);
  });

  test('one_failed_item_does_not_fail_the_others', () async {
    final rig = await ContentRig.start(
      fakeEnvironment: {
        'FAKE_STEAMCMD_ITEM_555': 'failure',
        'FAKE_STEAMCMD_ITEM_666': 'not_found',
      },
    );
    for (final id in ['555', '666', '777']) {
      rig.item(id);
    }

    final op = rig.acquire('inst-a', ['555', '666', '777']);
    await rig.finished(op);

    final result = rig.results[op.id]!;
    expect(result['555'].error!.reason, 'steam_unknown_error');
    expect(result['555'].error!.message, contains('555'));
    expect(
      result['666'].error!.reason,
      'workshop_item_unavailable',
      reason: 'SteamCMD found nothing although the API listed the item',
    );
    expect(result['777'].ok, isTrue);
    expect(rig.rows(), ['777/1700000000']);
  });

  test('a_link_in_the_download_is_refused_at_publish', () async {
    final outside = Directory(p.join(Directory.systemTemp.path, 'ws_out'))
      ..createSync(recursive: true);
    addTearDown(() => outside.deleteSync(recursive: true));
    File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
    final rig = await ContentRig.start(
      fakeEnvironment: {'FAKE_STEAMCMD_ITEM_${cfMod}_JUNCTION': outside.path},
    );
    rig.item(cfMod);

    final op = rig.acquire('inst-a', [cfMod]);
    await rig.finished(op);

    expect(rig.results[op.id]![cfMod].error!.reason, 'sandbox_violation');
    expect(rig.publishedVersions(cfMod), isEmpty);
    expect(rig.rows(), isEmpty);
    expect(rig.stagingLeftovers(), isEmpty);
    expect(
      File(p.join(outside.path, 'secret.txt')).existsSync(),
      isTrue,
      reason: 'nothing was followed or removed',
    );
  });

  group('workshop output patterns', () {
    final patterns = SteamPatterns.embedded();

    test('start_success_and_failure_lines', () {
      expect(
        patterns.workshopLine('Downloading item 123 ...'),
        isA<WorkshopStarted>().having((l) => l.item, 'item', '123'),
      );
      expect(
        patterns.workshopLine(
          'Success. Downloaded item 123 to "C:\\x" (1024 bytes)',
        ),
        isA<WorkshopDownloaded>().having((l) => l.item, 'item', '123'),
      );
      expect(
        patterns.workshopLine(
          'ERROR! Download item 9 failed (File Not Found).',
        ),
        isA<WorkshopFailed>()
            .having((l) => l.item, 'item', '9')
            .having((l) => l.reason, 'reason', 'workshop_item_unavailable'),
      );
      expect(
        patterns.workshopLine('ERROR! Download item 9 failed (Timeout).'),
        isA<WorkshopFailed>().having(
          (l) => l.reason,
          'reason',
          'steam_unknown_error',
        ),
      );
      expect(patterns.workshopLine('Loading Steam API...OK'), isNull);
    });
  });
}
