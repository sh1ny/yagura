import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secure_support.dart';

Future<List<pb.Device>> list(PairedDevice device) async =>
    (await device.pairing.listDevices(pb.ListDevicesRequest())).devices;

void main() {
  test('revoke_another_device', () async {
    final h = await SecureHarness.start(TestEnv());
    final desk = await h.pair('desk-01');
    final laptop = await h.pair('laptop');
    h.clock.advance(const Duration(minutes: 3));

    final revoked = await desk.pairing.revokeDevice(
      pb.RevokeDeviceRequest(deviceId: laptop.deviceId),
    );
    expect(revoked.revoked, isTrue);

    final devices = await list(desk);
    final entry = devices.singleWhere((d) => d.name == 'laptop');
    expect(entry.revoked, isTrue);
    expect(entry.revokedAt.toDateTime().toUtc(), h.clock.time);
    expect(entry.revokedByDeviceId, desk.deviceId);
    final self = devices.singleWhere((d) => d.name == 'desk-01');
    expect(self.revoked, isFalse);
    expect(self.isCaller, isTrue);
    expect(entry.isCaller, isFalse);
  });

  test('revoking_the_last_device', () async {
    final h = await SecureHarness.start(TestEnv());
    final only = await h.pair('desk-01');

    await expectLater(
      only.pairing.revokeDevice(
        pb.RevokeDeviceRequest(deviceId: only.deviceId),
      ),
      failsWithStatus(StatusCode.failedPrecondition, 'last_device'),
    );
    // Still enrolled and working.
    expect((await list(only)).single.revoked, isFalse);
  });

  test('a device may revoke itself while another remains', () async {
    final h = await SecureHarness.start(TestEnv());
    final desk = await h.pair('desk-01');
    final laptop = await h.pair('laptop');

    await desk.pairing.revokeDevice(
      pb.RevokeDeviceRequest(deviceId: desk.deviceId),
    );

    await expectLater(
      desk.instances.listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'device_revoked'),
    );
    expect(
      (await list(laptop)).singleWhere((d) => d.name == 'desk-01').revoked,
      isTrue,
    );
  });

  test('revoked devices do not count as remaining', () async {
    final h = await SecureHarness.start(TestEnv());
    final desk = await h.pair('desk-01');
    final laptop = await h.pair('laptop');
    await desk.pairing.revokeDevice(
      pb.RevokeDeviceRequest(deviceId: laptop.deviceId),
    );

    await expectLater(
      desk.pairing.revokeDevice(
        pb.RevokeDeviceRequest(deviceId: desk.deviceId),
      ),
      failsWithStatus(StatusCode.failedPrecondition, 'last_device'),
    );
  });

  test('an unknown device id is not found', () async {
    final h = await SecureHarness.start(TestEnv());
    final desk = await h.pair('desk-01');

    await expectLater(
      desk.pairing.revokeDevice(pb.RevokeDeviceRequest(deviceId: 'nope')),
      failsWithStatus(StatusCode.notFound, 'device_not_found'),
    );
  });

  test('devices are listed with their address and last seen time', () async {
    final h = await SecureHarness.start(TestEnv());
    final desk = await h.pair('desk-01');
    h.clock.advance(const Duration(hours: 2));
    await desk.instances.listInstances(pb.ListInstancesRequest());

    final entry = (await list(desk)).single;
    expect(entry.lastAddress, '127.0.0.1');
    expect(entry.lastSeenAt.toDateTime().toUtc(), h.clock.time);
    expect(
      entry.enrolledAt.toDateTime().toUtc().isBefore(h.clock.time),
      isTrue,
    );
    expect(
      entry.certificateExpiresAt.toDateTime().toUtc(),
      Certificate.parse(desk.certificate).notAfter,
    );
  });

  test('a device is renamed, and the name is checked', () async {
    final h = await SecureHarness.start(TestEnv());
    final desk = await h.pair('desk-01');

    final renamed = await desk.pairing.renameDevice(
      pb.RenameDeviceRequest(deviceId: desk.deviceId, name: 'office'),
    );
    expect(renamed.name, 'office');
    expect((await list(desk)).single.name, 'office');

    for (final bad in ['', 'x' * 65]) {
      await expectLater(
        desk.pairing.renameDevice(
          pb.RenameDeviceRequest(deviceId: desk.deviceId, name: bad),
        ),
        failsWithStatus(StatusCode.invalidArgument, 'device_name_invalid'),
      );
    }
  });

  test('the 101st device cannot enroll', () async {
    final h = await SecureHarness.start(TestEnv());
    final desk = await h.pair('desk-00');
    for (var i = 1; i < 100; i++) {
      h.security.pairing.enroll(
        code: h.issueCode(),
        deviceName: 'device-$i',
        csrDer: buildCsr(key: generateKeyPair(), commonName: 'x'),
        address: InternetAddress.loopbackIPv4,
      );
    }
    expect(await list(desk), hasLength(100));

    await expectLater(
      h.pair('one-too-many'),
      failsWithStatus(StatusCode.resourceExhausted, 'too_many_devices'),
    );
    // A revoked one frees a place.
    final other = (await list(desk)).firstWhere((d) => !d.isCaller);
    await desk.pairing.revokeDevice(pb.RevokeDeviceRequest(deviceId: other.id));
    await h.pair('fits-now');
  });

  test(
    'health reports the server certificate and the unbuilt components',
    () async {
      final h = await SecureHarness.start(TestEnv());
      final device = await h.pair('desk-01');

      final health = await device.system.getHealth(pb.GetHealthRequest());

      expect(
        health.serverCertNotAfter.toDateTime().toUtc(),
        h.security.identity.serverCertificate.notAfter,
      );
      expect(
        health.notBuilt,
        unorderedEquals(['firewall', 'service_accounts', 'steam_account']),
      );
      expect(health.secretStoreOk, isTrue);
      expect(health.adminChannelOk, isFalse);
      expect(health.serviceAccountsOk, isFalse);
    },
  );
}
