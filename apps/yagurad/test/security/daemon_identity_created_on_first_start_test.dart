import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/api_server.dart';
import 'package:yagurad/src/api/secure_listener.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/secret_store.dart';

import '../support/cli_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';
import '../support/secure_support.dart';

/// Every byte sequence in which the CA private key could appear.
List<(String, List<int>)> keyForms(EcKeyPair key) {
  final pem = key.privateKeyPem;
  final body = pem
      .split('\n')
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  final der = base64.decode(body);
  final scalar = key.privateKey.d!.toRadixString(16).padLeft(64, '0');
  return [
    ('PEM text', utf8.encode(pem)),
    ('PEM body', utf8.encode(body)),
    ('DER', der),
    (
      'scalar bytes',
      [
        for (var i = 0; i < 64; i += 2)
          int.parse(scalar.substring(i, i + 2), radix: 16),
      ],
    ),
    ('scalar hex', utf8.encode(scalar)),
  ];
}

bool containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  test('first_start', () async {
    final protector = FakeSecretProtector(serviceSid);
    final cli = RunningCli(
      ['--service', '--bind', '127.0.0.1:0'],
      isLocalSystem: () => true,
      secretProtector: protector,
    );
    final (_, port) = await cli.whenListening();

    // The CA is served by the daemon, and its fingerprint is in the log.
    final channel = untrustedChannelTo(port);
    final info = await pb.PairingClient(channel).info(pb.PairingInfoRequest());
    final fingerprint = sha256Hex(info.caCertificateDer);
    expect(cli.errors, contains('CA fingerprint: sha256:$fingerprint'));
    expect(info.caFingerprintSha256, fingerprint);
    final ca = Certificate.parse(Uint8List.fromList(info.caCertificateDer));
    expect(ca.isCa, isTrue);
    expect(ca.isSignedBy(ca), isTrue);
    expect(info.tlsAuthority, startsWith('yagurad-'));

    cli.stop();
    expect(await cli.exit, 0);

    // The CA key sits in the secret store and in no file in plain form.
    final dataDir = p.join(cli.data.path, 'data');
    final db = YaguraDatabase.open(p.join(dataDir, 'yagura.db'));
    addTearDown(db.close);
    final store = DatabaseSecretStore.open(db, protector, serviceMode: true);
    final caKey = EcKeyPair.fromPrivateKeyPem(
      utf8.decode(store.get('daemon:ca_key')!),
    );
    expect(caKey.publicKey.Q, ca.publicKey.Q, reason: 'it is the CA key');
    final files = [
      for (final f in Directory(dataDir).listSync(recursive: true))
        if (f is File) f,
    ];
    expect(files, isNotEmpty);
    for (final file in files) {
      final bytes = file.readAsBytesSync();
      for (final (form, needle) in keyForms(caKey)) {
        expect(
          containsBytes(bytes, needle),
          isFalse,
          reason:
              '${p.relative(file.path, from: dataDir)} holds the CA key '
              'as $form',
        );
      }
    }
  });

  test('server_certificate_rotated', () async {
    final env = TestEnv();
    // The identity is created 701 days ago: the server certificate (2
    // years) now has 29 days left, and is still valid for TLS today.
    final clock = TestClock(
      DateTime.now().toUtc().subtract(const Duration(days: 701)),
    );
    final h = await SecureHarness.start(env, clock: clock);
    final before = h.security.identity.serverCertificate;
    expect(
      before.notAfter.difference(DateTime.now().toUtc()).inDays,
      inInclusiveRange(28, 29),
    );
    final seen = await _serverCertificateOf(h);
    expect(seen, before.sha256);

    // The device pairs today, with the CA it pins; its certificate is valid
    // for the TLS stack, which reads the real time.
    clock.time = DateTime.now().toUtc();
    final device = await h.pair('desk-01');
    await h.server.checkCertificateRotation();

    final after = h.security.identity.serverCertificate;
    expect(after.sha256, isNot(before.sha256));
    expect(after.isSignedBy(h.security.identity.caCertificate), isTrue);
    expect(after.dnsNames, [
      'yagurad-${h.security.identity.daemonId}',
      'localhost',
    ]);
    expect(after.notAfter.difference(clock.time).inDays, greaterThan(700));
    expect(await _serverCertificateOf(h), after.sha256, reason: 'in use');

    // The paired client connects again without pairing: new connection, same
    // pinned CA.
    final again = device.connect();
    final answer = await pb.SystemClient(again).getInfo(pb.GetInfoRequest());
    expect(answer.devMode, isFalse);
  });

  test(
    'a rotation that cannot bind falls back to the old certificate',
    () async {
      final real = DateTime.now().toUtc();
      final clock = TestClock(real.subtract(const Duration(days: 701)));
      var failures = 0;
      final h = await SecureHarness.start(
        TestEnv(),
        clock: clock,
        serve: (daemon, lines) => ApiServer.serveSecure(
          daemon,
          address: InternetAddress.loopbackIPv4,
          port: 0,
          logSink: lines.add,
          binder: (server, address, port, context) async {
            if (failures > 0) {
              failures--;
              throw const SocketException('address in use');
            }
            return SecureListener.bind(server, address, port, context);
          },
        ),
      );
      final before = h.security.identity.serverCertificate.sha256;
      clock.time = real;

      // The bind with the new certificate fails: the old one is served again.
      failures = 1;
      await h.server.checkCertificateRotation();
      expect(h.security.identity.serverCertificate.sha256, before);
      expect(await _serverCertificateOf(h), before);
      expect(
        h.daemon.runtimeNotices.map((n) => n.step),
        contains('server_cert_rotation_failed'),
      );

      // The next attempt works, and the notice goes.
      await h.server.checkCertificateRotation();
      expect(h.security.identity.serverCertificate.sha256, isNot(before));
      expect(
        await _serverCertificateOf(h),
        h.security.identity.serverCertificate.sha256,
      );
      expect(
        h.daemon.runtimeNotices.map((n) => n.step),
        isNot(contains('server_cert_rotation_failed')),
      );
    },
  );

  test('a rotation that cannot bind at all ends the daemon', () async {
    final real = DateTime.now().toUtc();
    final clock = TestClock(real.subtract(const Duration(days: 701)));
    var failures = 0;
    final h = await SecureHarness.start(
      TestEnv(),
      clock: clock,
      serve: (daemon, lines) => ApiServer.serveSecure(
        daemon,
        address: InternetAddress.loopbackIPv4,
        port: 0,
        logSink: lines.add,
        binder: (server, address, port, context) async {
          if (failures > 0) {
            failures--;
            throw const SocketException('address in use');
          }
          return SecureListener.bind(server, address, port, context);
        },
      ),
    );
    clock.time = real;

    failures = 2;
    await h.server.checkCertificateRotation();

    await expectLater(
      h.server.failed,
      throwsA(
        isA<YaguraException>().having(
          (e) => e.reason,
          'reason',
          'listener_unavailable',
        ),
      ),
    );
  });

  test(
    'losing the CA key makes a new identity and revokes the devices',
    () async {
      final env = TestEnv();
      final protector = FakeSecretProtector(serviceSid);
      final first = await SecureHarness.start(env, secretProtector: protector);
      final device = await first.pair('desk-01');
      final oldCa = first.security.identity.caFingerprint;
      final oldId = first.security.identity.daemonId;
      await first.server.close();
      await first.daemon.close();

      // The secret rows are gone (a reset of the store, DPAPI keys lost).
      final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
      db.sqlite.execute('DELETE FROM secrets');
      db.close();

      final second = await SecureHarness.start(env, secretProtector: protector);
      expect(second.security.identity.caFingerprint, isNot(oldCa));
      expect(second.security.identity.daemonId, oldId);
      final devices = second.security.devices.list();
      expect(devices.single.name, 'desk-01');
      expect(devices.single.revoked, isTrue);
      expect(devices.single.revokedBy, 'identity_reset');
      // The old certificate is useless, and a new device can pair.
      expect(second.security.devices.lookup(device.sha256)!.revoked, isTrue);
      await second.pair('desk-02');
    },
  );

  test('the identity survives a restart', () async {
    final env = TestEnv();
    final protector = FakeSecretProtector(serviceSid);
    final first = await SecureHarness.start(env, secretProtector: protector);
    final device = await first.pair('desk-01');
    final ca = first.security.identity.caFingerprint;
    final server = first.security.identity.serverCertificate.sha256;
    await first.server.close();
    await first.daemon.close();

    final second = await SecureHarness.start(env, secretProtector: protector);

    expect(second.security.identity.caFingerprint, ca);
    expect(second.security.identity.serverCertificate.sha256, server);
    // The device that paired before still works, with the pinned CA.
    final reconnected = PairedDevice.forTest(
      second,
      device.name,
      device.deviceId,
      device.key,
      device.certificate,
    );
    expect(
      (await reconnected.system.getInfo(pb.GetInfoRequest())).devMode,
      isFalse,
    );
  });

  test('a dev daemon makes no identity', () async {
    final env = TestEnv();
    final daemon = await env.start();

    expect(daemon.security, isNull);
    final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    addTearDown(db.close);
    expect(db.sqlite.select('SELECT * FROM daemon_identity'), isEmpty);
  });

  test('secret_store_unavailable', () async {
    // The store opens, and refuses the write of the CA key.
    final protector = FlakySecretProtector(serviceSid)..failWrites = true;
    final env = TestEnv();

    await expectLater(
      env.start(
        serviceMode: true,
        secretProtector: protector,
        clock: TestClock().call,
      ),
      failsWith('secret_store_unavailable'),
    );

    // Through the command line: non-zero exit, the reason, no listener.
    final cli = RunningCli(
      ['--service', '--bind', '127.0.0.1:0'],
      isLocalSystem: () => true,
      secretProtector: FlakySecretProtector(serviceSid)..failWrites = true,
    );
    final code = await cli.exit;
    expect(code, isNonZero);
    expect(cli.errors, contains('secret_store_unavailable'));
    expect(cli.listening.isCompleted, isFalse, reason: 'no listener opened');
  });
}

Future<String> _serverCertificateOf(SecureHarness h) async {
  final plain = await Socket.connect(
    InternetAddress.loopbackIPv4,
    h.server.port,
  );
  final socket = await SecureSocket.secure(
    plain,
    host: h.authority,
    context: SecurityContext()
      ..setTrustedCertificatesBytes(utf8.encode(h.caPem)),
    supportedProtocols: ['h2'],
  );
  final fingerprint = sha256Hex(socket.peerCertificate!.der);
  socket.destroy();
  return fingerprint;
}
