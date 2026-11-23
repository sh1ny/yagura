import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/secret_store.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';
import '../support/temp_support.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late Directory dir;
  late String dbPath;

  setUp(() {
    dir = createCanonicalTempSync('yagurad_secrets_');
    dbPath = p.join(dir.path, 'yagura.db');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  YaguraDatabase openDb() => YaguraDatabase.open(dbPath);

  void addInstance(YaguraDatabase db, String id, String name) {
    db.sqlite.execute(
      'INSERT INTO instances(id, name, plugin_id, plugin_version, directory, '
      'state, settings_json, created_at, state_changed_at) '
      "VALUES (?, ?, 'valheim', '1', 'd', 'stopped', '{}', 1, 1)",
      [id, name],
    );
  }

  DatabaseSecretStore openStore(
    YaguraDatabase db,
    String sid, {
    required bool service,
  }) => DatabaseSecretStore.open(
    db,
    FakeSecretProtector(sid),
    serviceMode: service,
  );

  test('put_get_delete', () {
    final db = openDb();
    addTearDown(db.close);
    final store = openStore(db, devSid, service: false);

    expect(store.get('s1'), isNull);
    store.put('s1', bytes('hunter2'));
    expect(store.get('s1'), bytes('hunter2'));
    store.put('s1', bytes('changed'));
    expect(store.get('s1'), bytes('changed'));
    store.delete('s1');
    expect(store.get('s1'), isNull);
    store.delete('s1');
  });

  test('stored_blob_is_protected_and_records_the_scope', () {
    final db = openDb();
    addTearDown(db.close);
    openStore(db, devSid, service: false).put('s1', bytes('hunter2'));

    final row = db.sqlite.select('SELECT blob, scope_sid FROM secrets').single;
    expect(row['scope_sid'], devSid);
    expect(
      utf8.decode(row['blob'] as List<int>, allowMalformed: true),
      isNot(contains('hunter2')),
    );
  });

  test('instance_secrets_go_with_the_instance', () {
    final db = openDb();
    addTearDown(db.close);
    addInstance(db, 'A', 'Alpha');
    final store = openStore(db, devSid, service: false);
    store.put('s1', bytes('x'), instanceId: 'A', setting: 'password');

    db.sqlite.execute("DELETE FROM instances WHERE id = 'A'");

    expect(store.get('s1'), isNull);
  });

  test('secrets_protected_for_another_account', () {
    var db = openDb();
    addInstance(db, 'A', 'Alpha');
    addInstance(db, 'B', 'Beta');
    openStore(db, devSid, service: false)
      ..put('a1', bytes('x'), instanceId: 'A', setting: 'password')
      ..put('a2', bytes('y'), instanceId: 'A', setting: 'token')
      ..put('ca', bytes('key'));
    db.close();

    db = openDb();
    addTearDown(db.close);
    final store = openStore(db, serviceSid, service: true);
    store.put('mine', bytes('own'), instanceId: 'B', setting: 'password');

    expect(store.recovery.instanceIds, ['A']);
    expect(store.recovery.ownedIds, ['ca']);
    expect(store.get('a1'), isNull);
    expect(store.get('ca'), isNull);
    expect(db.sqlite.select('SELECT id FROM instances'), hasLength(2));
    expect(
      db.sqlite.select('SELECT scope_sid FROM secrets').single['scope_sid'],
      serviceSid,
    );
  });

  test('secrets_protected_on_another_machine', () {
    var db = openDb();
    addInstance(db, 'A', 'Alpha');
    addInstance(db, 'B', 'Beta');
    DatabaseSecretStore.open(
        db,
        FakeSecretProtector(serviceSid, machine: 'old-host'),
        serviceMode: true,
      )
      ..put('a1', bytes('x'), instanceId: 'A', setting: 'password')
      ..put('ca', bytes('key'));
    db.close();

    // Same SID (LocalSystem is S-1-5-18 everywhere), another DPAPI key.
    db = openDb();
    addTearDown(db.close);
    final store = DatabaseSecretStore.open(
      db,
      FakeSecretProtector(serviceSid, machine: 'new-host'),
      serviceMode: true,
    );

    expect(store.recovery.instanceIds, ['A']);
    expect(store.recovery.instanceNames, {'A': 'Alpha'});
    expect(store.recovery.ownedIds, ['ca']);
    expect(db.sqlite.select('SELECT id FROM secrets'), isEmpty);
    expect(db.sqlite.select('SELECT id FROM instances'), hasLength(2));
  });

  test('dpapi_fault_deletes_nothing', () {
    var db = openDb();
    addInstance(db, 'A', 'Alpha');
    DatabaseSecretStore.open(
        db,
        FakeSecretProtector(serviceSid),
        serviceMode: true,
      )
      ..put('a1', bytes('x'), instanceId: 'A', setting: 'password')
      ..put('ca', bytes('key'));
    db.close();

    // The same account and machine, but DPAPI fails for another reason than
    // a wrong key: the rows are not known to be foreign.
    db = openDb();
    addTearDown(db.close);
    final protector = FlakySecretProtector(serviceSid)..failReads = true;

    expect(
      () => DatabaseSecretStore.open(db, protector, serviceMode: true),
      throwsA(
        isA<YaguraException>()
            .having((e) => e.reason, 'reason', 'secret_store_unavailable')
            .having((e) => e.message, 'message', contains('1312')),
      ),
    );

    expect(db.sqlite.select('SELECT id FROM secrets'), hasLength(2));
    expect(db.sqlite.select('SELECT id FROM instances'), hasLength(1));
    // With DPAPI back, the same rows open.
    final store = openStore(db, serviceSid, service: true);
    expect(store.recovery.isEmpty, isTrue);
    expect(store.get('ca'), bytes('key'));
  });

  test('dev_mode_does_not_test_decrypt_its_own_scope', () {
    var db = openDb();
    openStore(db, devSid, service: false).put('s1', bytes('x'));
    db.close();

    db = openDb();
    addTearDown(db.close);
    final protector = FakeSecretProtector(devSid, machine: 'other-host');
    final store = DatabaseSecretStore.open(db, protector, serviceMode: false);

    expect(store.recovery.isEmpty, isTrue);
    expect(db.sqlite.select('SELECT id FROM secrets'), hasLength(1));
  });

  test('service_mode_keeps_rows_of_its_own_scope', () {
    var db = openDb();
    addInstance(db, 'A', 'Alpha');
    openStore(
      db,
      serviceSid,
      service: true,
    ).put('a1', bytes('x'), instanceId: 'A', setting: 'password');
    db.close();

    db = openDb();
    addTearDown(db.close);
    final store = openStore(db, serviceSid, service: true);

    expect(store.recovery.isEmpty, isTrue);
    expect(store.get('a1'), bytes('x'));
  });

  test('dev_mode_refuses_foreign_scope_rows_and_changes_nothing', () {
    var db = openDb();
    openStore(db, serviceSid, service: true).put('ca', bytes('key'));
    db.close();

    db = openDb();
    addTearDown(db.close);
    expect(
      () => openStore(db, devSid, service: false),
      failsWith('secret_store_unavailable', messageHas: [serviceSid, devSid]),
    );
    expect(db.sqlite.select('SELECT id FROM secrets'), hasLength(1));
  });
}
