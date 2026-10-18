/// Malformed DER.
class DerException implements Exception {
  const DerException(this.message);

  final String message;

  @override
  String toString() => 'DerException: $message';
}

/// A certificate or certificate signing request this package refuses.
///
/// [reason] is a stable identifier: `csr_invalid` for a request, and
/// `certificate_invalid` for a certificate.
class PkiException implements Exception {
  const PkiException(this.reason, this.message);

  final String reason;
  final String message;

  @override
  String toString() => 'PkiException($reason): $message';
}
