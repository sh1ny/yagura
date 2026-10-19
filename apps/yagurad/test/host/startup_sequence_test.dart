import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/data_directory.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/migrations.dart';

import '../support/acl_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';

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

  test('corrupt_database_is_a_fatal_database_step', () async {
    final env = TestEnv();
    DataDirectory.prepare(env.data);
    File(p.join(env.data, 'yagura.db'))
        .writeAsBytesSync(List.filled(4096, 0x41));

    await expectLater(
      env.start(),
      failsWith('internal_error', details: {'step': 'database'}),
    );

    // The failed start released the data directory lock.
    File(p.join(env.data, 'yagura.db')).deleteSync();
    final daemon = await env.start();
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

  test('data_directory_used_by_a_dev_daemon_first', () async {
    final env = TestEnv()..installValheim();
    var daemon = await env.start(secretProtector: FakeSecretProtector(devSid));
    final a = await createValheim(daemon, name: 'A');
    daemon.secrets.put(
      'valheim-password',
      Uint8List.fromList([1, 2, 3]),
      instanceId: a.id,
      setting: 'password',
    );
    await env.closeDaemons();
    final before = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    final stored = before.sqlite.select('SELECT id, scope_sid FROM secrets');
    before.close();
    expect(
      stored.single['scope_sid'],
      devSid,
      reason: 'the dev daemon stored it',
    );

    // The data directory protection needs administrator rights; the fake
    // stands in for it, so this row passes without them.
    final protector = FakeDataDirProtector();
    daemon = await env.start(
      serviceMode: true,
      secretProtector: FakeSecretProtector(serviceSid),
      dataDirProtector: protector,
    );
    expect(protector.events.first, 'open');

    // Recovery deleted the row, not just hid it.
    final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    addTearDown(db.close);
    // The service daemon has since stored its own identity keys.
    expect(
      db.sqlite.select("SELECT id FROM secrets WHERE id NOT LIKE 'daemon:%'"),
      isEmpty,
    );

    final kept = daemon.instances.get(a.id);
    expect(kept.name, 'A');
    expect(kept.settings['password'], {'secret': true, 'set': false});
    expect(daemon.secrets.get('valheim-password'), isNull);
    final reset = daemon.startupNotices.where((n) => n.step == 'secrets_reset');
    expect(reset, hasLength(1));
    expect(reset.single.message, allOf(contains(a.id), contains('A')));
  });

  test('a_dpapi_fault_at_service_start_is_fatal_and_deletes_nothing', () async {
    final env = TestEnv();
    final first = await env.start(
      serviceMode: true,
      secretProtector: FakeSecretProtector(serviceSid),
    );
    first.secrets.put('ca-key', Uint8List.fromList([9]));
    await env.closeDaemons();

    await expectLater(
      env.start(
        serviceMode: true,
        secretProtector: FlakySecretProtector(serviceSid)..failReads = true,
      ),
      failsWith(
        'secret_store_unavailable',
        messageHas: ['1312'],
        details: {'step': 'secret_store'},
      ),
    );

    final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    addTearDown(db.close);
    expect(
      db.sqlite.select("SELECT id FROM secrets WHERE id NOT LIKE 'daemon:%'"),
      hasLength(1),
    );
    // Restarted with a working DPAPI, the CA key is still there.
    final again = await env.start(
      serviceMode: true,
      secretProtector: FakeSecretProtector(serviceSid),
    );
    expect(again.secrets.get('ca-key'), Uint8List.fromList([9]));
    expect(
      again.startupNotices.where((n) => n.step == 'secrets_reset'),
      isEmpty,
    );
  });

  test('dev_daemon_refuses_a_data_directory_of_the_service', () async {
    final env = TestEnv();
    final service = await env.start(
      serviceMode: true,
      secretProtector: FakeSecretProtector(serviceSid),
    );
    service.secrets.put('ca-key', Uint8List.fromList([9]));
    await env.closeDaemons();

    await expectLater(
      env.start(secretProtector: FakeSecretProtector(devSid)),
      failsWith(
        'secret_store_unavailable',
        messageHas: [serviceSid, devSid],
        details: {'step': 'secret_store'},
      ),
    );

    // The refusal released the lock and changed nothing.
    final again = await env.start(
      serviceMode: true,
      secretProtector: FakeSecretProtector(serviceSid),
    );
    expect(again.secrets.get('ca-key'), Uint8List.fromList([9]));
    expect(
      again.startupNotices.where((n) => n.step == 'secrets_reset'),
      isEmpty,
    );
  });
}
