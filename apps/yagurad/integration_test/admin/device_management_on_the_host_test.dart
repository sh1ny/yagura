@Tags(['windows'])
library;

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../../test/support/admin_support.dart';
import '../../test/support/api_support.dart';
import '../../test/support/daemon_support.dart';
import '../../test/support/secure_support.dart';

final _code = RegExp(r'code=([0-9A-Z]{10})');

void main() {
  test('last_device_revoked_on_the_host', () async {
    final h = await AdminHarness.start(TestEnv());
    final secure = await SecureHarness.start(h.env, daemon: h.daemon);
    final desk = await secure.pair('desk-01');
    // From the device itself the last device cannot be revoked.
    await expectLater(
      desk.pairing.revokeDevice(
        pb.RevokeDeviceRequest(deviceId: desk.deviceId),
      ),
      failsWithStatus(StatusCode.failedPrecondition, 'last_device'),
    );

    final result = await h.run(['devices', 'revoke', 'desk-01']);

    expect(result.code, 0, reason: '$result');
    expect(result.out, contains('desk-01'));
    expect(h.daemon.security!.devices.get(desk.deviceId)!.revoked, isTrue);
    expect(
      h.daemon.security!.devices.get(desk.deviceId)!.revokedBy,
      'host-admin',
    );
    await expectLater(
      desk.instances.listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'device_revoked'),
    );
    // A new code from `yagurad pair` enrolls another device.
    final pair = await h.run(['pair']);
    final laptop = await secure.pair(
      'laptop',
      code: _code.firstMatch(pair.out)![1],
    );
    expect(
      (await laptop.pairing.listDevices(pb.ListDevicesRequest())).devices
          .where((d) => !d.revoked)
          .map((d) => d.name),
      ['laptop'],
    );
    // The revocation is in the audit log under the host's name.
    final entry = h.daemon.security!.audit.list().singleWhere(
      (e) => e.method == 'admin/devices.revoke',
    );
    expect(entry.deviceId, 'host-admin');
    expect(entry.target, desk.deviceId);
    expect(entry.result, 'ok');
  });

  test('devices_list_shows_every_device_with_its_state', () async {
    final h = await AdminHarness.start(TestEnv());
    final secure = await SecureHarness.start(h.env, daemon: h.daemon);
    final desk = await secure.pair('desk-01');
    await secure.pair('laptop');
    await h.run(['devices', 'revoke', desk.deviceId]);

    final result = await h.run(['devices', 'list']);

    expect(result.code, 0, reason: '$result');
    final lines = result.out.trim().split('\n');
    expect(lines.firstWhere((l) => l.contains('laptop')), contains('active'));
    expect(
      lines.firstWhere((l) => l.contains('desk-01')),
      allOf(contains('revoked'), contains('host-admin')),
    );
    expect(result.out, contains(desk.deviceId));
  });

  test('an_unknown_device_is_not_found', () async {
    final h = await AdminHarness.start(TestEnv());

    final result = await h.run(['devices', 'revoke', 'nobody']);

    expect(result.code, isNot(0));
    expect(result.err, contains('device_not_found'));
    expect(
      h.daemon.security!.audit.list().single.result,
      'device_not_found',
      reason: 'a refused change is audited with its reason',
    );
  });

  test('two_devices_with_one_name_are_told_apart_by_id', () async {
    final h = await AdminHarness.start(TestEnv());
    final secure = await SecureHarness.start(h.env, daemon: h.daemon);
    final first = await secure.pair('desk');
    final second = await secure.pair('desk');

    final ambiguous = await h.run(['devices', 'revoke', 'desk']);
    expect(ambiguous.code, isNot(0));
    expect(ambiguous.err, contains('device_ambiguous'));
    expect(ambiguous.err, contains(first.deviceId));
    expect(ambiguous.err, contains(second.deviceId));
    expect(h.daemon.security!.devices.activeCount, 2);

    final byId = await h.run(['devices', 'revoke', first.deviceId]);
    expect(byId.code, 0, reason: '$byId');
    expect(h.daemon.security!.devices.activeCount, 1);
    // The name now names the one device left.
    expect((await h.run(['devices', 'revoke', 'desk'])).code, 0);
    expect(h.daemon.security!.devices.activeCount, 0);
  });

  test('a_device_command_without_its_argument_is_a_usage_error', () async {
    final h = await AdminHarness.start(TestEnv());

    for (final arguments in [
      ['devices'],
      ['devices', 'revoke'],
      ['devices', 'frobnicate'],
      ['devices', 'list', 'extra'],
    ]) {
      final result = await h.run(arguments);
      expect(result.code, 64, reason: '$arguments: $result');
      expect(result.err, contains('usage: yagurad devices'));
    }
    expect(h.daemon.security!.audit.list(), isEmpty);
  });
}
