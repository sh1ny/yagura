/// Object identifiers the package reads and writes.
abstract final class Oid {
  static const ecPublicKey = '1.2.840.10045.2.1';
  static const prime256v1 = '1.2.840.10045.3.1.7';
  static const ecdsaWithSha256 = '1.2.840.10045.4.3.2';

  static const commonName = '2.5.4.3';

  static const basicConstraints = '2.5.29.19';
  static const keyUsage = '2.5.29.15';
  static const extendedKeyUsage = '2.5.29.37';
  static const subjectAltName = '2.5.29.17';

  static const serverAuth = '1.3.6.1.5.5.7.3.1';
  static const clientAuth = '1.3.6.1.5.5.7.3.2';
}
