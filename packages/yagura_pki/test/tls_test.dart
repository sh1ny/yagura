import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagura_pki/src/certificate.dart';
import 'package:yagura_pki/src/keys.dart';

/// Certificates built by the package, put through Dart's TLS stack.

const authority = 'yagurad-test';

final now = DateTime.now().toUtc();
final hourAgo = now.subtract(const Duration(hours: 1));
final yearOn = now.add(const Duration(days: 365));

class Ca {
  Ca([String name = 'Yagura CA test']) {
    key = generateKeyPair();
    der = issueCaCertificate(
      key: key,
      commonName: name,
      notBefore: hourAgo,
      notAfter: now.add(const Duration(days: 365 * 20)),
    );
    cert = Certificate.parse(der);
  }

  late final EcKeyPair key;
  late final Uint8List der;
  late final Certificate cert;

  String get pem => certificatePem(der);

  /// A server certificate for [authority] and its key.
  (Uint8List, EcKeyPair) server({DateTime? notAfter, DateTime? notBefore}) {
    final serverKey = generateKeyPair();
    return (
      issueServerCertificate(
        issuerKey: key,
        issuer: cert,
        subjectKey: serverKey.publicKey,
        commonName: authority,
        dnsNames: const [authority, 'localhost'],
        notBefore: notBefore ?? hourAgo,
        notAfter: notAfter ?? now.add(const Duration(days: 730)),
      ),
      serverKey,
    );
  }

  (Uint8List, EcKeyPair) client({DateTime? notAfter, DateTime? notBefore}) {
    final deviceKey = generateKeyPair();
    return (
      issueClientCertificate(
        issuerKey: key,
        issuer: cert,
        subjectKey: deviceKey.publicKey,
        commonName: 'desk-01',
        notBefore: notBefore ?? hourAgo,
        notAfter: notAfter ?? yearOn,
      ),
      deviceKey,
    );
  }
}

/// A TLS echo server that asks for a client certificate.
Future<SecureServerSocket> echoServer({
  required List<List<int>> chain,
  required EcKeyPair key,
  required String trustedRootPem,
  bool requireClientCertificate = false,
  void Function(X509Certificate? peer)? onPeer,
}) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(
      utf8.encode([for (final c in chain) certificatePem(c)].join()),
    )
    ..usePrivateKeyBytes(utf8.encode(key.privateKeyPem))
    ..setTrustedCertificatesBytes(utf8.encode(trustedRootPem));
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    context,
    requestClientCertificate: !requireClientCertificate,
    requireClientCertificate: requireClientCertificate,
  );
  server.listen((socket) {
    onPeer?.call(socket.peerCertificate);
    socket.listen(
      (data) => socket.add(data),
      onError: (Object _) {},
      onDone: socket.destroy,
    );
  }, onError: (Object _) {});
  addTearDown(server.close);
  return server;
}

/// Connects, sends a byte and returns the echo; null when TLS refused the
/// connection at any point. [certificate] and [privateKey] make the client
/// present a certificate.
Future<String?> exchange(
  int port, {
  required String trustedRootPem,
  Uint8List? certificate,
  EcKeyPair? privateKey,
  List<List<int>> chain = const [],
}) async {
  final context = SecurityContext()
    ..setTrustedCertificatesBytes(utf8.encode(trustedRootPem));
  if (certificate != null) {
    context
      ..useCertificateChainBytes(
        utf8.encode(
          [
            for (final c in [certificate, ...chain]) certificatePem(c),
          ].join(),
        ),
      )
      ..usePrivateKeyBytes(utf8.encode(privateKey!.privateKeyPem));
  }
  final plain = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final SecureSocket secure;
  try {
    secure = await SecureSocket.secure(
      plain,
      host: authority,
      context: context,
    );
  } on Object {
    plain.destroy();
    return null;
  }
  final echo = Completer<String?>();
  secure.listen(
    (data) {
      if (!echo.isCompleted) echo.complete(utf8.decode(data));
    },
    onError: (Object _) {
      if (!echo.isCompleted) echo.complete(null);
    },
    onDone: () {
      if (!echo.isCompleted) echo.complete(null);
    },
  );
  secure.add(utf8.encode('x'));
  final result = await echo.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => null,
  );
  secure.destroy();
  return result;
}

void main() {
  late Ca ca;

  setUp(() => ca = Ca());

  test(
    'a client trusting the CA completes a handshake with the server',
    () async {
      final (serverCert, serverKey) = ca.server();
      final server = await echoServer(
        chain: [serverCert],
        key: serverKey,
        trustedRootPem: ca.pem,
      );

      expect(await exchange(server.port, trustedRootPem: ca.pem), 'x');
    },
  );

  test(
    'the server certificate verifies for the fixed name and for localhost',
    () async {
      final (serverCert, serverKey) = ca.server();
      final server = await echoServer(
        chain: [serverCert],
        key: serverKey,
        trustedRootPem: ca.pem,
      );
      final context = SecurityContext()
        ..setTrustedCertificatesBytes(utf8.encode(ca.pem));
      for (final host in [authority, 'localhost']) {
        final plain = await Socket.connect(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        final secure = await SecureSocket.secure(
          plain,
          host: host,
          context: context,
        );
        secure.destroy();
      }
      final plain = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      await expectLater(
        SecureSocket.secure(plain, host: 'other-name', context: context),
        throwsA(isA<HandshakeException>()),
      );
      plain.destroy();
    },
  );

  test('a client refuses a server certificate from another CA', () async {
    final other = Ca('Another CA');
    final (serverCert, serverKey) = other.server();
    final server = await echoServer(
      chain: [serverCert],
      key: serverKey,
      trustedRootPem: other.pem,
    );

    expect(await exchange(server.port, trustedRootPem: ca.pem), isNull);
  });

  test('a client refuses an expired server certificate', () async {
    final (serverCert, serverKey) = ca.server(
      notBefore: now.subtract(const Duration(days: 800)),
      notAfter: now.subtract(const Duration(days: 70)),
    );
    final server = await echoServer(
      chain: [serverCert],
      key: serverKey,
      trustedRootPem: ca.pem,
    );

    expect(await exchange(server.port, trustedRootPem: ca.pem), isNull);
  });

  test(
    'a connection without a client certificate completes in request mode',
    () async {
      final (serverCert, serverKey) = ca.server();
      X509Certificate? seen;
      final peer = Completer<void>();
      final server = await echoServer(
        chain: [serverCert],
        key: serverKey,
        trustedRootPem: ca.pem,
        onPeer: (cert) {
          seen = cert;
          peer.complete();
        },
      );

      expect(await exchange(server.port, trustedRootPem: ca.pem), 'x');
      await peer.future;
      expect(seen, isNull);
    },
  );

  test(
    'a client certificate from the CA is accepted and its DER is exposed',
    () async {
      final (serverCert, serverKey) = ca.server();
      final (clientCert, clientKey) = ca.client();
      X509Certificate? seen;
      final peer = Completer<void>();
      final server = await echoServer(
        chain: [serverCert],
        key: serverKey,
        trustedRootPem: ca.pem,
        onPeer: (cert) {
          seen = cert;
          peer.complete();
        },
      );

      expect(
        await exchange(
          server.port,
          trustedRootPem: ca.pem,
          certificate: clientCert,
          privateKey: clientKey,
        ),
        'x',
      );
      await peer.future;
      expect(sha256Hex(seen!.der), Certificate.parse(clientCert).sha256);
    },
  );

  test('a client certificate from another CA is refused', () async {
    final (serverCert, serverKey) = ca.server();
    final other = Ca('Another CA');
    final (clientCert, clientKey) = other.client();
    final server = await echoServer(
      chain: [serverCert],
      key: serverKey,
      trustedRootPem: ca.pem,
    );

    expect(
      await exchange(
        server.port,
        trustedRootPem: ca.pem,
        certificate: clientCert,
        privateKey: clientKey,
      ),
      isNull,
    );
  });

  test('an expired client certificate is refused', () async {
    final (serverCert, serverKey) = ca.server();
    final (clientCert, clientKey) = ca.client(
      notBefore: now.subtract(const Duration(days: 400)),
      notAfter: now.subtract(const Duration(days: 35)),
    );
    final server = await echoServer(
      chain: [serverCert],
      key: serverKey,
      trustedRootPem: ca.pem,
    );

    expect(
      await exchange(
        server.port,
        trustedRootPem: ca.pem,
        certificate: clientCert,
        privateKey: clientKey,
      ),
      isNull,
    );
  });

  test(
    'TLS refuses a chain that uses a client certificate as an issuer',
    () async {
      // A control first: the same shape of chain with the CA as issuer is fine.
      final (serverCert, serverKey) = ca.server();
      final control = await echoServer(
        chain: [serverCert],
        key: serverKey,
        trustedRootPem: ca.pem,
      );
      expect(await exchange(control.port, trustedRootPem: ca.pem), 'x');

      // A device holds a CA-signed client certificate and its key; it signs a
      // "server" certificate for the daemon's name with that key.
      final (clientDer, deviceKey) = ca.client();
      final deviceCert = Certificate.parse(clientDer);
      final leafKey = generateKeyPair();
      final forged = issueServerCertificate(
        issuerKey: deviceKey,
        issuer: deviceCert,
        subjectKey: leafKey.publicKey,
        commonName: authority,
        dnsNames: const [authority, 'localhost'],
        notBefore: hourAgo,
        notAfter: yearOn,
      );
      expect(Certificate.parse(forged).isSignedBy(deviceCert), isTrue);
      final attacker = await echoServer(
        chain: [forged, clientDer],
        key: leafKey,
        trustedRootPem: ca.pem,
      );

      expect(await exchange(attacker.port, trustedRootPem: ca.pem), isNull);
    },
  );

  test(
    'TLS refuses a client certificate chain through a client certificate',
    () async {
      final (serverCert, serverKey) = ca.server();
      final (clientDer, deviceKey) = ca.client();
      final deviceCert = Certificate.parse(clientDer);
      final leafKey = generateKeyPair();
      final forged = issueClientCertificate(
        issuerKey: deviceKey,
        issuer: deviceCert,
        subjectKey: leafKey.publicKey,
        commonName: 'forged',
        notBefore: hourAgo,
        notAfter: yearOn,
      );
      final server = await echoServer(
        chain: [serverCert],
        key: serverKey,
        trustedRootPem: ca.pem,
      );

      expect(
        await exchange(
          server.port,
          trustedRootPem: ca.pem,
          certificate: forged,
          privateKey: leafKey,
          chain: [clientDer],
        ),
        isNull,
      );
    },
  );
}
