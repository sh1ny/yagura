import 'dart:async';

import 'package:test/test.dart';
import 'package:yagurad/src/content/content.dart';

import '../fixtures/fake_workshop_api.dart';
import '../support/daemon_support.dart';

void main() {
  late FakeWorkshopApi api;
  setUp(() async {
    api = await FakeWorkshopApi.start();
    addTearDown(api.close);
  });

  WorkshopClient client({
    Duration minInterval = Duration.zero,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final c = WorkshopClient(
      endpoint: api.endpoint,
      minInterval: minInterval,
      requestTimeout: timeout,
    );
    addTearDown(c.close);
    return c;
  }

  test('the_limits_default_to_the_design_values', () {
    final c = WorkshopClient(endpoint: api.endpoint);
    expect(c.batchSize, 100);
    expect(c.minInterval, const Duration(seconds: 1));
    expect(c.requestTimeout, const Duration(seconds: 15));
    expect(
      WorkshopClient.defaultEndpoint.toString(),
      'https://api.steampowered.com/ISteamRemoteStorage/'
      'GetPublishedFileDetails/v1/',
    );
  });

  test('details_carry_the_title_size_and_time_updated', () async {
    api.add(
      FakeWorkshopItem(
        '10',
        title: 'Ten',
        fileSize: 4096,
        timeUpdated: 1700000500,
      ),
    );

    final got = await client().details(['10']);

    final item = got['10']!;
    expect(item.available, isTrue);
    expect(item.title, 'Ten');
    expect(item.sizeBytes, 4096);
    expect(item.timeUpdated, 1700000500);
    expect(item.version, '1700000500');
    expect(api.requests.single.ids, ['10']);
    expect(api.requests.single.itemCount, 1);
  });

  test('missing_denied_and_private_items_are_not_available', () async {
    api
      ..add(FakeWorkshopItem('20', result: 15))
      ..add(FakeWorkshopItem('21', visibility: 2))
      ..add(FakeWorkshopItem('22', visibility: 0));

    final got = await client().details(['19', '20', '21', '22']);

    expect(got.keys, ['19', '20', '21', '22']);
    expect(got['19']!.available, isFalse, reason: 'result 9, not found');
    expect(got['20']!.available, isFalse, reason: 'result 15, access denied');
    expect(got['21']!.available, isFalse, reason: 'private');
    expect(got['22']!.available, isTrue);
  });

  test('items_go_in_batches_of_100', () async {
    final ids = [for (var i = 1; i <= 250; i++) '$i'];

    final got = await client().details(ids);

    expect(got, hasLength(250));
    expect([for (final r in api.requests) r.ids.length], [100, 100, 50]);
    expect([for (final r in api.requests) r.itemCount], [100, 100, 50]);
  });

  test('a_duplicate_id_is_asked_once', () async {
    await client().details(['5', '5', '6']);
    expect(api.requests.single.ids, ['5', '6']);
  });

  test('requests_are_paced_one_per_interval', () async {
    final c = client(minInterval: const Duration(milliseconds: 300));

    await c.details([for (var i = 1; i <= 250; i++) '$i']);

    expect(api.requests, hasLength(3));
    for (final gap in api.gaps) {
      expect(gap, greaterThanOrEqualTo(const Duration(milliseconds: 270)));
    }
  });

  test('callers_share_one_pace', () async {
    final c = client(minInterval: const Duration(milliseconds: 300));

    await Future.wait([
      c.details(['1']),
      c.details(['2']),
      c.details(['3']),
    ]);

    expect(api.requests, hasLength(3));
    for (final gap in api.gaps) {
      expect(gap, greaterThanOrEqualTo(const Duration(milliseconds: 270)));
    }
  });

  test('a_request_that_gets_no_answer_times_out', () async {
    api.hang = true;
    final c = client(timeout: const Duration(milliseconds: 300));

    final started = DateTime.now();
    await expectLater(
      c.details(['1']),
      failsWith('workshop_metadata_failed', messageHas: ['timed out']),
    );
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 5)),
    );
  });

  test('an_http_error_fails_the_lookup', () async {
    api.failWith.add(503);
    await expectLater(
      client().details(['1']),
      failsWith('workshop_metadata_failed', messageHas: ['503']),
    );
  });

  test('a_failed_lookup_can_be_retried', () async {
    api
      ..failWith.add(500)
      ..add(FakeWorkshopItem('1', title: 'One'));
    final c = client();
    await expectLater(c.details(['1']), throwsA(isA<Object>()));
    expect((await c.details(['1']))['1']!.title, 'One');
  });
}
