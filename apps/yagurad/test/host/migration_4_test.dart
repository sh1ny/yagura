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
    dir = createCanonicalTempSync('yagurad_migration4_');
    db = YaguraDatabase.open(p.join(dir.path, 'yagura.db'));
    addTearDown(() {
      db.close();
      dir.deleteSync(recursive: true);
    });
  });

  test('migration_4_adds_the_m2_schema', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(4));
    expect(columnsOf(db, 'secrets'), {
      'id',
      'instance_id',
      'setting',
      'blob',
      'scope_sid',
      'created_at',
    });
    expect(columnsOf(db, 'instances'), containsAll(['revision', 'acl_layout']));
    expect(columnsOf(db, 'runs'), contains('launched_ports'));
    expect(columnsOf(db, 'devices'), {
      'id',
      'name',
      'enrolled_at',
      'last_seen_at',
      'last_address',
      'revoked_at',
      'revoked_by',
    });
    expect(columnsOf(db, 'device_certificates'), {
      'device_id',
      'sha256',
      'not_after',
      'first_used_at', // migration 6
      'issued_at', // migration 6
    });
    expect(columnsOf(db, 'pairing_codes'), {
      'code_hash',
      'created_at',
      'expires_at',
      'used_at',
    });
    expect(
      columnsOf(db, 'audit'),
      containsAll(['time', 'device_id', 'method', 'target', 'result']),
    );
    expect(columnsOf(db, 'auth_failures'), {
      'address',
      'window_start',
      'count',
      'last_reason',
    });
    expect(columnsOf(db, 'instance_roots'), {'path', 'added_at'});
    expect(columnsOf(db, 'steamcmd_installations'), {
      'installation',
      'ready_at',
    });
    expect(columnsOf(db, 'steam_app_sizes'), {
      'app_id',
      'bytes',
      'recorded_at',
    });
  });

  test('existing_rows_get_the_new_column_defaults', () {
    final path = p.join(dir.path, 'old.db');
    final v3 = YaguraDatabase.open(
      path,
      migrations: allMigrations.take(3).toList(),
    );
    expect(v3.schemaVersion, 3);
    v3.sqlite
      ..execute(
        'INSERT INTO instances(id, name, plugin_id, plugin_version, '
        'directory, state, settings_json, created_at, state_changed_at) '
        "VALUES ('A', 'A', 'valheim', '1', 'd', 'stopped', '{}', 1, 1)",
      )
      ..execute(
        'INSERT INTO runs(run_id, instance_id, directory, state, created_at) '
        "VALUES ('r1', 'A', 'd', 'ended', 1)",
      );
    v3.close();

    final migrated = YaguraDatabase.open(path);
    addTearDown(migrated.close);

    expect(migrated.schemaVersion, allMigrations.last.number);
    final instance = migrated.sqlite
        .select('SELECT name, revision, acl_layout FROM instances')
        .single;
    expect(instance['name'], 'A');
    expect(instance['revision'], 1);
    expect(instance['acl_layout'], 0);
    final run = migrated.sqlite
        .select('SELECT launched_ports FROM runs')
        .single;
    expect(run['launched_ports'], '[]');
  });
  test('migration_6_counts_existing_certificates_as_used', () {
    final path = p.join(dir.path, 'v5.db');
    final v5 = YaguraDatabase.open(
      path,
      migrations: allMigrations.take(5).toList(),
    );
    v5.sqlite
      ..execute('INSERT INTO devices(id, name, enrolled_at) VALUES (?, ?, ?)', [
        'dev-1',
        'desk',
        1,
      ])
      ..execute(
        'INSERT INTO device_certificates(device_id, sha256, not_after) '
        "VALUES ('dev-1', 'abc', 2)",
      );
    v5.close();

    final migrated = YaguraDatabase.open(path);
    addTearDown(migrated.close);

    final row = migrated.sqlite
        .select('SELECT first_used_at FROM device_certificates')
        .single;
    expect(row['first_used_at'], isNotNull);
  });
}
