import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';
import 'errors.dart';
import 'keys.dart';
import 'oids.dart';

/// Key usage bits (RFC 5280 4.2.1.3) the profiles use.
enum KeyUsage {
  digitalSignature(0),
  keyCertSign(5),
  cRLSign(6);

  const KeyUsage(this.bit);

  final int bit;
}

/// The profile of a certificate Yagura issues (design D1).
enum CertificateProfile {
  /// `CA:true, pathLen:0`, keyCertSign and cRLSign.
  ca,

  /// `CA:false`, digitalSignature, serverAuth and DNS names.
  server,

  /// `CA:false`, digitalSignature and clientAuth.
  client,
}

/// A parsed X.509 v3 certificate.
class Certificate {
  Certificate._({
    required this.der,
    required this.tbs,
    required this.serial,
    required this.issuer,
    required this.subject,
    required this.notBefore,
    required this.notAfter,
    required this.publicKey,
    required this.signature,
    required this.isCa,
    required this.pathLength,
    required this.keyUsage,
    required this.extendedKeyUsage,
    required this.dnsNames,
  });

  final Uint8List der;

  /// The `tbsCertificate` exactly as encoded: the bytes the signature covers.
  final Uint8List tbs;
  final BigInt serial;
  final Name issuer;
  final Name subject;
  final DateTime notBefore;
  final DateTime notAfter;
  final ECPublicKey publicKey;

  /// The DER `SEQUENCE {r, s}`.
  final Uint8List signature;

  /// `basicConstraints` says `CA:true`.
  final bool isCa;
  final int? pathLength;
  final Set<KeyUsage> keyUsage;
  final List<String> extendedKeyUsage;
  final List<String> dnsNames;

  /// Lower-case hex SHA-256 of the DER: the identity Yagura keeps of a
  /// certificate.
  String get sha256 => sha256Hex(der);

  /// Whether [time] is within `[notBefore, notAfter]`.
  bool validAt(DateTime time) =>
      !time.isBefore(notBefore) && !time.isAfter(notAfter);

  /// Whether [issuer] named this certificate's issuer and its key made the
  /// signature.
  bool isSignedBy(Certificate issuer) =>
      this.issuer.der.length == issuer.subject.der.length &&
      _same(this.issuer.der, issuer.subject.der) &&
      verifyEcdsaSha256(issuer.publicKey, tbs, signature);

  /// Reads [der]; throws [PkiException] `certificate_invalid` when it is not
  /// a certificate this package understands.
  static Certificate parse(Uint8List der) {
    try {
      return _parseCertificate(der);
    } on DerException catch (e) {
      throw PkiException('certificate_invalid', e.message);
    } on FormatException catch (e) {
      throw PkiException('certificate_invalid', e.message);
    }
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A distinguished name. Only text attributes are kept.
class Name {
  Name._(this.der, this.attributes);

  /// The encoded `Name`.
  final Uint8List der;

  /// `(oid, value)` of each attribute in order.
  final List<(String, String)> attributes;

  /// The first common name, or null.
  String? get commonName {
    for (final (oid, value) in attributes) {
      if (oid == Oid.commonName) return value;
    }
    return null;
  }

  static Name parse(Der name) {
    final attributes = <(String, String)>[];
    for (final rdn in name.sequence) {
      if (rdn.tag != Tag.set) throw const DerException('malformed name');
      for (final attribute in rdn.children) {
        final parts = attribute.sequence;
        if (parts.length != 2) throw const DerException('malformed name');
        attributes.add((parts[0].oid, parts[1].text));
      }
    }
    return Name._(name.encoded, attributes);
  }
}

/// The encoded `Name` holding one common name.
Uint8List encodeCommonName(String commonName) => derSequence([
  derSet([
    derSequence([derOid(Oid.commonName), derUtf8String(commonName)]),
  ]),
]);

final _sha256WithEcdsa = derSequence([derOid(Oid.ecdsaWithSha256)]);

/// A random positive 128-bit serial number.
BigInt randomSerial([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) source.nextInt(256)];
  bytes[0] &= 0x7f;
  bytes[0] |= 0x40; // never short, never zero
  return bytesToBigInt(bytes);
}

Uint8List _keyUsageExtension(Set<KeyUsage> usages) {
  var high = 0;
  for (final u in usages) {
    if (u.bit > high) high = u.bit;
  }
  final bytes = List<int>.filled(high ~/ 8 + 1, 0);
  for (final u in usages) {
    bytes[u.bit ~/ 8] |= 0x80 >> (u.bit % 8);
  }
  return derBitString(bytes, unusedBits: 7 - high % 8);
}

Uint8List _extension(String oid, Uint8List value, {required bool critical}) =>
    derSequence([
      derOid(oid),
      if (critical) derBoolean(true),
      derOctetString(value),
    ]);

/// Builds and signs a certificate. [issuerKey] signs; [issuerName] is the
/// issuer's encoded subject (the subject itself for a CA).
Uint8List _issue({
  required CertificateProfile profile,
  required EcKeyPair issuerKey,
  required Uint8List issuerName,
  required ECPublicKey subjectKey,
  required String commonName,
  required DateTime notBefore,
  required DateTime notAfter,
  required List<String> dnsNames,
  BigInt? serial,
  SecureRandom? random,
}) {
  if (!notAfter.isAfter(notBefore)) {
    throw ArgumentError('notAfter must be after notBefore');
  }
  final extensions = <Uint8List>[
    _extension(
      Oid.basicConstraints,
      profile == CertificateProfile.ca
          ? derSequence([derBoolean(true), derSmallInteger(0)])
          : derSequence(const []),
      critical: true,
    ),
    _extension(
      Oid.keyUsage,
      _keyUsageExtension(
        profile == CertificateProfile.ca
            ? {KeyUsage.keyCertSign, KeyUsage.cRLSign}
            : {KeyUsage.digitalSignature},
      ),
      critical: true,
    ),
    if (profile == CertificateProfile.server) ...[
      _extension(
        Oid.extendedKeyUsage,
        derSequence([derOid(Oid.serverAuth)]),
        critical: false,
      ),
      _extension(
        Oid.subjectAltName,
        derSequence([
          for (final name in dnsNames)
            derTlv(contextTag(2, constructed: false), name.codeUnits),
        ]),
        critical: false,
      ),
    ],
    if (profile == CertificateProfile.client)
      _extension(
        Oid.extendedKeyUsage,
        derSequence([derOid(Oid.clientAuth)]),
        critical: false,
      ),
  ];
  final tbs = derSequence([
    derContext(0, [derSmallInteger(2)]),
    derInteger(serial ?? randomSerial()),
    _sha256WithEcdsa,
    issuerName,
    derSequence([derTime(notBefore), derTime(notAfter)]),
    encodeCommonName(commonName),
    encodePublicKey(subjectKey),
    derContext(3, [derSequence(extensions)]),
  ]);
  final signature = signEcdsaSha256(issuerKey.privateKey, tbs, random: random);
  return derSequence([tbs, _sha256WithEcdsa, derBitString(signature)]);
}

/// A self-signed CA certificate for [key].
Uint8List issueCaCertificate({
  required EcKeyPair key,
  required String commonName,
  required DateTime notBefore,
  required DateTime notAfter,
  BigInt? serial,
  SecureRandom? random,
}) => _issue(
  profile: CertificateProfile.ca,
  issuerKey: key,
  issuerName: encodeCommonName(commonName),
  subjectKey: key.publicKey,
  commonName: commonName,
  notBefore: notBefore,
  notAfter: notAfter,
  dnsNames: const [],
  serial: serial,
  random: random,
);

/// A server certificate for [subjectKey] with [dnsNames], signed by
/// [issuerKey] as [issuer].
Uint8List issueServerCertificate({
  required EcKeyPair issuerKey,
  required Certificate issuer,
  required ECPublicKey subjectKey,
  required String commonName,
  required List<String> dnsNames,
  required DateTime notBefore,
  required DateTime notAfter,
  BigInt? serial,
  SecureRandom? random,
}) => _issue(
  profile: CertificateProfile.server,
  issuerKey: issuerKey,
  issuerName: issuer.subject.der,
  subjectKey: subjectKey,
  commonName: commonName,
  notBefore: notBefore,
  notAfter: notAfter,
  dnsNames: dnsNames,
  serial: serial,
  random: random,
);

/// A client certificate for [subjectKey] (taken from a request), signed by
/// [issuerKey] as [issuer]. The subject and extensions are the profile's; the
/// request contributes only the key.
Uint8List issueClientCertificate({
  required EcKeyPair issuerKey,
  required Certificate issuer,
  required ECPublicKey subjectKey,
  required String commonName,
  required DateTime notBefore,
  required DateTime notAfter,
  BigInt? serial,
  SecureRandom? random,
}) => _issue(
  profile: CertificateProfile.client,
  issuerKey: issuerKey,
  issuerName: issuer.subject.der,
  subjectKey: subjectKey,
  commonName: commonName,
  notBefore: notBefore,
  notAfter: notAfter,
  dnsNames: const [],
  serial: serial,
  random: random,
);

/// PEM text for a certificate.
String certificatePem(List<int> der) => pemEncode('CERTIFICATE', der);

/// The DER of the first certificate in [pem].
Uint8List certificateFromPem(String pem) => pemDecode(pem, 'CERTIFICATE');

// -- Parsing ----------------------------------------------------------------

Certificate _parseCertificate(Uint8List der) {
  if (der.length > 16 * 1024) {
    throw const DerException('the certificate is too large');
  }
  final cert = parseDer(der).sequence;
  if (cert.length != 3) throw const DerException('malformed certificate');
  final tbsElement = cert[0];
  final tbs = tbsElement.sequence;
  final outerAlgorithm = cert[1];
  if (!_same(outerAlgorithm.encoded, _sha256WithEcdsa)) {
    throw const FormatException('the signature algorithm is not ECDSA-SHA256');
  }
  final signature = cert[2].bitString(
    unusedBits: (n) {
      if (n != 0) throw const FormatException('malformed signature');
    },
  );

  var i = 0;
  // version [0] EXPLICIT INTEGER, which must say v3.
  if (tbs.isEmpty || tbs[i].tag != contextTag(0, constructed: true)) {
    throw const FormatException('the certificate is not version 3');
  }
  final version = tbs[i++].children;
  if (version.length != 1 || version.single.integer != BigInt.two) {
    throw const FormatException('the certificate is not version 3');
  }
  if (tbs.length < i + 6) throw const DerException('malformed certificate');
  final serial = tbs[i++].integer;
  if (!_same(tbs[i++].encoded, _sha256WithEcdsa)) {
    throw const FormatException('the signature algorithm is not ECDSA-SHA256');
  }
  final issuer = Name.parse(tbs[i++]);
  final validity = tbs[i++].sequence;
  if (validity.length != 2) throw const DerException('malformed validity');
  final notBefore = validity[0].time;
  final notAfter = validity[1].time;
  final subject = Name.parse(tbs[i++]);
  final publicKey = decodePublicKey(tbs[i++]);

  var isCa = false;
  int? pathLength;
  final keyUsage = <KeyUsage>{};
  final eku = <String>[];
  final dns = <String>[];
  final seen = <String>{};
  if (i < tbs.length) {
    final element = tbs[i++];
    if (element.tag != contextTag(3, constructed: true) || i != tbs.length) {
      throw const FormatException('unexpected certificate fields');
    }
    final list = element.children;
    if (list.length != 1) throw const DerException('malformed extensions');
    for (final ext in list.single.sequence) {
      final parts = ext.sequence;
      if (parts.length < 2 || parts.length > 3) {
        throw const DerException('malformed extension');
      }
      final oid = parts[0].oid;
      final critical = parts.length == 3 && parts[1].boolean;
      final value = parseDer(parts.last.octetString);
      if (!seen.add(oid)) {
        throw FormatException('extension $oid appears twice');
      }
      switch (oid) {
        case Oid.basicConstraints:
          for (final part in value.sequence) {
            if (part.tag == Tag.boolean) {
              isCa = part.boolean;
            } else if (part.tag == Tag.integer) {
              pathLength = part.integer.toInt();
            }
          }
        case Oid.keyUsage:
          final bits = value.bitString();
          for (final usage in KeyUsage.values) {
            final byte = usage.bit ~/ 8;
            if (byte < bits.length &&
                bits[byte] & (0x80 >> (usage.bit % 8)) != 0) {
              keyUsage.add(usage);
            }
          }
        case Oid.extendedKeyUsage:
          for (final purpose in value.sequence) {
            eku.add(purpose.oid);
          }
        case Oid.subjectAltName:
          for (final name in value.sequence) {
            if (name.tag == contextTag(2, constructed: false)) {
              dns.add(String.fromCharCodes(name.content));
            }
          }
        default:
          if (critical) {
            throw FormatException('unknown critical extension $oid');
          }
      }
    }
  }
  return Certificate._(
    der: der,
    tbs: tbsElement.encoded,
    serial: serial,
    issuer: issuer,
    subject: subject,
    notBefore: notBefore,
    notAfter: notAfter,
    publicKey: publicKey,
    signature: Uint8List.fromList(signature),
    isCa: isCa,
    pathLength: pathLength,
    keyUsage: keyUsage,
    extendedKeyUsage: eku,
    dnsNames: dns,
  );
}
