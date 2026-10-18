import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
// ignore: implementation_imports
import 'package:grpc/src/client/channel.dart' show ClientChannelBase;
import 'package:test/test.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/reflection.dart';
import 'package:yagurad/src/security/method_access.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secure_support.dart';

/// Every method of every service in the descriptor set, as
/// `yagura.v1.Instances/ListInstances`.
List<String> allMethods() {
  final index = DescriptorIndex(pb.yaguraDescriptorSet);
  return [
    for (final service in index.services)
      for (final method in index.methods[service]!) '$service/$method',
  ];
}

/// Calls every method that is not exempt on [channel] and returns the
/// failures by method. A method that answered is mapped to null.
Future<Map<String, GrpcError?>> callEveryMethod(
  ClientChannelBase channel,
) async {
  final out = <String, GrpcError?>{};
  for (final method in allMethods()) {
    if (exemptMethods.contains(method)) continue;
    try {
      await rawCall(channel, '/$method', timeout: const Duration(seconds: 5));
      out[method] = null;
    } on GrpcError catch (e) {
      out[method] = e;
    }
  }
  return out;
}

void main() {
  test('call_without_a_client_certificate', () async {
    final h = await SecureHarness.start(TestEnv());
    final anonymous = pb.InstancesClient(h.channelWith());

    await expectLater(
      anonymous.listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'unauthenticated'),
    );

    // The attempt is in the authentication-failure log with the address.
    h.security.failures.flush();
    final rows = h.security.failures.aggregates();
    expect(rows, hasLength(1));
    expect(rows.single.address, '127.0.0.1');
    expect(rows.single.count, 1);
    expect(rows.single.lastReason, 'unauthenticated');
  });

  test('every method of the descriptor set is classified', () {
    final methods = allMethods();
    expect(methods, isNotEmpty);
    expect(
      methods.where((m) => !methodAccess.containsKey(m)),
      isEmpty,
      reason: 'a method added without a class would be open or unaudited',
    );
    expect(
      methodAccess.keys.where(
        // v1alpha is served but is not in the descriptor set.
        (m) => !methods.contains(m) && !m.startsWith('grpc.reflection.v1alpha'),
      ),
      isEmpty,
      reason: 'the table names a method that does not exist',
    );
    expect(exemptMethods, {
      'yagura.v1.Pairing/Info',
      'yagura.v1.Pairing/Enroll',
    });
  });

  test(
    'every method that is not exempt rejects a call without a certificate',
    () async {
      final h = await SecureHarness.start(TestEnv());
      final anonymous = h.channelWith();

      final results = await callEveryMethod(anonymous);
      expect(results, isNotEmpty);
      for (final MapEntry(:key, :value) in results.entries) {
        expect(value, isNotNull, reason: '$key answered');
        expect(value!.code, StatusCode.unauthenticated, reason: key);
        expect(errorDetailOf(value)?.reason, 'unauthenticated', reason: key);
      }
      // The exempt ones are served.
      final info = await pb.PairingClient(anonymous)
          .info(pb.PairingInfoRequest());
      expect(info.caCertificateDer, isNotEmpty);
    },
  );

  test('reflection v1alpha needs a certificate too', () async {
    final h = await SecureHarness.start(TestEnv());
    const path =
        '/grpc.reflection.v1alpha.ServerReflection/'
        'ServerReflectionInfo';

    await expectLater(
      rawCall(h.channelWith(), path),
      throwsA(
        isA<GrpcError>().having(
          (e) => e.code,
          'code',
          StatusCode.unauthenticated,
        ),
      ),
    );
    final other = await h.pair('desk-01');
    // With a certificate the gate lets it through to the handler, which
    // answers or fails with something other than UNAUTHENTICATED.
    try {
      await rawCall(other.channel, path);
    } on GrpcError catch (e) {
      expect(e.code, isNot(StatusCode.unauthenticated));
    }
  });

  test('revoked_device', () async {
    final h = await SecureHarness.start(TestEnv());
    final admin = await h.pair('admin');
    final laptop = await h.pair('laptop');

    // The laptop holds an open stream.
    final closed = Completer<Object?>();
    laptop.instances
        .watchInstances(pb.WatchInstancesRequest())
        .listen(
          (_) {},
          onError: closed.complete,
          onDone: () => closed.complete(null),
          cancelOnError: true,
        );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(closed.isCompleted, isFalse, reason: 'the stream is open');

    final clock = Stopwatch()..start();
    await admin.pairing.revokeDevice(
      pb.RevokeDeviceRequest(deviceId: laptop.deviceId),
    );

    // Its open stream ends within 5 s.
    await closed.future.timeout(const Duration(seconds: 5));
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));

    // Its next call fails with the reason.
    await expectLater(
      laptop.instances.listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'device_revoked'),
    );
    // A new connection does not help.
    await expectLater(
      pb.InstancesClient(laptop.connect())
          .listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'device_revoked'),
    );
    // The admin is unaffected.
    await admin.instances.listInstances(pb.ListInstancesRequest());
  });

  test('method_added_without_an_exemption', () async {
    final h = await SecureHarness.start(TestEnv());
    // Signed by the daemon CA, enrolled by nobody.
    final (certificate, key) = h.unenrolledCertificate();
    final stranger = h.channelWith(certificate: certificate, key: key);

    final results = await callEveryMethod(stranger);
    for (final MapEntry(:key, :value) in results.entries) {
      expect(value, isNotNull, reason: '$key answered');
      expect(value!.code, StatusCode.unauthenticated, reason: key);
    }
  });

  test('an expired certificate is refused by the gate itself', () async {
    final h = await SecureHarness.start(TestEnv());
    final device = await h.pair('desk-01');
    await device.instances.listInstances(pb.ListInstancesRequest());

    // The daemon's clock passes the certificate's end; the TLS stack, which
    // reads the real time, still lets the handshake through.
    h.clock.advance(const Duration(days: 366));
    await expectLater(
      pb.InstancesClient(device.connect())
          .listInstances(pb.ListInstancesRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'certificate_expired'),
    );
  });

  test('certificate_from_another_ca', () async {
    final h = await SecureHarness.start(TestEnv());
    await h.pair('witness');
    final now = h.clock.time;
    final otherKey = generateKeyPair();
    final other = Certificate.parse(
      issueCaCertificate(
        key: otherKey,
        commonName: 'Another CA',
        notBefore: now.subtract(const Duration(hours: 1)),
        notAfter: now.add(const Duration(days: 365)),
      ),
    );
    final clientKey = generateKeyPair();
    final foreign = issueClientCertificate(
      issuerKey: otherKey,
      issuer: other,
      subjectKey: clientKey.publicKey,
      commonName: 'witness',
      notBefore: now.subtract(const Duration(hours: 1)),
      notAfter: now.add(const Duration(days: 365)),
    );
    h.security.failures.flush();
    final before = h.security.failures.aggregates().length;

    final channel = h.channelWith(certificate: foreign, key: clientKey);
    final error = await failureOf(
      pb.InstancesClient(channel).listInstances(
        pb.ListInstancesRequest(),
        options: CallOptions(timeout: const Duration(seconds: 5)),
      ),
    );
    // The handshake is refused: the failure is a transport one, and the gate
    // never saw the call.
    expect(error, isA<GrpcError>());
    expect(error.code, isNot(StatusCode.unauthenticated));
    expect(errorDetailOf(error), isNull);
    h.security.failures.flush();
    expect(h.security.failures.aggregates(), hasLength(before));
  });

  test(
    'a certificate chained through a device certificate is refused',
    () async {
      final h = await SecureHarness.start(TestEnv());
      final device = await h.pair('desk-01');
      final deviceCert = Certificate.parse(device.certificate);
      final leafKey = generateKeyPair();
      final now = h.clock.time;
      final forged = issueClientCertificate(
        issuerKey: device.key,
        issuer: deviceCert,
        subjectKey: leafKey.publicKey,
        commonName: 'desk-01',
        notBefore: now.subtract(const Duration(hours: 1)),
        notAfter: now.add(const Duration(days: 30)),
      );
      final channel = h.channelWith(
        certificate: forged,
        key: leafKey,
        chain: [device.certificate],
      );

      final error = await failureOf(
        pb.InstancesClient(channel).listInstances(
          pb.ListInstancesRequest(),
          options: CallOptions(timeout: const Duration(seconds: 5)),
        ),
      );
      expect(errorDetailOf(error), isNull, reason: 'refused by TLS');
    },
  );

  test('a plaintext client cannot talk to the secure listener', () async {
    final h = await SecureHarness.start(TestEnv());
    final plain = ClientChannel(
      InternetAddress.loopbackIPv4.address,
      port: h.server.port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        connectTimeout: Duration(seconds: 5),
      ),
    );
    addTearDown(plain.terminate);

    await expectLater(
      pb.SystemClient(plain).getInfo(
        pb.GetInfoRequest(),
        options: CallOptions(timeout: const Duration(seconds: 5)),
      ),
      throwsA(isA<GrpcError>()),
    );
  });
}
