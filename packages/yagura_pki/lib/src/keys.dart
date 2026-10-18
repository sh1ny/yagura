import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';
import 'errors.dart';
import 'oids.dart';

/// The curve every key in Yagura uses: ECDSA P-256 (ADR 0007).
final ECDomainParameters p256 = ECCurve_secp256r1();

final _prime = BigInt.parse(
  'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  radix: 16,
);
final _b = BigInt.parse(
  '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
  radix: 16,
);

/// A P-256 key pair.
class EcKeyPair {
  EcKeyPair(this.privateKey, this.publicKey);

  final ECPrivateKey privateKey;
  final ECPublicKey publicKey;

  /// The private key as a SEC1 `EC PRIVATE KEY` PEM.
  String get privateKeyPem => encodePrivateKeyPem(privateKey);

  /// Rebuilds the pair from [privateKeyPem].
  factory EcKeyPair.fromPrivateKeyPem(String pem) {
    final key = decodePrivateKeyPem(pem);
    return EcKeyPair(key, ECPublicKey(p256.G * key.d, p256));
  }
}

/// A random source seeded from the operating system.
SecureRandom secureRandom([Random? seedSource]) {
  final source = seedSource ?? Random.secure();
  final random = FortunaRandom()
    ..seed(
      KeyParameter(
        Uint8List.fromList([for (var i = 0; i < 32; i++) source.nextInt(256)]),
      ),
    );
  return random;
}

/// A new P-256 key pair.
EcKeyPair generateKeyPair({SecureRandom? random}) {
  final generator = ECKeyGenerator()
    ..init(
      ParametersWithRandom(
        ECKeyGeneratorParameters(p256),
        random ?? secureRandom(),
      ),
    );
  final pair = generator.generateKeyPair();
  return EcKeyPair(pair.privateKey, pair.publicKey);
}

/// The SubjectPublicKeyInfo of [key]: `id-ecPublicKey` on `prime256v1` and
/// the uncompressed point.
Uint8List encodePublicKey(ECPublicKey key) {
  final point = key.Q!;
  final x = bigIntToFixedBytes(point.x!.toBigInteger()!, 32);
  final y = bigIntToFixedBytes(point.y!.toBigInteger()!, 32);
  return derSequence([
    derSequence([derOid(Oid.ecPublicKey), derOid(Oid.prime256v1)]),
    derBitString([0x04, ...x, ...y]),
  ]);
}

/// Reads a SubjectPublicKeyInfo. Only an `id-ecPublicKey` key on P-256 whose
/// point lies on the curve is accepted; anything else throws [DerException]
/// or [FormatException].
ECPublicKey decodePublicKey(Der info) {
  final parts = info.sequence;
  if (parts.length != 2) {
    throw const FormatException('malformed SubjectPublicKeyInfo');
  }
  final algorithm = parts[0].sequence;
  if (algorithm.length != 2 ||
      algorithm[0].oid != Oid.ecPublicKey ||
      algorithm[1].oid != Oid.prime256v1) {
    throw const FormatException('the key is not an ECDSA P-256 key');
  }
  final bits = parts[1].bitString(
    unusedBits: (n) {
      if (n != 0) throw const FormatException('malformed public key');
    },
  );
  if (bits.length != 65 || bits[0] != 0x04) {
    throw const FormatException('the public key point is not uncompressed');
  }
  final x = bytesToBigInt(bits.sublist(1, 33));
  final y = bytesToBigInt(bits.sublist(33));
  if (x >= _prime || y >= _prime) {
    throw const FormatException('the public key point is not on the curve');
  }
  final left = (y * y) % _prime;
  final right = (x * x * x - BigInt.from(3) * x + _b) % _prime;
  if (left != right) {
    throw const FormatException('the public key point is not on the curve');
  }
  return ECPublicKey(p256.curve.createPoint(x, y), p256);
}

/// `ecdsa-with-SHA256` over [data]; the signature is DER `SEQUENCE {r, s}`.
Uint8List signEcdsaSha256(
  ECPrivateKey key,
  List<int> data, {
  SecureRandom? random,
}) {
  final signer = Signer('SHA-256/ECDSA')
    ..init(
      true,
      ParametersWithRandom(
        PrivateKeyParameter<ECPrivateKey>(key),
        random ?? secureRandom(),
      ),
    );
  final signature =
      signer.generateSignature(Uint8List.fromList(data)) as ECSignature;
  return derSequence([derInteger(signature.r), derInteger(signature.s)]);
}

/// Whether the DER `SEQUENCE {r, s}` [signature] over [data] verifies under
/// [key].
bool verifyEcdsaSha256(ECPublicKey key, List<int> data, List<int> signature) {
  final BigInt r;
  final BigInt s;
  try {
    final parts = parseDer(Uint8List.fromList(signature)).sequence;
    if (parts.length != 2) return false;
    r = parts[0].integer;
    s = parts[1].integer;
  } on DerException {
    return false;
  }
  final n = p256.n;
  if (r == BigInt.zero || s == BigInt.zero || r >= n || s >= n) return false;
  final verifier = Signer('SHA-256/ECDSA')
    ..init(false, PublicKeyParameter<ECPublicKey>(key));
  return verifier.verifySignature(Uint8List.fromList(data), ECSignature(r, s));
}

/// SHA-256 of [data] as 64 lower-case hex characters.
String sha256Hex(List<int> data) {
  final digest = SHA256Digest().process(Uint8List.fromList(data));
  return [for (final b in digest) b.toRadixString(16).padLeft(2, '0')].join();
}

// -- SEC1 private keys and PEM -----------------------------------------------

/// SEC1 `ECPrivateKey` DER with the curve and the public key included, as
/// OpenSSL writes it.
Uint8List encodePrivateKeyDer(ECPrivateKey key) {
  final point = p256.G * key.d!;
  final x = bigIntToFixedBytes(point!.x!.toBigInteger()!, 32);
  final y = bigIntToFixedBytes(point.y!.toBigInteger()!, 32);
  return derSequence([
    derSmallInteger(1),
    derOctetString(bigIntToFixedBytes(key.d!, 32)),
    derContext(0, [derOid(Oid.prime256v1)]),
    derContext(1, [
      derBitString([0x04, ...x, ...y]),
    ]),
  ]);
}

String encodePrivateKeyPem(ECPrivateKey key) =>
    pemEncode('EC PRIVATE KEY', encodePrivateKeyDer(key));

ECPrivateKey decodePrivateKeyPem(String pem) {
  final der = pemDecode(pem, 'EC PRIVATE KEY');
  try {
    final parts = parseDer(der).sequence;
    if (parts.length < 2 ||
        parts[0].integer != BigInt.one ||
        parts[1].tag != Tag.octetString) {
      throw const FormatException('malformed EC private key');
    }
    final d = bytesToBigInt(parts[1].octetString);
    if (d == BigInt.zero || d >= p256.n) {
      throw const FormatException('the private scalar is out of range');
    }
    return ECPrivateKey(d, p256);
  } on DerException catch (e) {
    throw FormatException(e.message);
  }
}

/// PEM text for [der] with the label [label].
String pemEncode(String label, List<int> der) {
  final body = base64.encode(der);
  final lines = [
    for (var i = 0; i < body.length; i += 64)
      body.substring(i, min(i + 64, body.length)),
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

/// The DER inside the first PEM block labelled [label].
Uint8List pemDecode(String pem, String label) {
  final match = RegExp('-----BEGIN $label-----([\\s\\S]*?)-----END $label-----')
      .firstMatch(pem);
  if (match == null) {
    throw FormatException('no "$label" PEM block');
  }
  try {
    return base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    throw FormatException('the "$label" PEM block is not base64');
  }
}

/// Wraps a [FormatException] from key decoding for callers that deal in
/// requests.
PkiException invalidKey(String reason, Object error) => PkiException(
  reason,
  error is FormatException
      ? error.message
      : error is DerException
      ? error.message
      : '$error',
);
