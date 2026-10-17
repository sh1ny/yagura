import '../host/database.dart';
import 'source_tailer.dart';

/// Persisted tailer offsets (`log_offsets`, migration 2): where each source of
/// each instance was read up to, so a restart refills the ring from the file
/// tail and delivers what was written while the daemon was down.
class LogOffsetStore {
  LogOffsetStore(this._database);

  final YaguraDatabase _database;

  LogPosition? load(String instanceId, String source) {
    final rows = _database.sqlite.select(
      'SELECT file, offset FROM log_offsets '
      'WHERE instance_id = ? AND source = ?',
      [instanceId, source],
    );
    if (rows.isEmpty) return null;
    return LogPosition(
      rows.first['file'] as String,
      rows.first['offset'] as int,
    );
  }

  void save(String instanceId, String source, LogPosition position) {
    _database.sqlite.execute(
      'INSERT INTO log_offsets (instance_id, source, file, offset) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT (instance_id, source) '
      'DO UPDATE SET file = excluded.file, offset = excluded.offset',
      [instanceId, source, position.file, position.offset],
    );
  }

  void forgetSource(String instanceId, String source) {
    _database.sqlite.execute(
      'DELETE FROM log_offsets WHERE instance_id = ? AND source = ?',
      [instanceId, source],
    );
  }

  void forgetInstance(String instanceId) {
    _database.sqlite.execute('DELETE FROM log_offsets WHERE instance_id = ?', [
      instanceId,
    ]);
  }
}
