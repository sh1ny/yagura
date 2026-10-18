import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/errors.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secure_support.dart';

Uint8List csr(String name) =>
    buildCsr(key: generateKeyPair(), commonName: name);

/// The Enroll call from a connection that trusts the CA but has no client
/// certificate.
Future<pb.EnrollResponse> enroll(
  SecureHarness h,
  String code, {
  String name = 'desk-01',
  Uint8List? request,
  InternetAddress? from,
}) => pb.PairingClient(h.channelWith(from: from)).enroll(
  pb.EnrollRequest(code: code, deviceName: name, csrDer: request ?? csr(name)),
);

Future<List<pb.Device>> devicesOf(PairedDevice device) async =>
    (await device.pairing.listDevices(pb.ListDevicesRequest())).devices;

void main() {
  test('successful_enrollment', () async {
    final h = await SecureHarness.start(TestEnv());
    final code = h.issueCode();
    expect(code, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{10}$')));

    final deviceKey = generateKeyPair();
    final response = await pb.PairingClient(h.channelWith()).enroll(
      pb.EnrollRequest(
        code: code,
        deviceName: 'desk-01',
        csrDer: buildCsr(key: deviceKey, commonName: 'ignored'),
      ),
    );

    // A client certificate signed by the CA, valid for one year, for the key
    // of the request, named by the daemon.
    final cert = Certificate.parse(
      Uint8List.fromList(response.clientCertificateDer),
    );
    expect(cert.isSignedBy(h.security.identity.caCertificate), isTrue);
    expect(cert.subject.commonName, 'desk-01');
    expect(cert.publicKey.Q, deviceKey.publicKey.Q);
    expect(cert.extendedKeyUsage, ['1.3.6.1.5.5.7.3.2']);
    expect(cert.notAfter.difference(h.clock.time), const Duration(days: 365));
    expect(h.clock.time.difference(cert.notBefore), const Duration(hours: 1));
    expect(response.caCertificateDer, h.security.identity.caCertificate.der);

    // The device is listed, and the certificate works.
    final device = PairedDevice.forTest(
      h,
      'desk-01',
      response.deviceId,
      deviceKey,
      Uint8List.fromList(response.clientCertificateDer),
    );
    final devices = await devicesOf(device);
    expect(devices.map((d) => d.name), ['desk-01']);
    expect(devices.single.id, response.deviceId);
    expect(devices.single.isCaller, isTrue);
    expect(devices.single.revoked, isFalse);
    expect(devices.single.certificates.single.sha256, cert.sha256);

    // The code is spent.
    await expectLater(
      enroll(h, code, name: 'second'),
      failsWithStatus(StatusCode.permissionDenied, 'pairing_code_invalid'),
    );
    expect(await devicesOf(device), hasLength(1));
  });

  test('expired_or_reused_code', () async {
    final h = await SecureHarness.start(TestEnv());
    final witness = await h.pair('witness');

    // A code older than 10 minutes.
    final old = h.issueCode();
    h.clock.advance(const Duration(minutes: 10, seconds: 1));
    await expectLater(
      enroll(h, old),
      failsWithStatus(StatusCode.permissionDenied, 'pairing_code_invalid'),
    );

    // A code that was already used.
    final once = h.issueCode();
    await enroll(h, once, name: 'first');
    await expectLater(
      enroll(h, once, name: 'again'),
      failsWithStatus(StatusCode.permissionDenied, 'pairing_code_invalid'),
    );

    // A code that was never issued.
    await expectLater(
      enroll(h, 'ABCDEFGHJK'),
      failsWithStatus(StatusCode.permissionDenied, 'pairing_code_invalid'),
    );

    expect(
      (await devicesOf(witness)).map((d) => d.name),
      unorderedEquals(['witness', 'first']),
      reason: 'no device was created by a refused code',
    );
  });

  test('brute_force_from_one_address', () async {
    final h = await SecureHarness.start(TestEnv());
    final witness = await h.pair('witness');
    final code = h.issueCode();

    for (var i = 0; i < 5; i++) {
      await expectLater(
        enroll(h, 'WRONG0000$i'),
        failsWithStatus(StatusCode.permissionDenied, 'pairing_code_invalid'),
      );
    }
    // The sixth call is throttled, whatever the code.
    await expectLater(
      enroll(h, code),
      failsWithStatus(StatusCode.resourceExhausted, 'pairing_throttled'),
    );

    // The active code still works from another address.
    final other = await enroll(
      h,
      code,
      name: 'elsewhere',
      from: InternetAddress('127.0.0.2'),
    );
    expect(other.deviceId, isNotEmpty);
    expect(
      (await devicesOf(witness)).map((d) => d.name),
      contains('elsewhere'),
    );

    // The block lasts 10 minutes.
    h.clock.advance(const Duration(minutes: 5));
    await expectLater(
      enroll(h, h.issueCode()),
      failsWithStatus(StatusCode.resourceExhausted, 'pairing_throttled'),
    );
    h.clock.advance(const Duration(minutes: 5, seconds: 1));
    expect(
      (await enroll(h, h.issueCode(), name: 'later')).deviceId,
      isNotEmpty,
    );
  });

  test('IPv6 addresses are throttled per /64', () async {
    final h = await SecureHarness.start(TestEnv());
    h.issueCode();
    String? wrong(String address) {
      try {
        h.security.pairing.enroll(
          code: 'WRONG00000',
          deviceName: 'x',
          csrDer: Uint8List(0),
          address: InternetAddress(address),
        );
      } on YaguraException catch (e) {
        return e.reason;
      }
      return null;
    }

    for (var i = 1; i <= 5; i++) {
      expect(wrong('2001:db8:0:1::$i'), 'pairing_code_invalid');
    }
    // Another address of the same /64 is blocked; another /64 is not.
    expect(wrong('2001:db8:0:1:ffff::9'), 'pairing_throttled');
    expect(wrong('2001:db8:0:2::1'), 'pairing_code_invalid');
  });

  test('the throttle forgets the oldest address at its bound', () async {
    final h = await SecureHarness.start(TestEnv());
    h.issueCode();
    String? wrong(InternetAddress address) {
      try {
        h.security.pairing.enroll(
          code: 'WRONG00000',
          deviceName: 'x',
          csrDer: Uint8List(0),
          address: address,
        );
      } on YaguraException catch (e) {
        return e.reason;
      }
      return null;
    }

    final first = InternetAddress('10.0.0.1');
    for (var i = 0; i < 5; i++) {
      expect(wrong(first), 'pairing_code_invalid');
    }
    expect(wrong(first), 'pairing_throttled');
    // 10,000 other addresses make one wrong guess each.
    for (var i = 0; i < 10000; i++) {
      wrong(
        InternetAddress('11.${i ~/ 65025}.${i % 65025 ~/ 255}.${i % 255 + 1}'),
      );
    }
    // The first address had the oldest window: it is forgotten.
    expect(wrong(first), 'pairing_code_invalid');
  });

  test('distributed_guessing', () async {
    final h = await SecureHarness.start(TestEnv());
    final code = h.issueCode();

    // 50 wrong codes from 50 addresses, one each: no address is throttled.
    for (var i = 0; i < 50; i++) {
      await expectLater(
        () async => h.security.pairing.enroll(
          code: 'WRONG${i.toString().padLeft(5, '0')}',
          deviceName: 'guesser',
          csrDer: csr('guesser'),
          address: InternetAddress('10.1.${i ~/ 200}.${i % 200 + 1}'),
        ),
        throwsA(
          isA<YaguraException>().having(
            (e) => e.reason,
            'reason',
            'pairing_code_invalid',
          ),
        ),
        reason: 'guess $i',
      );
    }

    // The active code is dead, even for the right guess.
    await expectLater(
      enroll(h, code),
      failsWithStatus(StatusCode.permissionDenied, 'pairing_code_invalid'),
    );
    // The admin issues a new one.
    expect((await enroll(h, h.issueCode())).deviceId, isNotEmpty);
  });
}
