import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../errors.dart';
import '../operations/semaphore.dart';

/// What the Steam Web API says about one workshop item.
class WorkshopItemDetails {
  const WorkshopItemDetails({
    required this.id,
    required this.result,
    this.title = '',
    this.sizeBytes = 0,
    this.timeUpdated = 0,
    this.visibility = 0,
  });

  final String id;

  /// The per-item `result`: 1 found, 9 not found, 15 access denied.
  final int result;
  final String title;
  final int sizeBytes;

  /// Unix seconds; it names the version of the item (design D5).
  final int timeUpdated;

  /// 0 public, 1 friends only, 2 private, 3 unlisted.
  final int visibility;

  /// The item exists and is not private. A missing or private item is
  /// `unavailable` (steam-content, "Workshop downloads").
  bool get available => result == 1 && visibility != 2;

  /// The version of the item: its `time_updated`.
  String get version => '$timeUpdated';

  @override
  String toString() => 'WorkshopItemDetails($id, result $result)';
}

/// Reads workshop metadata from `ISteamRemoteStorage/GetPublishedFileDetails`
/// (design D5): POST, no key, [batchSize] items per request, one request per
/// [minInterval] for the whole client, and [requestTimeout] per request.
class WorkshopClient {
  WorkshopClient({
    required this.endpoint,
    this.requestTimeout = const Duration(seconds: 15),
    this.minInterval = defaultMinInterval,
    this.batchSize = 100,
  });

  /// At most one request per second per daemon.
  static const defaultMinInterval = Duration(seconds: 1);

  static final defaultEndpoint = Uri.parse(
    'https://api.steampowered.com/ISteamRemoteStorage/'
    'GetPublishedFileDetails/v1/',
  );

  /// A response larger than this is refused (100 items are far below it).
  static const maxResponseBytes = 8 * 1024 * 1024;

  /// The full URL; tests point it at a fake server.
  final Uri endpoint;
  final Duration requestTimeout;
  final Duration minInterval;
  final int batchSize;

  final _pace = Semaphore(1);
  final _open = <HttpClient>{};
  var _next = DateTime.fromMillisecondsSinceEpoch(0);
  var _closed = false;

  /// The details of every item of [ids] (duplicates asked once), in batches.
  /// An id the API does not list comes back with result 9. A failed request
  /// throws `workshop_metadata_failed`.
  Future<Map<String, WorkshopItemDetails>> details(Iterable<String> ids) async {
    final unique = <String>{...ids}.toList();
    final out = <String, WorkshopItemDetails>{};
    for (var i = 0; i < unique.length; i += batchSize) {
      final batch = unique.sublist(i, min(i + batchSize, unique.length));
      out.addAll(await _batch(batch));
    }
    return out;
  }

  Future<Map<String, WorkshopItemDetails>> _batch(List<String> batch) async {
    await _waitForTurn();
    final client = HttpClient()..connectionTimeout = requestTimeout;
    _open.add(client);
    try {
      return await _post(client, batch).timeout(requestTimeout);
    } on TimeoutException {
      throw YaguraException(
        'workshop_metadata_failed',
        'the Steam Web API did not answer within '
            '${requestTimeout.inMilliseconds / 1000} s (timed out)',
        details: {'items': batch.length},
      );
    } on YaguraException {
      rethrow;
    } on Object catch (e) {
      throw YaguraException(
        'workshop_metadata_failed',
        'the Steam Web API could not be read: $e',
        details: {'items': batch.length},
      );
    } finally {
      _open.remove(client);
      client.close(force: true);
    }
  }

  /// Waits until [minInterval] has passed since the previous request of any
  /// caller, and claims the next turn.
  Future<void> _waitForTurn() async {
    if (_closed) {
      throw YaguraException('internal_error', 'the workshop client is closed');
    }
    final release = await _pace.acquire();
    try {
      final wait = _next.difference(DateTime.now());
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _next = DateTime.now().add(minInterval);
    } finally {
      release();
    }
  }

  Future<Map<String, WorkshopItemDetails>> _post(
    HttpClient client,
    List<String> batch,
  ) async {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(
      [
        'itemcount=${batch.length}',
        for (var i = 0; i < batch.length; i++)
          '${Uri.encodeQueryComponent('publishedfileids[$i]')}='
              '${Uri.encodeQueryComponent(batch[i])}',
      ].join('&'),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw YaguraException(
        'workshop_metadata_failed',
        'the Steam Web API answered HTTP ${response.statusCode}',
        details: {'status': response.statusCode},
      );
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > maxResponseBytes) {
        throw YaguraException(
          'workshop_metadata_failed',
          'the Steam Web API answer is larger than $maxResponseBytes bytes',
        );
      }
    }
    return _parse(utf8.decode(bytes), batch);
  }

  Map<String, WorkshopItemDetails> _parse(String body, List<String> batch) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e) {
      throw YaguraException(
        'workshop_metadata_failed',
        'the Steam Web API answer is not JSON: ${e.message}',
      );
    }
    final list = switch (json) {
      {'response': {'publishedfiledetails': final List<Object?> list}} => list,
      _ => throw YaguraException(
        'workshop_metadata_failed',
        'the Steam Web API answer has no publishedfiledetails',
      ),
    };
    final found = <String, WorkshopItemDetails>{};
    for (final entry in list) {
      if (entry is! Map) continue;
      final id = '${entry['publishedfileid']}';
      found[id] = WorkshopItemDetails(
        id: id,
        result: _int(entry['result']),
        title: '${entry['title'] ?? ''}',
        sizeBytes: _int(entry['file_size']),
        timeUpdated: _int(entry['time_updated']),
        visibility: _int(entry['visibility']),
      );
    }
    return {
      for (final id in batch)
        id: found[id] ?? WorkshopItemDetails(id: id, result: 9),
    };
  }

  static int _int(Object? value) => switch (value) {
    final int n => n,
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  /// Refuses new requests and aborts the ones in flight.
  void close() {
    _closed = true;
    for (final client in _open.toList()) {
      client.close(force: true);
    }
  }
}
