import 'dart:convert';
import 'dart:typed_data';

import 'database.dart';
import 'secret_store.dart';

/// The secret values an instance's settings held before they were replaced or
/// deleted (design D11, table `replaced_secrets`), kept for 24 hours so the
/// log masker still hides a password a server keeps printing after a
/// rotation.
///
/// A row holds the DPAPI blob of a JSON list of the values replaced for one
/// setting, so rotating a setting twice within a day hides both old values.
class ReplacedSecrets {
  ReplacedSecrets(this._database, this._protector, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// How long a replaced value stays masked.
  static const retention = Duration(hours: 24);

  final YaguraDatabase _database;
  final SecretProtector _protector;
  final DateTime Function() _clock;

  /// Remembers [value], the value of [setting] of [instanceId] until now.
  void record(String instanceId, String setting, Uint8List value) {
    final db = _database.sqlite;
    final rows = db.select(
      'SELECT blob FROM replaced_secrets WHERE instance_id = ? AND setting = ?',
      [instanceId, setting],
    );
    final values = {
      for (final row in rows) ..._open(row['blob']! as List<int>),
      utf8.decode(value, allowMalformed: true),
    }.toList();
    db.execute(
      'INSERT OR REPLACE INTO replaced_secrets'
      '(instance_id, setting, blob, replaced_at) VALUES (?, ?, ?, ?)',
      [
        instanceId,
        setting,
        _protector.protect(Uint8List.fromList(utf8.encode(jsonEncode(values)))),
        _clock().millisecondsSinceEpoch,
      ],
    );
  }

  /// The values of [instanceId] replaced within [retention].
  List<String> recent(String instanceId) {
    final cutoff = _clock().subtract(retention).millisecondsSinceEpoch;
    return [
      for (final row in _database.sqlite.select(
        'SELECT blob FROM replaced_secrets '
        'WHERE instance_id = ? AND replaced_at > ?',
        [instanceId, cutoff],
      ))
        ..._open(row['blob']! as List<int>),
    ];
  }

  /// Deletes the rows older than [retention]; returns how many.
  int prune() {
    final cutoff = _clock().subtract(retention).millisecondsSinceEpoch;
    _database.sqlite.execute(
      'DELETE FROM replaced_secrets WHERE replaced_at <= ?',
      [cutoff],
    );
    return _database.sqlite.updatedRows;
  }

  /// The values in a blob; none for one this scope cannot open (the secret
  /// store deletes those rows when it opens).
  List<String> _open(List<int> blob) {
    try {
      final plain = _protector.unprotect(Uint8List.fromList(blob));
      return [
        for (final value in jsonDecode(utf8.decode(plain)) as List)
          value as String,
      ];
    } on WrongSecretKey {
      return const [];
    } on FormatException {
      return const [];
    }
  }
}
