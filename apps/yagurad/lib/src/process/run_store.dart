import 'dart:convert';

import '../host/database.dart';
import 'process_host.dart';

enum RunState {
  /// Recorded before `launch` is spawned.
  pending,

  /// Relay and server verified.
  running,

  /// The server's exit was observed, or the run was found lost.
  ended;

  static RunState fromWire(String name) =>
      values.firstWhere((s) => s.name == name);
}

/// One server run of an instance (design D2).
class RunRecord {
  const RunRecord({
    required this.runId,
    required this.instanceId,
    required this.directory,
    required this.state,
    required this.createdAt,
    this.relay,
    this.server,
    this.stopRequestedAt,
    this.stopGrace = Duration.zero,
    this.stopClearsRequested = true,
    this.stoppedBy = '',
    this.exitCode,
    this.endedAt,
    this.endReason = '',
    this.launchedPorts = const {},
  });

  final String runId;
  final String instanceId;
  final String directory;
  final RunState state;
  final DateTime createdAt;
  final ProcessIdentity? relay;
  final ProcessIdentity? server;

  /// Written before the stop strategy is sent (design D2).
  final DateTime? stopRequestedAt;
  final Duration stopGrace;

  /// Whether the stop is a Stop (clears the last requested state) or the
  /// internal stop of an update or restart (D14).
  final bool stopClearsRequested;
  final String stoppedBy;
  final int? exitCode;
  final DateTime? endedAt;
  final String endReason;

  /// The port numbers by name the server was launched with (design D11); the
  /// firewall rules follow them while the run has not ended. Empty for a run
  /// recorded before they were kept.
  final Map<String, int> launchedPorts;
}

/// SQLite persistence of run records and crash timestamps. The process
/// supervisor (the instance manager and lifecycle) is its only writer.
class RunStore {
  RunStore(this._database);

  final YaguraDatabase _database;

  static DateTime _time(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  /// Records a run `pending`, before its launcher is spawned.
  void insertPending({
    required String runId,
    required String instanceId,
    required String directory,
    required DateTime at,
    Map<String, int> launchedPorts = const {},
  }) {
    _database.sqlite.execute(
      'INSERT INTO runs (run_id, instance_id, directory, state, created_at, '
      'launched_ports) VALUES (?, ?, ?, ?, ?, ?)',
      [
        runId,
        instanceId,
        directory,
        RunState.pending.name,
        at.millisecondsSinceEpoch,
        jsonEncode(launchedPorts),
      ],
    );
  }

  /// Records the relay the launcher reported, before the server is known: the
  /// daemon's own record of the relay, so a `relay.json` rewritten by the
  /// game-server account never names it (design D9).
  void recordRelay(String runId, ProcessIdentity relay) {
    _database.sqlite.execute(
      'UPDATE runs SET relay_pid = ?, relay_created = ?, '
      'relay_executable = ? WHERE run_id = ?',
      [relay.pid, relay.created, relay.executable, runId],
    );
  }

  /// Marks the run `running` with the identities that were verified.
  void markRunning(
    String runId, {
    required ProcessIdentity server,
    ProcessIdentity? relay,
  }) {
    _database.sqlite.execute(
      'UPDATE runs SET state = ?, server_pid = ?, server_created = ?, '
      'executable = ?, relay_pid = ?, relay_created = ?, '
      'relay_executable = ? WHERE run_id = ?',
      [
        RunState.running.name,
        server.pid,
        server.created,
        server.executable,
        relay?.pid ?? 0,
        relay?.created ?? 0,
        relay?.executable ?? '',
        runId,
      ],
    );
  }

  /// Writes `stop_requested_at`, before the stop strategy is sent.
  void markStopRequested(
    String runId, {
    required DateTime at,
    required Duration grace,
    required bool clearsRequested,
  }) {
    _database.sqlite.execute(
      'UPDATE runs SET stop_requested_at = ?, stop_grace_ms = ?, '
      'stop_clears_requested = ? WHERE run_id = ?',
      [
        at.millisecondsSinceEpoch,
        grace.inMilliseconds,
        clearsRequested ? 1 : 0,
        runId,
      ],
    );
  }

  /// Ends the run: the exit was observed, or the run was found lost.
  void markEnded(
    String runId, {
    required DateTime at,
    String reason = '',
    String stoppedBy = '',
    int? exitCode,
  }) {
    _database.sqlite.execute(
      'UPDATE runs SET state = ?, ended_at = ?, end_reason = ?, '
      'stopped_by = ?, exit_code = ? WHERE run_id = ?',
      [
        RunState.ended.name,
        at.millisecondsSinceEpoch,
        reason,
        stoppedBy,
        exitCode,
        runId,
      ],
    );
  }

  RunRecord? get(String runId) {
    final rows = _database.sqlite.select(
      'SELECT * FROM runs WHERE run_id = ?',
      [runId],
    );
    return rows.isEmpty ? null : _read(rows.first);
  }

  /// The runs of [instanceId] that have not ended, oldest first.
  List<RunRecord> unresolvedFor(String instanceId) => [
    for (final row in _database.sqlite.select(
      'SELECT * FROM runs WHERE instance_id = ? AND state != ? '
      'ORDER BY created_at, rowid',
      [instanceId, RunState.ended.name],
    ))
      _read(row),
  ];

  /// Every run that has not ended.
  List<RunRecord> unresolved() => [
    for (final row in _database.sqlite.select(
      'SELECT * FROM runs WHERE state != ? ORDER BY created_at, rowid',
      [RunState.ended.name],
    ))
      _read(row),
  ];

  /// Every run of [instanceId], oldest first.
  List<RunRecord> all(String instanceId) => [
    for (final row in _database.sqlite.select(
      'SELECT * FROM runs WHERE instance_id = ? ORDER BY created_at, rowid',
      [instanceId],
    ))
      _read(row),
  ];

  RunRecord _read(Map<String, Object?> row) {
    ProcessIdentity? identity(String pid, String created, String exe) {
      final number = row[pid]! as int;
      if (number == 0) return null;
      return ProcessIdentity(
        pid: number,
        executable: row[exe]! as String,
        created: row[created]! as int,
      );
    }

    final stopAt = row['stop_requested_at'] as int?;
    final endedAt = row['ended_at'] as int?;
    return RunRecord(
      runId: row['run_id']! as String,
      instanceId: row['instance_id']! as String,
      directory: row['directory']! as String,
      state: RunState.fromWire(row['state']! as String),
      createdAt: _time(row['created_at']! as int),
      relay: identity('relay_pid', 'relay_created', 'relay_executable'),
      server: identity('server_pid', 'server_created', 'executable'),
      stopRequestedAt: stopAt == null ? null : _time(stopAt),
      stopGrace: Duration(milliseconds: row['stop_grace_ms']! as int),
      stopClearsRequested: (row['stop_clears_requested']! as int) != 0,
      stoppedBy: row['stopped_by']! as String,
      exitCode: row['exit_code'] as int?,
      endedAt: endedAt == null ? null : _time(endedAt),
      endReason: row['end_reason']! as String,
      launchedPorts: _ports(row['launched_ports']! as String),
    );
  }

  /// The ports a run was launched with; `{}` for the `[]` older rows hold.
  static Map<String, int> _ports(String json) {
    try {
      if (jsonDecode(json) case final Map<String, Object?> map) {
        return {
          for (final MapEntry(:key, :value) in map.entries)
            if (value is int) key: value,
        };
      }
    } on FormatException {
      // Unreadable reads as unknown: the saved ports apply.
    }
    return const {};
  }

  // ---- crashes -------------------------------------------------------------

  void addCrash(String instanceId, DateTime at) {
    _database.sqlite.execute(
      'INSERT INTO crashes (instance_id, at) VALUES (?, ?)',
      [instanceId, at.millisecondsSinceEpoch],
    );
  }

  /// Crash timestamps of [instanceId] at or after [since], oldest first.
  List<DateTime> crashesSince(String instanceId, DateTime since) => [
    for (final row in _database.sqlite.select(
      'SELECT at FROM crashes WHERE instance_id = ? AND at >= ? ORDER BY at',
      [instanceId, since.millisecondsSinceEpoch],
    ))
      _time(row['at']! as int),
  ];

  /// Resets the restart counter (Start or Acknowledge from `crash_loop`).
  void clearCrashes(String instanceId) {
    _database.sqlite.execute('DELETE FROM crashes WHERE instance_id = ?', [
      instanceId,
    ]);
  }
}
