/// Opens a daemon's secure connection and keeps its certificate fresh
/// (design D13).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yagura_pki/yagura_pki.dart';

import 'connection.dart';
import 'credentials.dart';
import 'daemon_record.dart';
import 'dialer.dart';
import 'keychain.dart';
import 'transport.dart';

/// A certificate with fewer days than this left is renewed.
const Duration kRenewalWindow = Duration(days: 30);

/// How often a connected daemon's certificate is checked.
const Duration kRenewalCheckInterval = Duration(hours: 24);

/// The seam between a [DaemonConnection] and the keychain: it makes each
/// attempt's transport from the stored credentials and renews the client
/// certificate.
final class DaemonLink {
  DaemonLink({
    required this.daemonId,
    required this._record,
    required Keychain keychain,
    required this._dialer,
    required this._now,
    required this._delay,
  }) : _credentials = CredentialStore(keychain);

  final String daemonId;
  final DaemonRecord? Function() _record;
  final CredentialStore _credentials;
  final DaemonDialer _dialer;
  final DateTime Function() _now;
  final Delay _delay;

  static const _loopback = {'127.0.0.1', 'localhost', '::1'};

  /// The transport for one connection attempt.
  ///
  /// Throws [ConnectionBlocked] with [Expired] when the stored client
  /// certificate has expired, without any network call. Throws
  /// [KeychainUnavailable] when the keychain cannot be read.
  Future<DaemonTransport> open() async {
    final record = _record();
    if (record == null) throw StateError('daemon $daemonId is not listed');
    if (record.isDev) {
      if (!_loopback.contains(record.host)) {
        throw StateError(
          'the development daemon is reachable on loopback only, not '
          '${record.host}',
        );
      }
      return _dialer.development(host: record.host, port: record.port);
    }
    final credentials = await _credentials.load(record.id);
    if (credentials == null) {
      throw const DaemonCallException(
        code: 16,
        reason: 'credentials_missing',
        message: 'no key or certificate is stored for this daemon',
      );
    }
    if (!_now().isBefore(credentials.certificateNotAfter)) {
      throw const ConnectionBlocked(Expired());
    }
    return _dialer.secure(
      host: record.host,
      port: record.port,
      authority: record.authority,
      credentials: credentials,
    );
  }

  /// Renews the client certificate when due, now and then every
  /// [kRenewalCheckInterval] until [ended] completes. A refused renewal
  /// throws [ConnectionBlocked] with [Expired].
  Future<void> keepFresh(DaemonTransport transport, Future<void> ended) async {
    var over = false;
    unawaited(ended.whenComplete(() => over = true));
    while (!over) {
      try {
        await _renewIfDue(transport);
      } on ConnectionBlocked {
        rethrow;
      } on Object catch (error) {
        debugPrint('daemon $daemonId: certificate check failed: $error');
      }
      await Future.any([_delay(kRenewalCheckInterval), ended]);
    }
  }

  Future<void> _renewIfDue(DaemonTransport transport) async {
    final current = await _credentials.load(daemonId);
    if (current == null) return;
    if (current.certificateNotAfter.difference(_now()) >= kRenewalWindow) {
      return;
    }
    // A new key for the new certificate; the old pair keeps working until the
    // new certificate is in the keychain.
    final key = generateKeyPair();
    await _credentials.writePendingKey(daemonId, key.privateKeyPem);
    try {
      final response = await transport.renewCertificate(
        buildCsr(key: key, commonName: 'yagura-client'),
      );
      final certificate = Uint8List.fromList(response.clientCertificateDer);
      if (Certificate.parse(certificate).publicKey.Q != key.publicKey.Q) {
        throw const DaemonCallException(
          code: 13,
          reason: 'renewal_invalid',
          message: 'the daemon returned a certificate for another key',
        );
      }
      await _credentials.replaceDevice(
        daemonId,
        keyPem: key.privateKeyPem,
        certificateDer: certificate,
      );
    } on DaemonCallException catch (e) {
      // 16 UNAUTHENTICATED and 7 PERMISSION_DENIED: the daemon refuses this
      // certificate. Anything else is a failed attempt to try again.
      if (e.reason == 'device_revoked') {
        throw const ConnectionBlocked(Revoked());
      }
      if (e.code == 16 || e.code == 7) {
        throw const ConnectionBlocked(Expired());
      }
      debugPrint('daemon $daemonId: renewal failed: $e');
    } finally {
      try {
        await _credentials.deletePendingKey(daemonId);
      } on KeychainUnavailable {
        // The entry is overwritten by the next attempt.
      }
    }
  }
}
