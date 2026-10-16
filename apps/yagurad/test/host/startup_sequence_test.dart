import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/data_directory.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/migrations.dart';

import '../support/daemon_support.dart';

/// A database at the current schema, closed again, with one operation row.
int seedCurrentDatabase(TestEnv env) {
  final dir = DataDirectory.prepare(env.data);
  final db = YaguraDatabase.open(dir.databasePath);
  final version = db.schemaVersion;
  db.sqlite.execute(
    "INSERT INTO operations(id, instance_id, kind, status, created_at) "
    "VALUES ('op-old', 'x', 'install', 'succeeded', 1)",
  );
  db.close();
  return version;
}

bool hasTable(YaguraDatabase db, String name) => db.sqlite.select(
  "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
  [name],
).isNotEmpty;

void main() {
  test('migration_with_backup', () async {
    final env = TestEnv();
    final old = seedCurrentDatabase(env);
    final next = old + 1;

    final daemon = await env.start(
      migrations: [
        ...allMigrations,
        Migration(next, 'CREATE TABLE added_later(x INTEGER)'),
      ],
    );

    final backup = File(p.join(env.data, 'yagura.db.bak-$old'));
    expect(backup.existsSync(), isTrue);
    final backedUp = YaguraDatabase.open(backup.path);
    expect(backedUp.schemaVersion, old);
    expect(hasTable(backedUp, 'added_later'), isFalse);
    backedUp.close();

    final live = YaguraDatabase.open(
      p.join(env.data, 'yagura.db'),
      migrations: [
        ...allMigrations,
        Migration(next, 'CREATE TABLE added_later(x INTEGER)'),
      ],
    );
    expect(live.schemaVersion, next);
    expect(hasTable(live, 'added_later'), isTrue);
    expect(
      live.sqlite.select("SELECT id FROM operations WHERE id = 'op-old'"),
      hasLength(1),
    );
    live.close();
    expect(daemon.instances.list(), isEmpty);
  });

  test('migration_fails', () async {
    final env = TestEnv();
    final old = seedCurrentDatabase(env);
    final next = old + 1;

    await expectLater(
      env.start(
        migrations: [
          ...allMigrations,
          Migration(next, 'CREATE TABLE half_done(x); THIS IS NOT SQL;'),
        ],
      ),
      failsWith(
        'migration_failed',
        messageHas: ['$next'],
        details: {'migration': next},
      ),
    );

    final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    expect(db.schemaVersion, old);
    expect(hasTable(db, 'half_done'), isFalse);
    expect(
      db.sqlite.select("SELECT id FROM operations WHERE id = 'op-old'"),
      hasLength(1),
    );
    db.close();

    // The failed start released the data directory lock.
    final daemon = await env.start();
    expect(daemon.instances.list(), isEmpty);
  });
}
