import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/files.dart';
import '../host/database.dart';

/// One published version in the content store.
class ContentVersion {
  const ContentVersion({
    required this.source,
    required this.app,
    required this.item,
    required this.version,
    required this.sizeBytes,
    required this.publishedAt,
    required this.path,
    this.unreferencedSince,
  });

  final String source;
  final String app;
  final String item;
  final String version;
  final int sizeBytes;
  final DateTime publishedAt;
  final String path;

  /// When collection first saw no instance use the version; null while one
  /// does.
  final DateTime? unreferencedSince;
}

/// The content store on disk and in `content_versions` (design D6):
/// `content/<source>/<app>/<item>/<version>/`, immutable once published. A
/// version is copied into `content/.staging/<run-id>/` first and renamed into
/// place, so a directory in the store is always whole.
class ContentStore {
  ContentStore({
    required this.database,
    required this.contentPath,
    DateTime Function()? clock,
    this.retention = const Duration(days: 7),
    this.collectionInterval = const Duration(days: 1),
    void Function(String message)? log,
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? ((_) {});

  static const workshopSource = 'steam_workshop';

  final YaguraDatabase database;
  final String contentPath;

  /// How long a version stays after nothing uses it.
  final Duration retention;

  /// How often collection runs after [startup].
  final Duration collectionInterval;

  final DateTime Function() _clock;
  final void Function(String message) _log;
  Timer? _timer;

  String get _staging => p.join(contentPath, '.staging');

  /// The directory of a version, published or not.
  String pathOf(String source, String app, String item, String version) =>
      p.join(contentPath, source, app, item, version);

  /// The published version, or null.
  ContentVersion? find(String source, String app, String item, String version) {
    final rows = database.sqlite.select(
      'SELECT * FROM content_versions WHERE source = ? AND app = ? AND '
      'item = ? AND version = ?',
      [source, app, item, version],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Every published version, by item and version.
  List<ContentVersion> versions() => [
    for (final row in database.sqlite.select(
      'SELECT * FROM content_versions ORDER BY source, app, item, version',
    ))
      _fromRow(row),
  ];

  /// The staging directory of the run [runId].
  String stagingDirectory(String runId) => p.join(_staging, runId);

  ContentVersion _fromRow(Map<String, Object?> row) {
    final source = row['source']! as String;
    final app = row['app']! as String;
    final item = row['item']! as String;
    final version = row['version']! as String;
    final since = row['unreferenced_since'] as int?;
    return ContentVersion(
      source: source,
      app: app,
      item: item,
      version: version,
      sizeBytes: row['size_bytes']! as int,
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
        row['published_at']! as int,
        isUtc: true,
      ),
      path: pathOf(source, app, item, version),
      unreferencedSince: since == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(since, isUtc: true),
    );
  }

  /// Publishes the files at [relative] below [fromRoot] as the version
  /// [version] of [item]: copied without following links into the run's
  /// staging directory, then renamed into place. A link in the source fails
  /// `sandbox_violation` and publishes nothing. A published version is never
  /// replaced: a directory that has no row (a crash after the rename) is
  /// adopted as it is.
  Future<ContentVersion> publish({
    required String source,
    required String app,
    required String item,
    required String version,
    required String fromRoot,
    required String relative,
    required String runId,
  }) async {
    final existing = find(source, app, item, version);
    if (existing != null) return existing;
    final target = pathOf(source, app, item, version);
    final staging = stagingDirectory(runId);
    final copy = p.join(staging, item);
    try {
      var size = 0;
      if (Directory(target).existsSync()) {
        size = _sizeOf(target);
      } else {
        final copied = await Isolate.run(() => _copy(fromRoot, relative, copy));
        if (copied.reason != null) {
          throw YaguraException(
            copied.reason!,
            copied.message!,
            details: {'item': item},
          );
        }
        size = copied.bytes;
        Directory(p.dirname(target)).createSync(recursive: true);
        Directory(copy).renameSync(target);
      }
      final now = _clock().millisecondsSinceEpoch;
      database.sqlite.execute(
        'INSERT OR IGNORE INTO content_versions '
        '(source, app, item, version, size_bytes, published_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [source, app, item, version, size, now],
      );
      return find(source, app, item, version)!;
    } finally {
      _deleteQuietly(staging);
    }
  }

  static ({int bytes, String? reason, String? message}) _copy(
    String fromRoot,
    String relative,
    String destination,
  ) {
    try {
      final bytes = ConfinedFs(fromRoot).copyOut(relative, destination);
      return (bytes: bytes, reason: null, message: null);
    } on YaguraException catch (e) {
      return (bytes: 0, reason: e.reason, message: e.message);
    }
  }

  static int _sizeOf(String directory) {
    var total = 0;
    for (final e in Directory(
      directory,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }

  void _deleteQuietly(String directory) {
    try {
      if (Directory(directory).existsSync()) {
        ConfinedFs(directory).deleteTree('');
      }
    } on Object catch (e) {
      _log('could not delete $directory: $e');
    }
  }

  /// Daemon startup: empties the staging area (a copy a killed daemon left),
  /// collects, and schedules collection every [collectionInterval].
  void startup() {
    final staging = Directory(_staging)..createSync(recursive: true);
    for (final entry in staging.listSync(followLinks: false)) {
      try {
        if (entry is Directory) {
          ConfinedFs(entry.path).deleteTree('');
        } else {
          entry.deleteSync();
        }
      } on Object catch (e) {
        _log('could not delete ${entry.path}: $e');
      }
    }
    _runCollection();
    _timer?.cancel();
    _timer = Timer.periodic(collectionInterval, (_) => _runCollection());
  }

  void _runCollection() {
    try {
      collect();
    } on Object catch (e) {
      _log('content collection failed: $e');
    }
  }

  /// Starts or clears the unreferenced clock of every version from the mods
  /// instances stage or want, and deletes what has been unreferenced for more
  /// than [retention]. Returns the number of versions deleted. A version that
  /// cannot be deleted stays for the next run.
  int collect() {
    final used = <String>{
      for (final row in database.sqlite.select(
        'SELECT source, item_id, staged_version, desired_version '
        'FROM instance_mods',
      ))
        for (final v in [row['staged_version'], row['desired_version']])
          if (v is String && v.isNotEmpty)
            '${row['source']}|${row['item_id']}|$v',
    };
    final now = _clock();
    var removed = 0;
    for (final version in versions()) {
      final key = '${version.source}|${version.item}|${version.version}';
      final key2 = (version.source, version.app, version.item, version.version);
      if (used.contains(key)) {
        if (version.unreferencedSince != null) {
          _setSince(key2, null);
        }
        continue;
      }
      final since = version.unreferencedSince;
      if (since == null) {
        _setSince(key2, now);
      } else if (now.difference(since) > retention) {
        if (_remove(version)) removed++;
      }
    }
    return removed;
  }

  void _setSince((String, String, String, String) key, DateTime? since) {
    database.sqlite.execute(
      'UPDATE content_versions SET unreferenced_since = ? WHERE source = ? '
      'AND app = ? AND item = ? AND version = ?',
      [since?.millisecondsSinceEpoch, key.$1, key.$2, key.$3, key.$4],
    );
  }

  bool _remove(ContentVersion version) {
    try {
      if (Directory(version.path).existsSync()) {
        ConfinedFs(version.path).deleteTree('');
      }
    } on Object catch (e) {
      _log('could not delete ${version.path}: $e');
      return false;
    }
    database.sqlite.execute(
      'DELETE FROM content_versions WHERE source = ? AND app = ? AND '
      'item = ? AND version = ?',
      [version.source, version.app, version.item, version.version],
    );
    // The item and app directories go when they are empty.
    for (final parent in [
      p.dirname(version.path),
      p.dirname(p.dirname(version.path)),
    ]) {
      try {
        Directory(parent).deleteSync();
      } on Object {
        // Not empty: other versions live there.
      }
    }
    return true;
  }

  void close() {
    _timer?.cancel();
    _timer = null;
  }
}
