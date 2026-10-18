import '../host/database.dart';

/// What the Steam service remembers between runs: which SteamCMD
/// installations are ready and the last known size of each app.
///
/// It lives in the daemon's database, not in files under `<data>/steamcmd`,
/// so the account that runs the game servers cannot write it (ADR 0013).
abstract interface class SteamState {
  /// Whether [installation] was bootstrapped and self-updated.
  bool isReady(String installation);

  /// Marks [installation] ready.
  void markReady(String installation);

  /// Forgets that [installation] was ready.
  void markNotReady(String installation);

  /// Last known size of [appId] in bytes, or null when never recorded.
  int? lastKnownSize(int appId);

  /// Records the size of [appId] in bytes.
  void recordSize(int appId, int bytes);
}

/// A [SteamState] held in memory; the default until the daemon attaches its
/// database, and what tests of the service use.
class MemorySteamState implements SteamState {
  final _ready = <String>{};
  final _sizes = <int, int>{};

  @override
  bool isReady(String installation) => _ready.contains(installation);

  @override
  void markReady(String installation) => _ready.add(installation);

  @override
  void markNotReady(String installation) => _ready.remove(installation);

  @override
  int? lastKnownSize(int appId) => _sizes[appId];

  @override
  void recordSize(int appId, int bytes) => _sizes[appId] = bytes;
}

/// A [SteamState] in the `steamcmd_installations` and `steam_app_sizes`
/// tables.
class DatabaseSteamState implements SteamState {
  DatabaseSteamState(this._database, [DateTime Function()? clock])
    : _clock = clock ?? DateTime.now;

  final YaguraDatabase _database;
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  @override
  bool isReady(String installation) => _database.sqlite.select(
    'SELECT 1 FROM steamcmd_installations WHERE installation = ?',
    [installation],
  ).isNotEmpty;

  @override
  void markReady(String installation) => _database.sqlite.execute(
    'INSERT OR REPLACE INTO steamcmd_installations (installation, ready_at) '
    'VALUES (?, ?)',
    [installation, _now],
  );

  @override
  void markNotReady(String installation) => _database.sqlite.execute(
    'DELETE FROM steamcmd_installations WHERE installation = ?',
    [installation],
  );

  @override
  int? lastKnownSize(int appId) {
    final rows = _database.sqlite.select(
      'SELECT bytes FROM steam_app_sizes WHERE app_id = ?',
      [appId],
    );
    return rows.isEmpty ? null : rows.first['bytes'] as int;
  }

  @override
  void recordSize(int appId, int bytes) => _database.sqlite.execute(
    'INSERT OR REPLACE INTO steam_app_sizes (app_id, bytes, recorded_at) '
    'VALUES (?, ?, ?)',
    [appId, bytes, _now],
  );
}
