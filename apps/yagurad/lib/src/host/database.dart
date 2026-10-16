import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../errors.dart';
import 'migrations.dart';

/// A numbered schema migration: SQL statements run in order.
class Migration {
  const Migration(this.number, this.sql);

  final int number;
  final String sql;
}

/// The SQLite database (ADR 0008): WAL mode, numbered migrations run at
/// startup in one transaction after a backup copy, `PRAGMA user_version` as
/// the schema version.
class YaguraDatabase {
  YaguraDatabase._(this.sqlite);

  final Database sqlite;

  /// Opens (creating if needed) and migrates the database at [path] to the
  /// last of [migrations] (default [allMigrations]).
  ///
  /// When migrations are pending on an existing database, a copy named
  /// `<path>.bak-N` (N = the old schema version) is written first. If a
  /// migration fails, the transaction rolls
  /// back and `migration_failed` is thrown naming its number.
  static YaguraDatabase open(String path, {List<Migration>? migrations}) {
    final all = migrations ?? allMigrations;
    final Database db;
    try {
      db = sqlite3.open(path);
    } on SqliteException catch (e) {
      throw YaguraException(
        'internal_error',
        'cannot open the database $path: ${e.message}',
        details: {'step': 'database', 'path': path},
      );
    }
    try {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA foreign_keys = ON');
      _migrate(db, path, all);
    } on Object {
      db.close();
      rethrow;
    }
    return YaguraDatabase._(db);
  }

  static int _version(Database db) =>
      db.select('PRAGMA user_version').first.values.first! as int;

  static void _migrate(Database db, String path, List<Migration> all) {
    final current = _version(db);
    final latest = all.isEmpty ? 0 : all.last.number;
    if (current > latest) {
      throw YaguraException(
        'migration_failed',
        'the database is at schema version $current, newer than this daemon '
            '($latest)',
        details: {'step': 'database', 'migration': current},
      );
    }
    final pending = [
      for (final m in all)
        if (m.number > current) m,
    ];
    if (pending.isEmpty) return;

    if (current > 0) {
      final backup = '$path.bak-$current';
      if (File(backup).existsSync()) File(backup).deleteSync();
      db.execute('VACUUM INTO ?', [backup]);
    }

    var running = current;
    try {
      db.execute('BEGIN IMMEDIATE');
      for (final migration in pending) {
        running = migration.number;
        db.execute(migration.sql);
        db.execute('PRAGMA user_version = ${migration.number}');
      }
      db.execute('COMMIT');
    } on SqliteException catch (e) {
      try {
        db.execute('ROLLBACK');
      } on SqliteException {
        // No transaction left to roll back.
      }
      throw YaguraException(
        'migration_failed',
        'migration $running failed and was rolled back: ${e.message}',
        details: {'step': 'database', 'migration': running},
      );
    }
  }

  /// The schema version (`PRAGMA user_version`).
  int get schemaVersion => _version(sqlite);

  /// Runs [body] in a transaction: committed when it returns, rolled back
  /// when it throws.
  T transaction<T>(T Function() body) {
    sqlite.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      sqlite.execute('COMMIT');
      return result;
    } on Object {
      sqlite.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => sqlite.close();
}
