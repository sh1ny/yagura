import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:yagura_pki/yagura_pki.dart';

import '../host/database.dart';
import '../host/secret_store.dart';
import 'atomically.dart';

/// The ids of the identity's secrets in the secret store (design D3).
const caKeySecret = 'daemon:ca_key';
const serverKeySecret = 'daemon:server_key';

/// How long the CA and the server certificate last.
const caValidity = Duration(days: 365 * 20 + 5);
const serverValidity = Duration(days: 730);

/// A server certificate is replaced when less than this remains.
const serverRenewalMargin = Duration(days: 30);

/// Certificates are valid from an hour before they are issued, so a client
/// whose clock is a little behind still accepts them.
const backdate = Duration(hours: 1);

/// A server key and its certificate, not yet in use.
class ServerMaterial {
  ServerMaterial(this.key, this.certificate);

  final EcKeyPair key;
  final Certificate certificate;
}

/// The daemon's identity (design D1, D4): daemon id, CA and server
/// certificate. Both private keys are in the secret store; the database holds
/// the public parts.
class DaemonIdentity {
  DaemonIdentity._(
    this._database,
    this._secrets,
    this._clock, {
    required this.daemonId,
    required this.caKey,
    required this.caCertificate,
    required this._server,
    required this.recreated,
  });

  final YaguraDatabase _database;
  final SecretStore _secrets;
  final DateTime Function() _clock;

  /// Random, stable for the life of the data directory.
  final String daemonId;
  final EcKeyPair caKey;
  final Certificate caCertificate;

  /// Whether the CA was made again because an earlier one was lost: devices
  /// enrolled under it can no longer be trusted.
  final bool recreated;

  ServerMaterial _server;

  /// The name in the server certificate and the one clients verify.
  String get authority => 'yagurad-$daemonId';

  ServerMaterial get serverMaterial => _server;
  EcKeyPair get serverKey => _server.key;
  Certificate get serverCertificate => _server.certificate;

  String get caFingerprint => caCertificate.sha256;

  /// What the daemon logs at start so the administrator can compare it with
  /// the pairing string.
  String get fingerprintLine => 'CA fingerprint: sha256:$caFingerprint';

  /// Whether the server certificate has under 30 days left.
  bool serverCertificateDue() =>
      serverCertificate.notAfter.difference(_clock()) < serverRenewalMargin;

  /// Opens the identity, or creates it when there is none. A failure to read
  /// or write the keys is `secret_store_unavailable`.
  static DaemonIdentity open(
    YaguraDatabase database,
    SecretStore secrets, {
    required DateTime Function() clock,
  }) {
    final rows = database.sqlite.select('SELECT * FROM daemon_identity');
    String? existingId;
    if (rows.isNotEmpty) {
      final row = rows.single;
      existingId = row['daemon_id']! as String;
      final caKeyBytes = secrets.get(caKeySecret);
      if (caKeyBytes != null) {
        try {
          final caKey = EcKeyPair.fromPrivateKeyPem(utf8.decode(caKeyBytes));
          final ca = Certificate.parse(
            Uint8List.fromList(row['ca_certificate']! as List<int>),
          );
          if (ca.publicKey.Q == caKey.publicKey.Q) {
            // The CA is intact. A server key or certificate that is missing
            // or does not match is replaced alone; the CA and the devices
            // stay (design D3: only the loss of the CA key remakes it).
            final server = _readServer(row, secrets, ca);
            final identity = DaemonIdentity._(
              database,
              secrets,
              clock,
              daemonId: existingId,
              caKey: caKey,
              caCertificate: ca,
              server: server ?? _issueServer(caKey, ca, existingId, clock()),
              recreated: false,
            );
            if (server == null) identity.adopt(identity._server);
            return identity;
          }
        } on FormatException {
          // Unreadable: made again below.
        } on PkiException {
          // Likewise.
        } on DerException {
          // Likewise.
        }
      }
    }
    return _create(
      database,
      secrets,
      clock,
      daemonId: existingId ?? _newId(),
      recreated: existingId != null,
    );
  }

  /// The stored server key and certificate, or null when either is missing,
  /// unreadable, or they do not belong together under [ca].
  static ServerMaterial? _readServer(
    Map<String, Object?> row,
    SecretStore secrets,
    Certificate ca,
  ) {
    try {
      final bytes = secrets.get(serverKeySecret);
      final der = row['server_certificate'] as List<int>?;
      if (bytes == null || der == null) return null;
      final key = EcKeyPair.fromPrivateKeyPem(utf8.decode(bytes));
      final cert = Certificate.parse(Uint8List.fromList(der));
      if (cert.publicKey.Q == key.publicKey.Q && cert.isSignedBy(ca)) {
        return ServerMaterial(key, cert);
      }
    } on FormatException {
      // Replaced by the caller.
    } on PkiException {
      // Likewise.
    } on DerException {
      // Likewise.
    }
    return null;
  }

  static DaemonIdentity _create(
    YaguraDatabase database,
    SecretStore secrets,
    DateTime Function() clock, {
    required String daemonId,
    required bool recreated,
  }) {
    final now = clock();
    final caKey = generateKeyPair();
    final caDer = issueCaCertificate(
      key: caKey,
      commonName: 'Yagura CA $daemonId',
      notBefore: now.subtract(backdate),
      notAfter: now.add(caValidity),
    );
    final ca = Certificate.parse(caDer);
    final server = _issueServer(caKey, ca, daemonId, now);
    // Keys and row in one transaction (both live in the database): a crash
    // leaves the old identity or the whole new one, never a mixture.
    atomically(database, () {
      secrets.put(
        caKeySecret,
        Uint8List.fromList(utf8.encode(caKey.privateKeyPem)),
      );
      secrets.put(
        serverKeySecret,
        Uint8List.fromList(utf8.encode(server.key.privateKeyPem)),
      );
      database.sqlite.execute('DELETE FROM daemon_identity');
      database.sqlite.execute(
        'INSERT INTO daemon_identity(id, daemon_id, ca_certificate, '
        'server_certificate, created_at) VALUES (1, ?, ?, ?, ?)',
        [daemonId, ca.der, server.certificate.der, now.millisecondsSinceEpoch],
      );
    });
    return DaemonIdentity._(
      database,
      secrets,
      clock,
      daemonId: daemonId,
      caKey: caKey,
      caCertificate: ca,
      server: server,
      recreated: recreated,
    );
  }

  /// A new server certificate and key, signed by the CA; nothing is stored
  /// until [adopt].
  ServerMaterial issueServer() =>
      _issueServer(caKey, caCertificate, daemonId, _clock());

  /// Makes [material] the server certificate: stored, then used.
  void adopt(ServerMaterial material) {
    // The key and the certificate change together or not at all.
    atomically(_database, () {
      _secrets.put(
        serverKeySecret,
        Uint8List.fromList(utf8.encode(material.key.privateKeyPem)),
      );
      _database.sqlite.execute(
        'UPDATE daemon_identity SET server_certificate = ? WHERE id = 1',
        [material.certificate.der],
      );
    });
    _server = material;
  }

  /// A client certificate for the key of [request], named by the daemon (never by
  /// the request).
  Uint8List issueClient({
    required CertificationRequest request,
    required String name,
    Duration validity = const Duration(days: 365),
  }) {
    final now = _clock();
    return issueClientCertificate(
      issuerKey: caKey,
      issuer: caCertificate,
      subjectKey: request.publicKey,
      commonName: name,
      notBefore: now.subtract(backdate),
      notAfter: now.add(validity),
    );
  }

  static ServerMaterial _issueServer(
    EcKeyPair caKey,
    Certificate ca,
    String daemonId,
    DateTime now,
  ) {
    final key = generateKeyPair();
    final der = issueServerCertificate(
      issuerKey: caKey,
      issuer: ca,
      subjectKey: key.publicKey,
      commonName: 'yagurad-$daemonId',
      dnsNames: ['yagurad-$daemonId', 'localhost'],
      notBefore: now.subtract(backdate),
      notAfter: now.add(serverValidity),
    );
    return ServerMaterial(key, Certificate.parse(der));
  }

  static String _newId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 6; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
