import '../host/database.dart';

/// The hash of each file the config binder last wrote, per instance (design
/// D9, table `bound_files`). The binder compares a file against it to find a
/// hand edit made since.
class BoundFileStore {
  BoundFileStore(this._database);

  final YaguraDatabase _database;

  /// The recorded hashes of [instanceId] by path.
  Map<String, String> hashes(String instanceId) => {
    for (final row in _database.sqlite.select(
      'SELECT path, hash FROM bound_files WHERE instance_id = ?',
      [instanceId],
    ))
      row['path']! as String: row['hash']! as String,
  };

  /// Records [hashes] (path to SHA-256) for [instanceId] in one transaction.
  void record(String instanceId, Map<String, String> hashes) {
    if (hashes.isEmpty) return;
    final db = _database.sqlite;
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final MapEntry(:key, :value) in hashes.entries) {
        db.execute(
          'INSERT INTO bound_files(instance_id, path, hash) VALUES (?, ?, ?) '
          'ON CONFLICT(instance_id, path) DO UPDATE SET hash = excluded.hash',
          [instanceId, key, value],
        );
      }
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
