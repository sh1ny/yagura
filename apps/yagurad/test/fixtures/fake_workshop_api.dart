// A stand-in for the Steam Web API's `ISteamRemoteStorage/GetPublishedFileDetails/v1`
// (POST, form-encoded `itemcount` and `publishedfileids[N]`, no key needed).
//
// Request shape: https://partner.steamgames.com/doc/webapi/ISteamRemoteStorage
// (fetched 2026-10-20: `itemcount` uint32, `publishedfileids[0..]` uint64).
// Response shape, as Valve returns it: `{"response":{"result":1,
// "resultcount":N,"publishedfiledetails":[{...}]}}` with `publishedfileid` and
// `file_size` as strings, `time_updated` as a number, `result` per item
// (1 = OK, 9 = file not found; a missing item is just
// `{"publishedfileid":"…","result":9}`). The per-item field list is modelled
// from real responses, not from the Valve page, which documents only the
// request.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One workshop item the fake knows.
class FakeWorkshopItem {
  FakeWorkshopItem(
    this.id, {
    this.title = 'Item',
    this.fileSize = 1024,
    this.timeUpdated = 1700000000,
    this.result = 1,
    this.visibility = 0,
    this.consumerAppId = 107410,
  });

  final String id;
  String title;
  int fileSize;

  /// Unix seconds; change it between calls to model an update mid-download.
  int timeUpdated;

  /// Per-item `result`: 1 found, 9 not found, 15 access denied.
  int result;

  /// 0 public, 1 friends only, 2 private, 3 unlisted.
  int visibility;
  int consumerAppId;

  Map<String, Object?> toJson() {
    if (result != 1) return {'publishedfileid': id, 'result': result};
    return {
      'publishedfileid': id,
      'result': 1,
      'creator': '76561198000000000',
      'creator_app_id': consumerAppId,
      'consumer_app_id': consumerAppId,
      'filename': '',
      'file_size': '$fileSize',
      'file_url': '',
      'hcontent_file': '0',
      'preview_url': '',
      'hcontent_preview': '0',
      'title': title,
      'description': '',
      'time_created': timeUpdated - 1000,
      'time_updated': timeUpdated,
      'visibility': visibility,
      'banned': 0,
      'ban_reason': '',
      'subscriptions': 1,
      'favorited': 0,
      'lifetime_subscriptions': 1,
      'lifetime_favorited': 0,
      'views': 1,
      'tags': <Object?>[],
    };
  }
}

/// One request the fake received.
class FakeWorkshopRequest {
  FakeWorkshopRequest(this.at, this.ids, this.itemCount);

  final DateTime at;

  /// The `publishedfileids[N]` values in order.
  final List<String> ids;

  /// The `itemcount` field as sent (null if absent).
  final int? itemCount;
}

class FakeWorkshopApi {
  FakeWorkshopApi._(this._server) {
    _server.listen(_handle);
  }

  /// Binds to loopback on an ephemeral port.
  static Future<FakeWorkshopApi> start() async =>
      FakeWorkshopApi._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final items = <String, FakeWorkshopItem>{};
  final requests = <FakeWorkshopRequest>[];

  /// Pause before every response.
  Duration delay = Duration.zero;

  /// The next requests answer with these HTTP statuses (consumed in order).
  final failWith = <int>[];

  /// Never answer (until [close]): models a request that times out.
  bool hang = false;

  /// Called for every request before it is answered, e.g. to bump a
  /// `timeUpdated` between calls.
  void Function(FakeWorkshopRequest request)? onRequest;

  /// Where requests go, e.g. `Uri.parse('$baseUri/ISteamRemoteStorage/…')`.
  Uri get baseUri =>
      Uri(scheme: 'http', host: _server.address.address, port: _server.port);

  /// The full endpoint.
  Uri get endpoint =>
      baseUri.replace(path: '/ISteamRemoteStorage/GetPublishedFileDetails/v1/');

  FakeWorkshopItem add(FakeWorkshopItem item) => items[item.id] = item;

  /// Gaps between consecutive request arrivals.
  List<Duration> get gaps => [
    for (var i = 1; i < requests.length; i++)
      requests[i].at.difference(requests[i - 1].at),
  ];

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path.endsWith('/')
        ? request.uri.path
        : '${request.uri.path}/';
    if (path != '/ISteamRemoteStorage/GetPublishedFileDetails/v1/') {
      response.statusCode = HttpStatus.notFound;
      return _finish(response);
    }
    if (request.method != 'POST') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return _finish(response);
    }
    final body = await utf8.decoder.bind(request).join();
    final form = Uri.splitQueryString(body);
    final ids = <String>[];
    for (var i = 0; form.containsKey('publishedfileids[$i]'); i++) {
      ids.add(form['publishedfileids[$i]']!);
    }
    final record = FakeWorkshopRequest(
      DateTime.now(),
      ids,
      int.tryParse(form['itemcount'] ?? ''),
    );
    requests.add(record);
    onRequest?.call(record);
    if (hang) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith.isNotEmpty) {
      response.statusCode = failWith.removeAt(0);
      return _finish(response);
    }
    final details = [
      for (final id in ids)
        (items[id] ?? FakeWorkshopItem(id, result: 9)).toJson(),
    ];
    response.headers.contentType = ContentType.json;
    response.write(
      jsonEncode({
        'response': {
          'result': 1,
          'resultcount': details.length,
          'publishedfiledetails': details,
        },
      }),
    );
    return _finish(response);
  }

  Future<void> _finish(HttpResponse response) async {
    try {
      await response.close();
    } on Object {
      // The client went away.
    }
  }
}
