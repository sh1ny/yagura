import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'certificate.dart';
import 'der.dart';
import 'errors.dart';
import 'keys.dart';
import 'oids.dart';

/// The largest request the parser reads.
const maxCsrBytes = 4096;

final _algorithm = derSequence([derOid(Oid.ecdsaWithSha256)]);

/// A PKCS#10 request for [key] with subject `CN=[commonName]`. It carries no
/// attributes.
Uint8List buildCsr({
  required EcKeyPair key,
  required String commonName,
  SecureRandom? random,
}) {
  final info = derSequence([
    derSmallInteger(0),
    encodeCommonName(commonName),
    encodePublicKey(key.publicKey),
    derContext(0, const []),
  ]);
  final signature = signEcdsaSha256(key.privateKey, info, random: random);
  return derSequence([info, _algorithm, derBitString(signature)]);
}

/// A request that parsed and verified.
class CertificationRequest {
  CertificationRequest._(this.publicKey, this.commonName);

  /// The key to certify: P-256, on the curve.
  final ECPublicKey publicKey;

  /// The requested common name; the daemon never copies it into a
  /// certificate.
  final String? commonName;

  /// Parses and verifies [der]. Throws [PkiException] `csr_invalid` for a
  /// request with attributes, a key that is not P-256, an unsupported
  /// signature algorithm, trailing bytes or a bad signature.
  static CertificationRequest parse(Uint8List der) {
    try {
      return _parse(der);
    } on DerException catch (e) {
      throw PkiException('csr_invalid', e.message);
    } on FormatException catch (e) {
      throw PkiException('csr_invalid', e.message);
    }
  }
}

CertificationRequest _parse(Uint8List der) {
  if (der.length > maxCsrBytes) {
    throw const DerException('the request is too large');
  }
  final request = parseDer(der).sequence;
  if (request.length != 3) throw const DerException('malformed request');
  final infoElement = request[0];
  final info = infoElement.sequence;
  if (request[1].encoded.length != _algorithm.length ||
      !_equal(request[1].encoded, _algorithm)) {
    throw const FormatException('the signature algorithm is not ECDSA-SHA256');
  }
  final signature = request[2].bitString(
    unusedBits: (n) {
      if (n != 0) throw const FormatException('malformed signature');
    },
  );
  if (info.length != 4) {
    throw const FormatException('the request has unexpected fields');
  }
  if (info[0].integer != BigInt.zero) {
    throw const FormatException('the request version is not 0');
  }
  final subject = Name.parse(info[1]);
  final key = decodePublicKey(info[2]);
  // attributes [0] must be present and empty: the daemon accepts no
  // requested extensions or other attributes.
  if (info[3].tag != contextTag(0, constructed: true) ||
      info[3].content.isNotEmpty) {
    throw const FormatException('the request carries attributes');
  }
  if (!verifyEcdsaSha256(key, infoElement.encoded, signature)) {
    throw const FormatException('the request signature is invalid');
  }
  return CertificationRequest._(key, subject.commonName);
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
