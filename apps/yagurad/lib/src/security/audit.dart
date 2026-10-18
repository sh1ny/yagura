import 'dart:io';

import '../host/database.dart';
import 'atomically.dart';

/// How long one row of the authentication-failure log covers.
const failureWindow = Duration(minutes: 10);

/// Authentication failures aggregated per address per 10 minutes (design D4).
///
/// [record] only counts in memory; [flush] writes every count in one
/// transaction, so a flood costs one write per flush and not one per call. A
/// separate table keeps a flood from evicting audit entries.
class AuthFailureLog {
  AuthFailureLog(this._database, {required this._clock, this.maxRows = 10000});

  final YaguraDatabase _database;
  final DateTime Function() _clock;

  /// Rows kept; the oldest are pruned.
  final int maxRows;

  // Insertion order is the order the rows are written, so pruning by row id
  // removes the oldest.
  final _pending = <(String, int), _Pending>{};

  /// Counts one failed attempt from [address].
  void record(InternetAddress address, String reason) {
    final window = _windowStart(_clock());
    final key = (address.address, window);
    final pending = _pending[key];
    if (pending != null) {
      pending.count++;
      pending.reason = reason;
      return;
    }
    // A scanner using many addresses cannot grow the memory without bound:
    // at the bound the counts are written out.
    if (_pending.length >= maxRows) flush();
    _pending[key] = _Pending(reason);
  }

  /// Writes the counts since the last flush.
  void flush() {
    if (_pending.isEmpty) return;
    final rows = [..._pending.entries];
    _pending.clear();
    _database.transaction(() {
      for (final MapEntry(key: (address, window), :value) in rows) {
        _database.sqlite.execute(
          'INSERT INTO auth_failures(address, window_start, count, '
          'last_reason) VALUES (?, ?, ?, ?) '
          'ON CONFLICT(address, window_start) DO UPDATE SET '
          'count = count + excluded.count, '
          'last_reason = excluded.last_reason',
          [address, window, value.count, value.reason],
        );
      }
      _database.sqlite.execute(
        'DELETE FROM auth_failures WHERE rowid NOT IN ('
        'SELECT rowid FROM auth_failures '
        'ORDER BY window_start DESC, rowid DESC LIMIT ?)',
        [maxRows],
      );
    });
  }

  /// The rows written so far, oldest first.
  List<AuthFailureRow> aggregates() => [
    for (final row in _database.sqlite.select(
      'SELECT address, window_start, count, last_reason FROM auth_failures '
      'ORDER BY window_start, rowid',
    ))
      AuthFailureRow(
        row['address']! as String,
        DateTime.fromMillisecondsSinceEpoch(
          row['window_start']! as int,
          isUtc: true,
        ),
        row['count']! as int,
        row['last_reason']! as String,
      ),
  ];

  static int _windowStart(DateTime time) {
    final ms = time.millisecondsSinceEpoch;
    final width = failureWindow.inMilliseconds;
    return ms - ms % width;
  }
}

class _Pending {
  _Pending(this.reason) : count = 1;

  int count;
  String reason;
}

class AuthFailureRow {
  AuthFailureRow(this.address, this.windowStart, this.count, this.lastReason);

  final String address;
  final DateTime windowStart;
  final int count;
  final String lastReason;
}

/// The audit log of state-changing calls (design D4). It never holds a
/// secret value: the caller passes only the method, a target and the result.
class AuditLog {
  AuditLog(this._database, {required this._clock, this.maxRows = 100000});

  final YaguraDatabase _database;
  final DateTime Function() _clock;

  /// Rows kept; the oldest are pruned.
  final int maxRows;

  void record({
    required String deviceId,
    required String address,
    required String method,
    required String target,
    required String result,
  }) {
    atomically(_database, () {
      _database.sqlite.execute(
        'INSERT INTO audit(time, device_id, remote_address, method, target, '
        'result) VALUES (?, ?, ?, ?, ?, ?)',
        [
          _clock().millisecondsSinceEpoch,
          deviceId,
          address,
          method,
          target,
          result,
        ],
      );
      final last = _database.sqlite.lastInsertRowId;
      _database.sqlite.execute('DELETE FROM audit WHERE id <= ?', [
        last - maxRows,
      ]);
    });
  }

  /// Entries newest first; [before] is the id of the last entry of the
  /// previous page.
  List<AuditRecord> list({int limit = 100, int? before}) => [
    for (final row in _database.sqlite.select(
      'SELECT id, time, device_id, remote_address, method, target, result '
      'FROM audit ${before == null ? '' : 'WHERE id < ?'} '
      'ORDER BY id DESC LIMIT ?',
      [?before, limit],
    ))
      AuditRecord(
        id: row['id']! as int,
        at: DateTime.fromMillisecondsSinceEpoch(
          row['time']! as int,
          isUtc: true,
        ),
        deviceId: row['device_id']! as String,
        address: row['remote_address']! as String,
        method: row['method']! as String,
        target: row['target']! as String,
        result: row['result']! as String,
      ),
  ];
}

class AuditRecord {
  AuditRecord({
    this.id = 0,
    required this.at,
    required this.deviceId,
    required this.address,
    required this.method,
    required this.target,
    required this.result,
  });

  final int id;
  final DateTime at;
  final String deviceId;
  final String address;
  final String method;
  final String target;
  final String result;
}
