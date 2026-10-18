import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';

Set<String> columnsOf(YaguraDatabase db, String table) => {
  for (final row in db.sqlite.select('PRAGMA table_info($table)'))
    row['name']! as String,
};

void main() {
  late Directory dir;
  late YaguraDatabase db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('yagurad_migration4_');
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

  test('existing_instances_start_at_revision_1', () {
    final old = YaguraDatabase.open(p.join(dir.path, 'old.db'));
    addTearDown(old.close);
    old.sqlite.execute(
      'INSERT INTO instances(id, name, plugin_id, plugin_version, directory, '
      'state, settings_json, created_at, state_changed_at) '
      "VALUES ('A', 'A', 'valheim', '1', 'd', 'stopped', '{}', 1, 1)",
    );

    final row = old.sqlite.select('SELECT revision, acl_layout FROM instances');
    expect(row.single['revision'], 1);
    expect(row.single['acl_layout'], 0);
  });
}
