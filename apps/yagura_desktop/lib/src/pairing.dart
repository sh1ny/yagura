/// Pairing a daemon from a pairing string (design D13, protocol "Pairing").
library;

import 'dart:typed_data';

import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'credentials.dart';
import 'daemon_record.dart';
import 'dialer.dart';
import 'keychain.dart';
import 'transport.dart';

/// Why pairing did not complete. [reason] is a stable code (docs/protocol.md):
/// `invalid_pairing_string`, `fingerprint_mismatch`, `pairing_code_invalid`,
/// `keychain_unavailable`, `too_many_daemons`, or the daemon's own reason.
class PairingFailure implements Exception {
  const PairingFailure(this.reason, this.message, {this.details = const {}});

  final String reason;
  final String message;

  /// Extra facts the UI can show, e.g. the `expected` and `presented`
  /// fingerprints.
  final Map<String, String> details;

  @override
  String toString() => '$reason: $message';
}

/// `yagura://<host>:<port>?code=<CODE>&ca=sha256:<64 hex>&name=<name>`
final class PairingString {
  const PairingString({
    required this.host,
    required this.port,
    required this.code,
    required this.caFingerprint,
    required this.name,
  });

  final String host;
  final int port;
  final String code;

  /// 64 lower-case hex characters.
  final String caFingerprint;
  final String name;

  static final _code = RegExp(r'^[0-9A-Za-z]{10}$');
  static final _fingerprint = RegExp(r'^sha256:([0-9a-fA-F]{64})$');

  static const _invalid = PairingFailure(
    'invalid_pairing_string',
    'That is not a pairing string. Paste the line printed by "yagurad pair": '
        'yagura://<host>:<port>?code=<code>&ca=sha256:<fingerprint>',
  );

  /// Throws [PairingFailure] `invalid_pairing_string`; makes no network call.
  static PairingString parse(String text) {
    final Uri uri;
    try {
      uri = Uri.parse(text.trim());
    } on FormatException {
      throw _invalid;
    }
    final query = uri.queryParameters;
    final code = query['code'];
    final fingerprint = _fingerprint.firstMatch(query['ca'] ?? '');
    if (uri.scheme != 'yagura' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasFragment ||
        code == null ||
        !_code.hasMatch(code) ||
        fingerprint == null) {
      throw _invalid;
    }
    final name = query['name'];
    return PairingString(
      host: uri.host,
      port: uri.port,
      code: code.toUpperCase(),
      caFingerprint: fingerprint.group(1)!.toLowerCase(),
      name: name == null || name.isEmpty ? uri.host : name,
    );
  }
}

/// Pairs a daemon: parse, `Pairing.Info`, fingerprint check, `Enroll` with a
/// CSR for a key that only the keychain holds.
final class PairingService {
  PairingService({required Keychain keychain, required this._dialer})
    : _credentials = CredentialStore(keychain);

  final CredentialStore _credentials;
  final DaemonDialer _dialer;

  static final _authority = RegExp(r'^yagurad-([0-9A-Za-z]{1,64})$');

  /// The record of the new daemon; its credentials are in the keychain. On
  /// any failure the key generated for it is gone again. [knownIds] are the
  /// daemons already listed (pairing one of them again replaces it).
  Future<DaemonRecord> pair(
    String pairingString,
    String deviceName, {
    Set<String> knownIds = const {},
  }) async {
    final parsed = PairingString.parse(pairingString);
    final name = deviceName.trim();
    if (name.isEmpty || name.length > 64) {
      throw const PairingFailure(
        'device_name_invalid',
        'The device name must be 1 to 64 characters.',
      );
    }

    // 1. Info over TLS that verifies nothing: the CA is not known yet.
    final PairingInfo info;
    final unpinned = _dialer.pairing(host: parsed.host, port: parsed.port);
    try {
      info = await unpinned.info();
    } on DaemonCallException catch (e) {
      throw _unreachable(parsed, e);
    } finally {
      await unpinned.close();
    }

    // 2. The CA must be the one the pairing string names; otherwise stop
    // before the code is sent.
    final caDer = Uint8List.fromList(info.caCertificateDer);
    final presented = sha256Hex(caDer);
    if (presented != parsed.caFingerprint) {
      throw PairingFailure(
        'fingerprint_mismatch',
        'The daemon presented a different CA than the pairing string names, '
            'so the code was not sent. Expected ${parsed.caFingerprint}, '
            'presented $presented.',
        details: {'expected': parsed.caFingerprint, 'presented': presented},
      );
    }
    final authority = _authority.firstMatch(info.tlsAuthority);
    if (authority == null) {
      throw PairingFailure(
        'tls_authority_invalid',
        'The daemon names itself "${info.tlsAuthority}", which is not a '
            'yagurad-<id> name.',
      );
    }
    final id = authority.group(1)!;
    if (!knownIds.contains(id) && knownIds.length >= kMaxDaemons) {
      throw const PairingFailure(
        'too_many_daemons',
        'The list holds $kMaxDaemons daemons. Remove one first.',
      );
    }

    // 3. A key that stays in the keychain; only its CSR leaves.
    final key = generateKeyPair();
    try {
      await _credentials.writePendingKey(id, key.privateKeyPem);
    } on KeychainUnavailable catch (e) {
      throw PairingFailure(
        KeychainUnavailable.reason,
        'The OS keychain is not available, so no key can be kept: '
        '${e.message}',
      );
    }
    try {
      final csr = buildCsr(key: key, commonName: name);
      final enrolled = await _enroll(
        parsed,
        info.tlsAuthority,
        caDer,
        name,
        csr,
      );
      final certificate = Uint8List.fromList(enrolled.clientCertificateDer);
      _checkIssued(certificate, key, enrolled, presented);
      await _credentials.save(
        id,
        DeviceCredentials(
          caDer: caDer,
          certificateDer: certificate,
          keyPem: key.privateKeyPem,
        ),
      );
      await _credentials.deletePendingKey(id);
      return DaemonRecord(
        id: id,
        name: info.daemonName.isNotEmpty ? info.daemonName : parsed.name,
        host: parsed.host,
        port: parsed.port,
        caFingerprint: presented,
      );
    } on KeychainUnavailable catch (e) {
      await _discard(id);
      throw PairingFailure(
        KeychainUnavailable.reason,
        'The OS keychain stopped answering: ${e.message}',
      );
    } on Object {
      await _discard(id);
      rethrow;
    }
  }

  Future<EnrollResponse> _enroll(
    PairingString parsed,
    String authority,
    Uint8List caDer,
    String deviceName,
    Uint8List csr,
  ) async {
    // A new connection with the checked CA as its only root.
    final channel = _dialer.pairing(
      host: parsed.host,
      port: parsed.port,
      pinnedCa: caDer,
      authority: authority,
    );
    try {
      return await channel.enroll(
        EnrollRequest(code: parsed.code, deviceName: deviceName, csrDer: csr),
      );
    } on DaemonCallException catch (e) {
      throw switch (e.reason) {
        'pairing_code_invalid' => const PairingFailure(
          'pairing_code_invalid',
          'The pairing code expired or was used. Ask the host admin for a '
              'new one with "yagurad pair".',
        ),
        'pairing_throttled' => const PairingFailure(
          'pairing_throttled',
          'Too many wrong codes were sent from this address. Wait ten minutes '
              'and try again.',
        ),
        'server_ca_mismatch' => const PairingFailure(
          'server_ca_mismatch',
          'The daemon no longer presents the CA it showed a moment ago.',
        ),
        _ => _unreachable(parsed, e),
      };
    } finally {
      await channel.close();
    }
  }

  /// The daemon must return a certificate for the key we hold and the CA we
  /// pinned.
  void _checkIssued(
    Uint8List certificateDer,
    EcKeyPair key,
    EnrollResponse response,
    String pinnedFingerprint,
  ) {
    try {
      final certificate = Certificate.parse(certificateDer);
      if (certificate.publicKey.Q != key.publicKey.Q) {
        throw const PairingFailure(
          'enroll_response_invalid',
          'The daemon returned a certificate for another key.',
        );
      }
    } on PkiException catch (e) {
      throw PairingFailure('enroll_response_invalid', e.message);
    }
    if (response.caCertificateDer.isNotEmpty &&
        sha256Hex(response.caCertificateDer) != pinnedFingerprint) {
      throw const PairingFailure(
        'enroll_response_invalid',
        'The daemon returned another CA than the one pinned.',
      );
    }
  }

  PairingFailure _unreachable(PairingString parsed, DaemonCallException e) {
    final why = e.reason.isNotEmpty
        ? e.reason
        : (e.message.isNotEmpty ? e.message : 'status ${e.code}');
    return PairingFailure(
      e.reason.isNotEmpty ? e.reason : 'daemon_unreachable',
      'Pairing with ${parsed.host}:${parsed.port} failed: $why',
    );
  }

  Future<void> _discard(String id) async {
    try {
      await _credentials.deletePendingKey(id);
    } on KeychainUnavailable {
      // Nothing more can be done; the entry is overwritten by the next try.
    }
  }
}
