import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' show GrpcError;
import 'package:yagura_desktop/src/credentials.dart';
import 'package:yagura_desktop/src/grpc_transport.dart';
import 'package:yagura_desktop/src/transport.dart';
import 'package:yagura_pki/yagura_pki.dart';

import 'support/fake_world.dart';
import 'support/pairing_ui.dart';

void main() {
  testWidgets('fingerprint_mismatch_at_pairing', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    // A different CA answers where the pairing string pins another one.
    final impostor = FakeHost(id: 'evil');
    host.presentedCa = impostor.caDer;
    await world.pump(tester);

    await pairThroughTheUi(tester, host.pairingString());

    // It aborts before the code is sent and shows both fingerprints.
    final error = pairingError(tester);
    expect(error, contains('fingerprint_mismatch'));
    expect(error, contains(host.fingerprint));
    expect(error, contains(impostor.fingerprint));
    expect(host.enrollRequests, isEmpty);
    expect(host.channels, [(pinned: false, authority: null)]);
    // No daemon was added and no key was left behind.
    expect(daemonCard('alpha'), findsNothing);
    expect(world.store.records, isEmpty);
    expect(world.keychain.entries, isEmpty);
  });

  testWidgets('daemon_ca_matches_stored_ca', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.prePair(host);
    await world.pump(tester);
    expect(world.stateOf(tester, 'alpha'), 'connected');

    // A restart: the client reconnects against the stored CA.
    host.daemon.kill();
    await settleAll(tester);
    host.daemon.restart();
    world.reconnectDelay.release();
    await settleAll(tester);

    expect(world.stateOf(tester, 'alpha'), 'connected');
    // No prompt, and every connection used the stored CA as its only root
    // with the daemon's fixed name.
    expect(find.byType(AlertDialog), findsNothing);
    expect(world.dialer.secureOpens, hasLength(2));
    for (final open in world.dialer.secureOpens) {
      expect(open.credentials.caDer, host.caDer);
      expect(open.authority, 'yagurad-alpha');
    }
  });

  testWidgets('a_different_ca_is_refused_and_re_pairing_is_offered', (
    tester,
  ) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.prePair(host);
    // The address now answers with another CA (the daemon's was reset).
    final reset = FakeHost(id: 'alpha');
    world.dialer.hosts[host.key] = reset;
    await world.pump(tester);

    expect(world.stateOf(tester, 'alpha'), 'offline');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daemon:alpha:detail')))
          .data,
      contains('server_ca_mismatch'),
    );
    expect(find.byKey(const ValueKey('daemon:alpha:repair')), findsOneWidget);
  });

  group('the TLS context', () {
    late EcKeyPair caKey;
    late Uint8List caDer;
    late Certificate ca;

    setUp(() {
      caKey = generateKeyPair();
      final start = DateTime.now().subtract(const Duration(days: 1));
      caDer = issueCaCertificate(
        key: caKey,
        commonName: 'Yagura CA',
        notBefore: start,
        notAfter: start.add(const Duration(days: 30)),
      );
      ca = Certificate.parse(caDer);
    });

    /// A TLS server whose certificate carries the name [name], signed by
    /// [issuerKey]. It requests a client certificate like the daemon does.
    Future<SecureServerSocket> serve(
      String name, {
      EcKeyPair? issuerKey,
      Certificate? issuer,
    }) async {
      final key = generateKeyPair();
      final start = DateTime.now().subtract(const Duration(days: 1));
      final certificate = issueServerCertificate(
        issuerKey: issuerKey ?? caKey,
        issuer: issuer ?? ca,
        subjectKey: key.publicKey,
        commonName: name,
        dnsNames: [name],
        notBefore: start,
        notAfter: start.add(const Duration(days: 30)),
      );
      final context = SecurityContext()
        ..setTrustedCertificatesBytes(certificatePemBytes(caDer))
        ..useCertificateChainBytes(certificatePemBytes(certificate))
        ..usePrivateKeyBytes(key.privateKeyPem.codeUnits);
      return SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
        requestClientCertificate: true,
      );
    }

    /// What the client sees when it connects with [context]: the server
    /// socket's accepted peer certificate, or the handshake error.
    Future<({Object? error, bool clientCertificatePresented})> connect(
      SecureServerSocket server,
      SecurityContext context,
      String authority,
    ) async {
      final presented = Completer<bool>();
      server.listen(
        (socket) {
          presented.complete(socket.peerCertificate != null);
          socket.destroy();
        },
        onError: (Object _) {
          if (!presented.isCompleted) presented.complete(false);
        },
      );
      try {
        final raw = await Socket.connect(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        final socket = await SecureSocket.secure(
          raw,
          host: authority,
          context: context,
        );
        final seen = await presented.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        socket.destroy();
        return (error: null, clientCertificatePresented: seen);
      } on Object catch (e) {
        return (error: e, clientCertificatePresented: false);
      }
    }

    test(
      'trusts_the_pinned_ca_by_the_fixed_name_and_sends_its_certificate',
      () async {
        final server = await serve('yagurad-alpha');
        addTearDown(server.close);
        final key = generateKeyPair();
        final start = DateTime.now().subtract(const Duration(hours: 1));
        final clientCertificate = issueClientCertificate(
          issuerKey: caKey,
          issuer: ca,
          subjectKey: key.publicKey,
          commonName: 'laptop',
          notBefore: start,
          notAfter: start.add(const Duration(days: 30)),
        );
        final context = pinnedSecurityContext(
          caDer: caDer,
          certificateDer: clientCertificate,
          keyPem: key.privateKeyPem,
        );

        final result = await connect(server, context, 'yagurad-alpha');

        expect(result.error, isNull);
        expect(result.clientCertificatePresented, isTrue);
      },
    );

    test('refuses_a_server_from_another_ca', () async {
      final otherKey = generateKeyPair();
      final start = DateTime.now().subtract(const Duration(days: 1));
      final otherDer = issueCaCertificate(
        key: otherKey,
        commonName: 'Other CA',
        notBefore: start,
        notAfter: start.add(const Duration(days: 30)),
      );
      final server = await serve(
        'yagurad-alpha',
        issuerKey: otherKey,
        issuer: Certificate.parse(otherDer),
      );
      addTearDown(server.close);

      final result = await connect(
        server,
        pinnedSecurityContext(caDer: caDer),
        'yagurad-alpha',
      );

      expect(result.error, isA<HandshakeException>());
    });

    test('refuses_the_right_ca_under_another_name', () async {
      final server = await serve('yagurad-other');
      addTearDown(server.close);

      final result = await connect(
        server,
        pinnedSecurityContext(caDer: caDer),
        'yagurad-alpha',
      );

      expect(result.error, isA<HandshakeException>());
    });

    DeviceCredentials credentialsFor() {
      final key = generateKeyPair();
      final start = DateTime.now().subtract(const Duration(hours: 1));
      return DeviceCredentials(
        caDer: caDer,
        certificateDer: issueClientCertificate(
          issuerKey: caKey,
          issuer: ca,
          subjectKey: key.publicKey,
          commonName: 'laptop',
          notBefore: start,
          notAfter: start.add(const Duration(days: 30)),
        ),
        keyPem: key.privateKeyPem,
      );
    }

    Future<DaemonCallException> callOver(SecureServerSocket server) async {
      server.listen((socket) => socket.destroy(), onError: (Object _) {});
      final transport = GrpcTransport.secure(
        host: '127.0.0.1',
        port: server.port,
        authority: 'yagurad-alpha',
        credentials: credentialsFor(),
      );
      addTearDown(transport.close);
      try {
        await transport.getInfo();
      } on DaemonCallException catch (e) {
        return e;
      }
      fail('the call should have failed');
    }

    test('a_server_from_another_ca_is_server_ca_mismatch_over_grpc', () async {
      final otherKey = generateKeyPair();
      final start = DateTime.now().subtract(const Duration(days: 1));
      final otherDer = issueCaCertificate(
        key: otherKey,
        commonName: 'Other CA',
        notBefore: start,
        notAfter: start.add(const Duration(days: 30)),
      );
      final server = await serve(
        'yagurad-alpha',
        issuerKey: otherKey,
        issuer: Certificate.parse(otherDer),
      );
      addTearDown(server.close);

      final error = await callOver(server);

      expect(error.code, 14);
      expect(error.reason, 'server_ca_mismatch');
    });

    test('the_right_ca_under_another_name_is_server_ca_mismatch', () async {
      final server = await serve('yagurad-other');
      addTearDown(server.close);

      final error = await callOver(server);

      expect(error.reason, 'server_ca_mismatch');
    });

    test('an_unreachable_server_is_not_a_ca_mismatch', () async {
      final server = await serve('yagurad-alpha');
      final port = server.port;
      await server.close();
      final transport = GrpcTransport.secure(
        host: '127.0.0.1',
        port: port,
        authority: 'yagurad-alpha',
        credentials: credentialsFor(),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.getInfo(),
        throwsA(
          isA<DaemonCallException>().having(
            (e) => e.reason,
            'reason',
            isNot('server_ca_mismatch'),
          ),
        ),
      );
    });

    test('the_message_text_is_only_a_fallback', () {
      final text = GrpcError.unavailable(
        'Error connecting: CERTIFICATE_VERIFY_FAILED',
      );
      final plain = GrpcError.unavailable('connection refused');
      expect(toCallException(text).reason, 'server_ca_mismatch');
      expect(toCallException(plain).reason, isEmpty);
      expect(
        toCallException(plain, certificateRejected: true).reason,
        'server_ca_mismatch',
      );
      // A daemon's own answer is never relabelled.
      expect(
        toCallException(
          GrpcError.unauthenticated('x'),
          certificateRejected: true,
        ).reason,
        isEmpty,
      );
    });
  });
}

List<int> certificatePemBytes(List<int> der) => certificatePem(der).codeUnits;
