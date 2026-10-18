import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/security/audit.dart';

/// The bounds of design D4 on the two tables, at small sizes.
void main() {
  late YaguraDatabase db;
  late DateTime now;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('yagurad_audit_');
    addTearDown(() => dir.deleteSync(recursive: true));
    db = YaguraDatabase.open(p.join(dir.path, 'yagura.db'));
    addTearDown(db.close);
    now = DateTime.utc(2030, 1, 1);
  });

  test('the audit log keeps the newest rows up to its bound', () {
    final log = AuditLog(db, clock: () => now, maxRows: 100);
    for (var i = 0; i < 130; i++) {
      now = now.add(const Duration(seconds: 1));
      log.record(
        deviceId: 'd',
        address: '127.0.0.1',
        method: 'yagura.v1.Instances/DeleteInstance',
        target: 'instance-$i',
        result: 'ok',
      );
    }

    final entries = log.list(limit: 1000);
    expect(entries, hasLength(100));
    expect(entries.first.target, 'instance-129', reason: 'newest first');
    expect(entries.last.target, 'instance-30');
  });

  test('the failure log keeps the newest rows up to its bound', () {
    final log = AuthFailureLog(db, clock: () => now, maxRows: 50);
    for (var i = 0; i < 80; i++) {
      now = now.add(const Duration(seconds: 1));
      log.record(InternetAddress('198.51.100.${i + 1}'), 'unauthenticated');
    }
    log.flush();

    final rows = log.aggregates();
    expect(rows, hasLength(50));
    expect(rows.map((r) => r.address), isNot(contains('198.51.100.1')));
    expect(rows.map((r) => r.address), contains('198.51.100.80'));
  });

  test('a flood of failures writes once per flush', () {
    final log = AuthFailureLog(db, clock: () => now);
    for (var i = 0; i < 5000; i++) {
      log.record(InternetAddress('198.51.100.7'), 'unauthenticated');
    }
    expect(log.aggregates(), isEmpty, reason: 'nothing written before flush');
    log.flush();
    expect(log.aggregates().single.count, 5000);
    log.flush();
    expect(log.aggregates().single.count, 5000, reason: 'flushed counts reset');
  });
}
