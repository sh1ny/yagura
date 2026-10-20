/// Certificates and CSRs for the daemon CA: a small DER builder over
/// pointycastle (design D1 of `m2-secure-remote-host`).
///
/// It covers only what Yagura issues: P-256 keys, v3 certificates with basic
/// constraints, key usage, extended key usage and DNS names, and PKCS#10
/// requests without attributes.
library;

export 'src/certificate.dart'
    show
        Certificate,
        CertificateProfile,
        KeyUsage,
        Name,
        certificateFromPem,
        certificatePem,
        issueCaCertificate,
        issueClientCertificate,
        issueServerCertificate,
        randomSerial;
export 'src/csr.dart' show CertificationRequest, buildCsr, maxCsrBytes;
export 'src/errors.dart' show DerException, PkiException;
export 'src/keys.dart'
    show
        EcKeyPair,
        decodePrivateKeyPem,
        encodePrivateKeyPem,
        generateKeyPair,
        secureRandom,
        sha256Hex;
