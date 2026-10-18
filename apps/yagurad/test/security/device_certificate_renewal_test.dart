import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secure_support.dart';

/// A daemon whose clock started 345 days ago, with `desk-01` paired then:
/// its certificate now ends 20 days from the real time, so TLS (which reads
/// the real time) still accepts it. [TestClock.time] is set to now.
Future<(SecureHarness, PairedDevice)> twentyDaysLeft() async {
  final real = DateTime.now().toUtc();
  final clock = TestClock(real.subtract(const Duration(days: 345)));
  final h = await SecureHarness.start(TestEnv(), clock: clock);
  final device = await h.pair('desk-01');
  clock.time = real;
  return (h, device);
}

Future<pb.EnrollResponse> renew(PairedDevice device, EcKeyPair newKey) =>
    device.pairing.renewCertificate(
      pb.RenewCertificateRequest(
        csrDer: buildCsr(key: newKey, commonName: 'desk-01'),
      ),
    );

PairedDevice renewed(
  SecureHarness h,
  PairedDevice device,
  EcKeyPair key,
  pb.EnrollResponse response,
) => PairedDevice.forTest(
  h,
  device.name,
  device.deviceId,
  key,
  Uint8List.fromList(response.clientCertificateDer),
);

void main() {
  test('renewal_before_expiry', () async {
    final (h, device) = await twentyDaysLeft();
    final oldCert = Certificate.parse(device.certificate);
    expect(oldCert.notAfter.difference(h.clock.time).inDays, 20);

    final newKey = generateKeyPair();
    final response = await renew(device, newKey);

    // A new certificate valid for one year, for the new key, same device.
    final newCert = Certificate.parse(
      Uint8List.fromList(response.clientCertificateDer),
    );
    expect(response.deviceId, device.deviceId);
    expect(newCert.isSignedBy(h.security.identity.caCertificate), isTrue);
    expect(newCert.publicKey.Q, newKey.publicKey.Q);
    expect(newCert.subject.commonName, 'desk-01');
    expect(
      newCert.notAfter.difference(h.clock.time),
      const Duration(days: 365),
    );

    // ListDevices shows one desk-01 with the new expiry.
    final fresh = renewed(h, device, newKey, response);
    final devices = (await fresh.pairing.listDevices(pb.ListDevicesRequest()))
        .devices;
    expect(devices, hasLength(1));
    expect(devices.single.name, 'desk-01');
    expect(
      devices.single.certificateExpiresAt.toDateTime().toUtc(),
      newCert.notAfter,
    );
    expect(
      devices.single.certificates.map((c) => c.sha256),
      unorderedEquals([oldCert.sha256, newCert.sha256]),
    );

    // Both authenticate until the old one expires.
    await pb.InstancesClient(device.connect())
        .listInstances(pb.ListInstancesRequest());
    await fresh.instances.listInstances(pb.ListInstancesRequest());

    h.clock.advance(const Duration(days: 21));
    await expectLater(
      pb.InstancesClient(device.connect())
          .listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'certificate_expired'),
    );
    await fresh.instances.listInstances(pb.ListInstancesRequest());
  });

  test('a second renewal retires the first certificate', () async {
    final (h, device) = await twentyDaysLeft();
    final first = Certificate.parse(device.certificate);
    final secondKey = generateKeyPair();
    final secondResponse = await renew(device, secondKey);
    final second = renewed(h, device, secondKey, secondResponse);

    final thirdKey = generateKeyPair();
    final thirdResponse = await renew(second, thirdKey);
    final third = renewed(h, device, thirdKey, thirdResponse);

    // Only the certificate that renewed and the new one are kept.
    final devices = (await third.pairing.listDevices(pb.ListDevicesRequest()))
        .devices;
    expect(
      devices.single.certificates.map((c) => c.sha256),
      unorderedEquals([
        Certificate.parse(second.certificate).sha256,
        Certificate.parse(third.certificate).sha256,
      ]),
    );
    expect(
      devices.single.certificates.map((c) => c.sha256),
      isNot(contains(first.sha256)),
    );
    await expectLater(
      pb.InstancesClient(device.connect())
          .listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'unauthenticated'),
    );
    await second.instances.listInstances(pb.ListInstancesRequest());
  });

  test('revoking_a_renewed_device', () async {
    final (h, device) = await twentyDaysLeft();
    final admin = await h.pair('admin');
    final newKey = generateKeyPair();
    final fresh = renewed(h, device, newKey, await renew(device, newKey));
    await fresh.instances.listInstances(pb.ListInstancesRequest());

    await admin.pairing.revokeDevice(
      pb.RevokeDeviceRequest(deviceId: device.deviceId),
    );

    for (final certificate in [device, fresh]) {
      await expectLater(
        pb.InstancesClient(certificate.connect())
            .listInstances(pb.ListInstancesRequest()),
        failsWithStatus(StatusCode.unauthenticated, 'device_revoked'),
      );
    }
  });

  test('renewal_without_a_valid_certificate', () async {
    final (h, device) = await twentyDaysLeft();
    final admin = await h.pair('admin');

    // The daemon's clock passes the end of the certificate.
    h.clock.advance(const Duration(days: 21));
    await expectLater(
      renew(device, generateKeyPair()),
      failsWithStatus(StatusCode.unauthenticated, 'certificate_expired'),
    );

    // Without a certificate at all.
    await expectLater(
      pb.PairingClient(h.channelWith()).renewCertificate(
        pb.RenewCertificateRequest(
          csrDer: buildCsr(key: generateKeyPair(), commonName: 'desk-01'),
        ),
      ),
      failsWithStatus(StatusCode.unauthenticated, 'unauthenticated'),
    );

    // No certificate was issued: the device still has its one.
    final devices = (await admin.pairing.listDevices(pb.ListDevicesRequest()))
        .devices;
    final desk = devices.singleWhere((d) => d.name == 'desk-01');
    expect(desk.certificates, hasLength(1));
  });

  test('a revoked device cannot renew', () async {
    final h = await SecureHarness.start(TestEnv());
    final admin = await h.pair('admin');
    final laptop = await h.pair('laptop');
    await admin.pairing.revokeDevice(
      pb.RevokeDeviceRequest(deviceId: laptop.deviceId),
    );

    await expectLater(
      renew(laptop, generateKeyPair()),
      failsWithStatus(StatusCode.unauthenticated, 'device_revoked'),
    );
  });

  test(
    'a renewal request with attributes or a bad signature is refused',
    () async {
      final h = await SecureHarness.start(TestEnv());
      final device = await h.pair('desk-01');

      for (final bad in [
        Uint8List(0),
        Uint8List.fromList([0x30, 0x03, 1, 2, 3]),
      ]) {
        await expectLater(
          device.pairing.renewCertificate(
            pb.RenewCertificateRequest(csrDer: bad),
          ),
          failsWithStatus(StatusCode.invalidArgument, 'csr_invalid'),
        );
      }
      final devices = (await device.pairing.listDevices(
        pb.ListDevicesRequest(),
      )).devices;
      expect(devices.single.certificates, hasLength(1));
    },
  );
}
