import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagura_pki/src/certificate.dart';
import 'package:yagura_pki/src/csr.dart';
import 'package:yagura_pki/src/der.dart';
import 'package:yagura_pki/src/errors.dart';
import 'package:yagura_pki/src/keys.dart';
import 'package:yagura_pki/src/oids.dart';

final notBefore = DateTime.utc(2026, 10, 18, 11);
final year = notBefore.add(const Duration(days: 365));

void main() {
  final caKey = generateKeyPair();
  final caDer = issueCaCertificate(
    key: caKey,
    commonName: 'Yagura CA test-host',
    notBefore: notBefore,
    notAfter: DateTime.utc(2046, 10, 18, 11),
  );
  final ca = Certificate.parse(caDer);

  group('the CA certificate', () {
    test('parses back with the CA profile', () {
      expect(ca.isCa, isTrue);
      expect(ca.pathLength, 0);
      expect(ca.keyUsage, {KeyUsage.keyCertSign, KeyUsage.cRLSign});
      expect(ca.extendedKeyUsage, isEmpty);
      expect(ca.subject.commonName, 'Yagura CA test-host');
      expect(ca.issuer.commonName, 'Yagura CA test-host');
      expect(ca.notBefore, notBefore);
      expect(ca.notAfter, DateTime.utc(2046, 10, 18, 11));
      expect(ca.publicKey.Q, caKey.publicKey.Q);
    });

    test('is signed by its own key and by no other', () {
      expect(ca.isSignedBy(ca), isTrue);
      final other = Certificate.parse(
        issueCaCertificate(
          key: generateKeyPair(),
          commonName: 'Yagura CA test-host',
          notBefore: notBefore,
          notAfter: year,
        ),
      );
      expect(ca.isSignedBy(other), isFalse, reason: 'same name, other key');
    });

    test('has a fingerprint of the DER', () {
      expect(ca.sha256, hasLength(64));
      expect(ca.sha256, sha256Hex(caDer));
    });
  });

  group('the server certificate', () {
    late EcKeyPair serverKey;
    late Certificate server;

    setUp(() {
      serverKey = generateKeyPair();
      server = Certificate.parse(
        issueServerCertificate(
          issuerKey: caKey,
          issuer: ca,
          subjectKey: serverKey.publicKey,
          commonName: 'yagurad-abc123',
          dnsNames: const ['yagurad-abc123', 'localhost'],
          notBefore: notBefore,
          notAfter: notBefore.add(const Duration(days: 730)),
        ),
      );
    });

    test('has the server profile', () {
      expect(server.isCa, isFalse);
      expect(server.keyUsage, {KeyUsage.digitalSignature});
      expect(server.extendedKeyUsage, [Oid.serverAuth]);
      expect(server.dnsNames, ['yagurad-abc123', 'localhost']);
      expect(server.subject.commonName, 'yagurad-abc123');
      expect(server.issuer.commonName, 'Yagura CA test-host');
      expect(server.publicKey.Q, serverKey.publicKey.Q);
    });

    test('is signed by the CA', () {
      expect(server.isSignedBy(ca), isTrue);
      expect(server.isSignedBy(server), isFalse);
    });

    test('fails verification when a byte of it changes', () {
      final der = Uint8List.fromList(server.der);
      // The subject common name sits inside the signed part.
      final at = der.indexOf('y'.codeUnitAt(0), 100);
      der[at] ^= 1;
      expect(Certificate.parse(der).isSignedBy(ca), isFalse);
    });
  });

  group('the client certificate', () {
    test('takes only the key from the request and the rest from the CA', () {
      final deviceKey = generateKeyPair();
      final csr = CertificationRequest.parse(
        buildCsr(key: deviceKey, commonName: 'attacker CN=CA'),
      );
      final client = Certificate.parse(
        issueClientCertificate(
          issuerKey: caKey,
          issuer: ca,
          subjectKey: csr.publicKey,
          commonName: 'desk-01',
          notBefore: notBefore,
          notAfter: year,
        ),
      );

      expect(client.subject.commonName, 'desk-01');
      expect(client.isCa, isFalse);
      expect(client.pathLength, isNull);
      expect(client.keyUsage, {KeyUsage.digitalSignature});
      expect(client.extendedKeyUsage, [Oid.clientAuth]);
      expect(client.dnsNames, isEmpty);
      expect(client.publicKey.Q, deviceKey.publicKey.Q);
      expect(client.isSignedBy(ca), isTrue);
      expect(
        client.notAfter.difference(client.notBefore),
        const Duration(days: 365),
      );
    });

    test('has a random 128-bit serial, different every time', () {
      final serials = {
        for (var i = 0; i < 20; i++)
          Certificate.parse(
            issueClientCertificate(
              issuerKey: caKey,
              issuer: ca,
              subjectKey: generateKeyPair().publicKey,
              commonName: 'd',
              notBefore: notBefore,
              notAfter: year,
            ),
          ).serial,
      };
      expect(serials, hasLength(20));
      expect(
        serials.every((s) => s.bitLength >= 120 && s.bitLength <= 127),
        isTrue,
      );
    });

    test('validity is checked against a time', () {
      final client = Certificate.parse(
        issueClientCertificate(
          issuerKey: caKey,
          issuer: ca,
          subjectKey: generateKeyPair().publicKey,
          commonName: 'd',
          notBefore: notBefore,
          notAfter: year,
        ),
      );
      expect(client.validAt(notBefore), isTrue);
      expect(client.validAt(year), isTrue);
      expect(client.validAt(year.add(const Duration(seconds: 1))), isFalse);
      expect(
        client.validAt(notBefore.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });

  group('certificate parsing refuses', () {
    test('trailing bytes, truncation and garbage', () {
      for (final bad in [
        Uint8List.fromList([...caDer, 0]),
        caDer.sublist(0, caDer.length - 3),
        Uint8List.fromList([1, 2, 3]),
        Uint8List(0),
      ]) {
        expect(
          () => Certificate.parse(bad),
          throwsA(
            isA<PkiException>().having(
              (e) => e.reason,
              'reason',
              'certificate_invalid',
            ),
          ),
        );
      }
    });

    test('a certificate that is not version 3', () {
      final parts = parseDer(caDer).sequence;
      final tbs = parts[0].sequence;
      final v1 = derSequence([
        derSequence(tbs.skip(1).map((e) => e.encoded)),
        parts[1].encoded,
        parts[2].encoded,
      ]);
      expect(() => Certificate.parse(v1), throwsA(isA<PkiException>()));
    });
  });

  group('private keys', () {
    test('round trip through SEC1 PEM', () {
      final key = generateKeyPair();
      final pem = key.privateKeyPem;
      expect(pem, startsWith('-----BEGIN EC PRIVATE KEY-----\n'));
      final back = EcKeyPair.fromPrivateKeyPem(pem);
      expect(back.privateKey.d, key.privateKey.d);
      expect(back.publicKey.Q, key.publicKey.Q);
    });

    test('a zero scalar is refused', () {
      final zero = pemEncode(
        'EC PRIVATE KEY',
        derSequence([derSmallInteger(1), derOctetString(Uint8List(32))]),
      );
      expect(() => decodePrivateKeyPem(zero), throwsFormatException);
    });
  });

  group('signatures', () {
    test('verify, and fail for another message, key or malformed value', () {
      final key = generateKeyPair();
      final message = Uint8List.fromList([1, 2, 3]);
      final signature = signEcdsaSha256(key.privateKey, message);
      expect(verifyEcdsaSha256(key.publicKey, message, signature), isTrue);
      expect(verifyEcdsaSha256(key.publicKey, [1, 2, 4], signature), isFalse);
      expect(
        verifyEcdsaSha256(generateKeyPair().publicKey, message, signature),
        isFalse,
      );
      expect(verifyEcdsaSha256(key.publicKey, message, [1, 2, 3]), isFalse);
      expect(
        verifyEcdsaSha256(
          key.publicKey,
          message,
          derSequence([derSmallInteger(0), derSmallInteger(1)]),
        ),
        isFalse,
        reason: 'r = 0',
      );
    });
  });

  group('certificate signing requests', () {
    final key = generateKeyPair();
    final good = buildCsr(key: key, commonName: 'd');

    Uint8List rebuild({
      Uint8List? attributes,
      Uint8List? spki,
      Uint8List? algorithm,
      EcKeyPair? signer,
    }) {
      final info = derSequence([
        derSmallInteger(0),
        encodeCommonName('d'),
        spki ?? encodePublicKey(key.publicKey),
        attributes ?? derContext(0, const []),
      ]);
      final signature = signEcdsaSha256((signer ?? key).privateKey, info);
      return derSequence([
        info,
        algorithm ?? derSequence([derOid(Oid.ecdsaWithSha256)]),
        derBitString(signature),
      ]);
    }

    void refused(String name, Uint8List Function() make) {
      test('refuse $name', () {
        expect(
          () => CertificationRequest.parse(make()),
          throwsA(
            isA<PkiException>().having(
              (e) => e.reason,
              'reason',
              'csr_invalid',
            ),
          ),
        );
      });
    }

    test('parse back with the key and the name', () {
      final csr = CertificationRequest.parse(good);
      expect(csr.publicKey.Q, key.publicKey.Q);
      expect(csr.commonName, 'd');
    });

    test(
      'a rebuilt request is accepted, so each refusal differs by one thing',
      () {
        expect(() => CertificationRequest.parse(rebuild()), returnsNormally);
      },
    );

    refused('attributes', () {
      // An extensionRequest attribute asking for CA:true.
      final attribute = derSequence([
        derOid('1.2.840.113549.1.9.14'),
        derSet([
          derSequence([
            derSequence([
              derOid(Oid.basicConstraints),
              derOctetString(derSequence([derBoolean(true)])),
            ]),
          ]),
        ]),
      ]);
      return rebuild(attributes: derContext(0, [attribute]));
    });
    refused('a missing attributes field', () {
      final info = derSequence([
        derSmallInteger(0),
        encodeCommonName('d'),
        encodePublicKey(key.publicKey),
      ]);
      return derSequence([
        info,
        derSequence([derOid(Oid.ecdsaWithSha256)]),
        derBitString(signEcdsaSha256(key.privateKey, info)),
      ]);
    });
    refused('a bad signature', () {
      final changed = Uint8List.fromList(good);
      changed[changed.length - 2] ^= 0xff;
      return changed;
    });
    refused(
      'a signature by another key',
      () => rebuild(signer: generateKeyPair()),
    );
    refused('another curve', () {
      final spki = derSequence([
        derSequence([derOid(Oid.ecPublicKey), derOid('1.3.132.0.34')]),
        derBitString([0x04, ...List<int>.filled(96, 1)]),
      ]);
      return rebuild(spki: spki);
    });
    refused('another key type', () {
      final spki = derSequence([
        derSequence([derOid('1.2.840.113549.1.1.1'), derTlv(0x05, const [])]),
        derBitString(List<int>.filled(64, 1)),
      ]);
      return rebuild(spki: spki);
    });
    refused('a point that is not on the curve', () {
      final spki = derSequence([
        derSequence([derOid(Oid.ecPublicKey), derOid(Oid.prime256v1)]),
        derBitString([0x04, ...List<int>.filled(64, 2)]),
      ]);
      return rebuild(spki: spki);
    });
    refused('a compressed point', () {
      final spki = derSequence([
        derSequence([derOid(Oid.ecPublicKey), derOid(Oid.prime256v1)]),
        derBitString([0x02, ...List<int>.filled(32, 2)]),
      ]);
      return rebuild(spki: spki);
    });
    refused(
      'another signature algorithm',
      () => rebuild(algorithm: derSequence([derOid('1.2.840.10045.4.3.3')])),
    );
    refused('trailing bytes', () => Uint8List.fromList([...good, 0]));
    refused(
      'garbage',
      () => Uint8List.fromList(List<int>.generate(50, (i) => i)),
    );
    refused('an oversized request', () => Uint8List(maxCsrBytes + 1));
    refused('an empty input', () => Uint8List(0));
  });
}
