import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secure_support.dart';

Future<List<pb.AuditEntry>> audit(PairedDevice device) async =>
    (await device.system.listAudit(pb.ListAuditRequest(pageSize: 200))).entries;

/// A daemon with the Valheim plugin and a paired `desk-01`.
Future<(SecureHarness, PairedDevice)> start() async {
  final env = TestEnv()..installValheim();
  final h = await SecureHarness.start(env);
  return (h, await h.pair('desk-01'));
}

void main() {
  test('instance_deletion_audited', () async {
    final (h, desk) = await start();
    await createValheim(h.daemon, name: 'A');
    final b = await createValheim(h.daemon, name: 'B', ports: {'game': 2556});
    h.clock.advance(const Duration(minutes: 1));

    final op = await desk.instances.deleteInstance(
      pb.DeleteInstanceRequest(
        instanceId: b.id,
        expectedRevision: Int64(b.revision),
      ),
    );
    await h.daemon.operations.whenDone(op.id);

    final entries = await audit(desk);
    final entry = entries.singleWhere(
      (e) => e.method == 'yagura.v1.Instances/DeleteInstance',
    );
    expect(entry.deviceId, desk.deviceId);
    expect(entry.target, b.id);
    expect(entry.result, 'ok');
    expect(entry.remoteAddress, '127.0.0.1');
    expect(entry.at.toDateTime().toUtc(), h.clock.time);

    // Reads are not audited; a refused mutation records its reason.
    await desk.instances.listInstances(pb.ListInstancesRequest());
    final refused = await failureOf(
      desk.instances.deleteInstance(
        pb.DeleteInstanceRequest(instanceId: 'no-such-instance'),
      ),
    );
    final after = await audit(desk);
    expect(after.where((e) => e.method.endsWith('/ListInstances')), isEmpty);
    expect(after.first.method, 'yagura.v1.Instances/DeleteInstance');
    expect(after.first.target, 'no-such-instance');
    expect(after.first.result, errorDetailOf(refused)!.reason);
    expect(after.first.result, isNot('ok'));
  });

  test('pairing and revocation are audited', () async {
    final (h, desk) = await start();
    final laptop = await h.pair('laptop');
    await desk.pairing.revokeDevice(
      pb.RevokeDeviceRequest(deviceId: laptop.deviceId),
    );

    final entries = await audit(desk);
    expect(
      entries.map((e) => (e.method, e.target, e.result)),
      containsAll([
        ('yagura.v1.Pairing/Enroll', desk.deviceId, 'ok'),
        ('yagura.v1.Pairing/Enroll', laptop.deviceId, 'ok'),
        ('yagura.v1.Pairing/RevokeDevice', laptop.deviceId, 'ok'),
      ]),
    );
    expect(
      entries.firstWhere((e) => e.method.endsWith('/RevokeDevice')).deviceId,
      desk.deviceId,
    );
  });

  test('scanner_flood', () async {
    final (h, desk) = await start();
    final instance = await createValheim(h.daemon, name: 'B');
    final op = await desk.instances.deleteInstance(
      pb.DeleteInstanceRequest(
        instanceId: instance.id,
        expectedRevision: Int64(instance.revision),
      ),
    );
    await h.daemon.operations.whenDone(op.id);
    final before = await audit(desk);

    // 100,000 unauthenticated calls from 3 addresses.
    final scanners = [
      for (final last in [11, 12, 13]) InternetAddress('203.0.113.$last'),
    ];
    for (var i = 0; i < 100000; i++) {
      h.security.failures.record(scanners[i % 3], 'unauthenticated');
    }
    // And a real one from another address.
    await expectLater(
      pb.InstancesClient(h.channelWith(from: InternetAddress('127.0.0.9')))
          .listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'unauthenticated'),
    );
    h.security.failures.flush();

    final rows = {
      for (final r in h.security.failures.aggregates()) r.address: r,
    };
    expect(
      rows.keys,
      unorderedEquals([for (final s in scanners) s.address, '127.0.0.9']),
    );
    expect(rows['203.0.113.11']!.count, 33334);
    expect(rows['203.0.113.12']!.count, 33333);
    expect(rows['203.0.113.13']!.count, 33333);
    expect(rows['127.0.0.9']!.count, 1);

    // The earlier deletion is still there, and nothing else was added.
    final after = await audit(desk);
    expect(
      after.map((e) => (e.method, e.target)),
      before.map((e) => (e.method, e.target)),
    );
    expect(
      after.where((e) => e.method == 'yagura.v1.Instances/DeleteInstance'),
      hasLength(1),
    );
  });

  test('failures in a later window are separate rows', () async {
    final (h, _) = await start();
    final scanner = InternetAddress('203.0.113.11');
    h.security.failures.record(scanner, 'unauthenticated');
    h.clock.advance(const Duration(minutes: 10));
    h.security.failures.record(scanner, 'device_revoked');
    h.security.failures.flush();

    final rows = h.security.failures.aggregates();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.count), [1, 1]);
    expect(rows.last.lastReason, 'device_revoked');
    expect(
      rows.last.windowStart.difference(rows.first.windowStart),
      const Duration(minutes: 10),
    );
  });

  test('secret_set_without_value_in_audit', () async {
    final (h, desk) = await start();
    final instance = await createValheim(h.daemon);
    const password = 'correct-horse-battery-9';

    await desk.instances.setSecret(
      pb.SetSecretRequest(
        instanceId: instance.id,
        key: 'password',
        value: password,
        expectedRevision: Int64(instance.revision),
      ),
    );

    final entries = await audit(desk);
    final entry = entries.firstWhere(
      (e) => e.method == 'yagura.v1.Instances/SetSecret',
    );
    expect(entry.deviceId, desk.deviceId);
    expect(entry.target, contains(instance.id));
    expect(entry.target, contains('password'));
    expect(entry.result, 'ok');

    for (final e in entries) {
      expect('$e', isNot(contains(password)));
    }
    expect(h.logLines.join('\n'), isNot(contains(password)));
    // Nor in any file of the data directory.
    for (final file in Directory(h.env.data).listSync(recursive: true)) {
      if (file is! File) continue;
      expect(
        String.fromCharCodes(file.readAsBytesSync()),
        isNot(contains(password)),
        reason: file.path,
      );
    }
  });

  test('skipping the snapshot is audited with the device', () async {
    final (h, desk) = await start();
    final instance = await createInstalled(h.daemon);

    final op = await desk.instances.update(
      pb.LifecycleRequest(instanceId: instance.id, skipSnapshot: true),
    );
    await h.daemon.operations.whenDone(op.id);

    final entry = (await audit(desk))
        .firstWhere((e) => e.method == 'yagura.v1.Instances/Update');
    expect(entry.deviceId, desk.deviceId);
    expect(entry.target, contains(instance.id));
    expect(entry.target, contains('skip_snapshot'));
    expect(entry.result, 'ok');
  });
}
