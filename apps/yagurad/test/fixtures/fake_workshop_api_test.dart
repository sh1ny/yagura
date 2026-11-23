import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'fake_workshop_api.dart';

Future<(int, Map<String, Object?>?)> _post(
  FakeWorkshopApi api,
  List<String> ids, {
  Duration? timeout,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(api.endpoint);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    request.write(
      [
        'itemcount=${ids.length}',
        for (var i = 0; i < ids.length; i++) 'publishedfileids[$i]=${ids[i]}',
      ].join('&'),
    );
    var response = request.close();
    if (timeout != null) response = response.timeout(timeout);
    final r = await response;
    final text = await utf8.decoder.bind(r).join();
    return (
      r.statusCode,
      text.isEmpty ? null : jsonDecode(text) as Map<String, Object?>,
    );
  } finally {
    client.close(force: true);
  }
}

List<Map<String, Object?>> _details((int, Map<String, Object?>?) r) =>
    ((r.$2!['response']! as Map)['publishedfiledetails']! as List)
        .cast<Map<String, Object?>>();

void main() {
  late FakeWorkshopApi api;
  setUp(() async {
    api = await FakeWorkshopApi.start();
    addTearDown(api.close);
  });

  test('binds to loopback and answers with the real response shape', () async {
    expect(api.baseUri.host, '127.0.0.1');
    api.add(
      FakeWorkshopItem(
        '10',
        title: 'Ten',
        fileSize: 99,
        timeUpdated: 1700000500,
      ),
    );
    final r = await _post(api, ['10']);
    expect(r.$1, 200);
    final response = r.$2!['response']! as Map<String, Object?>;
    expect(response['result'], 1);
    expect(response['resultcount'], 1);
    final d = _details(r).single;
    expect(d['publishedfileid'], '10');
    expect(d['result'], 1);
    expect(d['title'], 'Ten');
    expect(d['file_size'], '99');
    expect(d['time_updated'], 1700000500);
    expect(d['visibility'], 0);
  });

  test('missing and private items carry per-item results', () async {
    api.add(FakeWorkshopItem('1', result: 15));
    final list = _details(await _post(api, ['1', '404']));
    expect(list[0], {'publishedfileid': '1', 'result': 15});
    expect(list[1], {'publishedfileid': '404', 'result': 9});
  });

  test('time_updated can change between calls', () async {
    final item = api.add(FakeWorkshopItem('5'));
    final first = _details(await _post(api, ['5'])).single;
    item.timeUpdated += 60;
    final second = _details(await _post(api, ['5'])).single;
    expect(
      (second['time_updated']! as int) - (first['time_updated']! as int),
      60,
    );
  });

  test('logs requests for batching and pacing assertions', () async {
    await _post(api, [for (var i = 0; i < 100; i++) '$i']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _post(api, ['a', 'b']);
    expect(api.requests, hasLength(2));
    expect(api.requests[0].ids, hasLength(100));
    expect(api.requests[0].itemCount, 100);
    expect(api.requests[1].ids, ['a', 'b']);
    expect(
      api.gaps.single,
      greaterThanOrEqualTo(const Duration(milliseconds: 40)),
    );
  });

  test('failures, delays and hangs', () async {
    api.failWith.add(500);
    expect((await _post(api, ['1'])).$1, 500);
    api.delay = const Duration(milliseconds: 200);
    final sw = Stopwatch()..start();
    expect((await _post(api, ['1'])).$1, 200);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(180));
    api
      ..delay = Duration.zero
      ..hang = true;
    await expectLater(
      _post(api, ['1'], timeout: const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
    expect(api.requests, hasLength(3));
  });

  test('rejects other paths and methods', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final get = await (await client.getUrl(api.endpoint)).close();
    expect(get.statusCode, HttpStatus.methodNotAllowed);
    final other = await (await client.postUrl(api.baseUri.replace(path: '/x')))
        .close();
    expect(other.statusCode, HttpStatus.notFound);
    expect(api.requests, isEmpty);
  });
}
