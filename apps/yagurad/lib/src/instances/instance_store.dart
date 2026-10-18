import 'dart:convert';

import 'package:yagura_plugin/yagura_plugin.dart';

import '../errors.dart';
import '../host/database.dart';
import '../process/process.dart';
import 'instance.dart';

/// The `revision_conflict` failure for [instanceId], carrying the current
/// [revision] in its details (design D12).
YaguraException revisionConflict(String instanceId, int revision) =>
    YaguraException(
      'revision_conflict',
      'instance $instanceId is at revision $revision; reload and retry',
      details: {'instanceId': instanceId, 'revision': revision},
    );

/// The mutable record of one instance. The instance manager is its only
/// writer; [InstanceStore] mirrors it to SQLite.
class InstanceRecord {
  InstanceRecord({
    required this.id,
    required this.name,
    required this.pluginId,
    required this.pluginVersion,
    required this.directory,
    required this.state,
    required this.settings,
    required this.ports,
    required this.createdAt,
    required this.stateChangedAt,
    this.stateReason = '',
    this.warning = '',
    this.steamAccountId = '',
    this.restartPolicy = 'on_crash',
    this.autostart = true,
    this.lastRequestedRunning = false,
    this.restartRequired = false,
    this.settingsInvalid = false,
    this.revision = 1,
  });

  final String id;
  String name;
  String pluginId;
  String pluginVersion;
  final String directory;
  InstanceState state;
  String stateReason;
  String warning;

  /// Validated values with defaults; secrets are never stored.
  Map<String, Object?> settings;
  List<PortAssignment> ports;
  String steamAccountId;
  String restartPolicy;
  bool autostart;

  /// Set when a Start succeeds; cleared by Stop, Delete and operations that
  /// end with the server stopped (design D14).
  bool lastRequestedRunning;
  bool restartRequired;
  bool settingsInvalid;

  /// The configuration revision (design D12).
  int revision;
  final DateTime createdAt;
  DateTime stateChangedAt;

  /// The live server, in memory only (the supervisor of group 5 records runs).
  RunningServer? server;

  /// The run of [server] (memory only; the run record is in SQLite).
  String runId = '';

  /// Whether a stop of [server] was requested, so its exit is not a crash.
  bool stopRequested = false;

  /// `unknown` while the instance runs without a passed health check.
  InstanceHealth health = InstanceHealth.unspecified;

  /// Whether `error` carries one of the reasons with their own exits; any
  /// other reason is an update failure (design D17).
  bool get isUpdateFailure =>
      state == InstanceState.error &&
      stateReason != crashLoopReason &&
      stateReason != restoreInterruptedReason &&
      stateReason != settingsInvalidReason &&
      stateReason != pluginMissingReason;
}

/// SQLite persistence of instance records (`instances`, `instance_ports`).
class InstanceStore {
  InstanceStore(this._database);

  final YaguraDatabase _database;

  /// Every stored instance, oldest first.
  List<InstanceRecord> loadAll() {
    final db = _database.sqlite;
    final ports = <String, List<PortAssignment>>{};
    for (final row in db.select(
      'SELECT * FROM instance_ports ORDER BY rowid',
    )) {
      ports
          .putIfAbsent(row['instance_id']! as String, () => [])
          .add(
            PortAssignment(
              name: row['name']! as String,
              number: row['number']! as int,
              protocol: PortProtocol.values.byName(row['protocol']! as String),
              purpose: PortPurpose.values.byName(row['purpose']! as String),
              exposed: (row['exposed']! as int) != 0,
            ),
          );
    }
    return [
      for (final row in db.select(
        'SELECT * FROM instances ORDER BY created_at, rowid',
      ))
        InstanceRecord(
          id: row['id']! as String,
          name: row['name']! as String,
          pluginId: row['plugin_id']! as String,
          pluginVersion: row['plugin_version']! as String,
          directory: row['directory']! as String,
          state: InstanceState.fromWire(row['state']! as String),
          stateReason: row['state_reason']! as String,
          warning: row['warning']! as String,
          settings: Map<String, Object?>.from(
            jsonDecode(row['settings_json']! as String) as Map,
          ),
          ports: ports[row['id']! as String] ?? const [],
          steamAccountId: row['steam_account_id']! as String,
          restartPolicy: row['restart_policy']! as String,
          autostart: (row['autostart']! as int) != 0,
          lastRequestedRunning: row['last_requested_state']! == 'running',
          restartRequired: (row['restart_required']! as int) != 0,
          settingsInvalid: (row['settings_invalid']! as int) != 0,
          revision: row['revision']! as int,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at']! as int,
          ),
          stateChangedAt: DateTime.fromMillisecondsSinceEpoch(
            row['state_changed_at']! as int,
          ),
        ),
    ];
  }

  /// Writes [record] and its ports in one transaction.
  void save(InstanceRecord record) {
    _database.transaction(() => _write(record, record.revision));
  }

  /// Writes [record] as the revision after [expected], in one transaction
  /// that first checks the stored revision (design D12): a mismatch fails
  /// `revision_conflict` and writes nothing. The record's revision is set
  /// once the transaction committed.
  void saveRevised(InstanceRecord record, int expected) {
    _database.transaction(() {
      _requireStored(record.id, expected);
      _write(record, expected + 1);
    });
    record.revision = expected + 1;
  }

  /// Sets the stored revision of [record] to [revision] after checking that
  /// it is [expected] (an accepted restore, or the undo of one).
  void setRevision(InstanceRecord record, int expected, int revision) {
    _database.transaction(() {
      _requireStored(record.id, expected);
      _database.sqlite.execute(
        'UPDATE instances SET revision = ? WHERE id = ?',
        [revision, record.id],
      );
    });
    record.revision = revision;
  }

  void _requireStored(String id, int expected) {
    final rows = _database.sqlite.select(
      'SELECT revision FROM instances WHERE id = ?',
      [id],
    );
    final stored = rows.isEmpty ? null : rows.first['revision']! as int;
    if (stored != null && stored != expected) {
      throw revisionConflict(id, stored);
    }
  }

  void _write(InstanceRecord record, int revision) {
    final db = _database.sqlite;
    final values = [
      record.name,
      record.pluginId,
      record.pluginVersion,
      record.directory,
      record.state.wireName,
      record.stateReason,
      record.warning,
      jsonEncode(record.settings),
      record.steamAccountId,
      record.restartPolicy,
      record.autostart ? 1 : 0,
      record.lastRequestedRunning ? 'running' : '',
      record.restartRequired ? 1 : 0,
      record.settingsInvalid ? 1 : 0,
      record.stateChangedAt.millisecondsSinceEpoch,
      revision,
    ];
    db.execute(
      'UPDATE instances SET name = ?, plugin_id = ?, plugin_version = ?, '
      'directory = ?, state = ?, state_reason = ?, warning = ?, '
      'settings_json = ?, steam_account_id = ?, restart_policy = ?, '
      'autostart = ?, last_requested_state = ?, restart_required = ?, '
      'settings_invalid = ?, state_changed_at = ?, revision = ? WHERE id = ?',
      [...values, record.id],
    );
    if (db.updatedRows == 0) {
      db.execute(
        'INSERT INTO instances (name, plugin_id, plugin_version, directory, '
        'state, state_reason, warning, settings_json, steam_account_id, '
        'restart_policy, autostart, last_requested_state, restart_required, '
        'settings_invalid, state_changed_at, revision, id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [...values, record.id, record.createdAt.millisecondsSinceEpoch],
      );
    }
    db.execute('DELETE FROM instance_ports WHERE instance_id = ?', [record.id]);
    for (final port in record.ports) {
      db.execute(
        'INSERT INTO instance_ports (instance_id, name, number, protocol, '
        'purpose, exposed) VALUES (?, ?, ?, ?, ?, ?)',
        [
          record.id,
          port.name,
          port.number,
          port.protocol.name,
          port.purpose.name,
          port.exposed ? 1 : 0,
        ],
      );
    }
  }

  /// Removes the instance's rows (its ports go with it); operation rows stay.
  void delete(String id) {
    _database.sqlite.execute('DELETE FROM instances WHERE id = ?', [id]);
  }
}
