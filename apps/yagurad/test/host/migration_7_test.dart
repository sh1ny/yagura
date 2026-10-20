import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/migrations.dart';

import '../support/temp_support.dart';

Set<String> columnsOf(YaguraDatabase db, String table) => {
  for (final row in db.sqlite.select('PRAGMA table_info($table)'))
    row['name']! as String,
};

void main() {
  late Directory dir;
  late YaguraDatabase db;

  setUp(() {
    dir = createCanonicalTempSync('yagurad_migration7_');
    db = YaguraDatabase.open(p.join(dir.path, 'yagura.db'));
    addTearDown(() {
      db.close();
      dir.deleteSync(recursive: true);
    });
  });

  test('migration_7_adds_the_m3_schema', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(7));
    expect(columnsOf(db, 'steam_accounts'), {
      'id',
      'username',
      'status',
      'password_secret_id',
      'last_login_at',
      'created_at',
    });
    expect(columnsOf(db, 'operations'), contains('account_id'));
    expect(columnsOf(db, 'instance_mods'), {
      'instance_id',
      'position',
      'source',
      'item_id',
      'role',
      'staged_name',
      'stage_kind',
      'desired_version',
      'staged_version',
      'status',
      'last_error',
      'warnings_json',
      'remote_updated',
      'update_available',
    });
    expect(columnsOf(db, 'content_versions'), {
      'source',
      'app',
      'item',
      'version',
      'size_bytes',
      'published_at',
      'unreferenced_since',
    });
    expect(columnsOf(db, 'placed_keys'), {
      'instance_id',
      'file_name',
      'content_hash',
      'providers_json',
    });
    expect(columnsOf(db, 'bound_files'), {'instance_id', 'path', 'hash'});
    expect(columnsOf(db, 'replaced_secrets'), {
      'instance_id',
      'setting',
      'blob',
      'replaced_at',
    });
  });

  test('migration_7_keeps_existing_rows_and_cascades_instance_tables', () {
    final path = p.join(dir.path, 'v6.db');
    final v6 = YaguraDatabase.open(
      path,
      migrations: allMigrations.take(6).toList(),
    );
    expect(v6.schemaVersion, 6);
    v6.sqlite
      ..execute(
        'INSERT INTO instances(id, name, plugin_id, plugin_version, '
        'directory, state, settings_json, created_at, state_changed_at) '
        "VALUES ('A', 'A', 'valheim', '1', 'd', 'stopped', '{}', 1, 1)",
      )
      ..execute(
        'INSERT INTO operations(id, instance_id, kind, status, created_at) '
        "VALUES ('op1', 'A', 'install', 'succeeded', 1)",
      );
    v6.close();

    final migrated = YaguraDatabase.open(path);
    addTearDown(migrated.close);

    expect(migrated.schemaVersion, allMigrations.last.number);
    final op = migrated.sqlite
        .select('SELECT instance_id, account_id FROM operations')
        .single;
    expect(op['instance_id'], 'A');
    expect(op['account_id'], '');

    migrated.sqlite
      ..execute(
        'INSERT INTO operations(id, instance_id, kind, status, created_at, '
        "account_id) VALUES ('op2', '', 'login', 'running', 2, 'acct_1')",
      )
      ..execute(
        'INSERT INTO instance_mods(instance_id, position, source, item_id) '
        "VALUES ('A', 0, 'workshop', '123')",
      )
      ..execute(
        'INSERT INTO placed_keys(instance_id, file_name) VALUES (?, ?)',
        ['A', 'a.bikey'],
      )
      ..execute('INSERT INTO bound_files(instance_id, path) VALUES (?, ?)', [
        'A',
        'cfg.json',
      ])
      ..execute(
        'INSERT INTO replaced_secrets(instance_id, setting, blob, '
        'replaced_at) VALUES (?, ?, ?, ?)',
        [
          'A',
          'password',
          [1, 2],
          3,
        ],
      );
    final mod = migrated.sqlite.select('SELECT * FROM instance_mods').single;
    expect(mod['status'], 'pending');
    expect(mod['stage_kind'], '');

    migrated.sqlite.execute('DELETE FROM instances');
    for (final table in [
      'instance_mods',
      'placed_keys',
      'bound_files',
      'replaced_secrets',
    ]) {
      expect(
        migrated.sqlite.select('SELECT 1 FROM $table'),
        isEmpty,
        reason: table,
      );
    }
  });
}
