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

/// A daemon's certificate is renewed at most this often, by the client's
/// clock, whether or not the new one still looks due. A daemon with a wrong
/// clock issues certificates that look due at once; without the limit every
/// renewal would trigger the next.
const Duration kRenewalMinimumInterval = Duration(hours: 24);

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
    this.onRenewed,
    this.onClockSuspect,
  }) : _credentials = CredentialStore(keychain);

  final String daemonId;
  final DaemonRecord? Function() _record;
  final CredentialStore _credentials;
  final DaemonDialer _dialer;
  final DateTime Function() _now;
  final Delay _delay;

  /// Called with the time of each renewal, to keep it across restarts.
  final Future<void> Function(DateTime renewed)? onRenewed;

  /// Called with whether the daemon's clock looks wrong.
  final void Function({required bool suspect})? onClockSuspect;

  /// The last renewal of this session, in case it could not be saved.
  DateTime? _renewedAt;

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
  /// [kRenewalCheckInterval] until [ended] completes. A revoked device throws
  /// [ConnectionBlocked] with [Revoked]; a renewal the daemon refuses throws
  /// it with [Expired].
  ///
  /// The stored key and certificate are replaced only after the new
  /// certificate has arrived and been verified. If the answer is lost or the
  /// keychain write fails, the old pair is intact and the next check renews
  /// with it: the daemon accepts a renewal from the previous certificate for
  /// as long as the newest has never been used.
  Future<void> keepFresh(DaemonTransport transport, Future<void> ended) async {
    var over = false;
    unawaited(ended.whenComplete(() => over = true));
    while (!over) {
      try {
        if (await _renewIfDue(transport)) throw const ConnectionRefresh();
      } on ConnectionRefresh {
        rethrow;
      } on ConnectionBlocked {
        rethrow;
      } on Object catch (error) {
        debugPrint('daemon $daemonId: certificate check failed: $error');
      }
      await Future.any([_delay(kRenewalCheckInterval), ended]);
    }
  }

  bool _renewedRecently() {
    final times = [_renewedAt, _record()?.lastRenewal].nonNulls;
    for (final at in times) {
      final age = _now().difference(at);
      if (!age.isNegative && age < kRenewalMinimumInterval) return true;
    }
    return false;
  }

  /// Whether a new certificate was stored; the connection then reconnects
  /// with it at once, so it is in use within seconds.
  Future<bool> _renewIfDue(DaemonTransport transport) async {
    final current = await _credentials.load(daemonId);
    if (current == null) return false;
    if (current.certificateNotAfter.difference(_now()) >= kRenewalWindow) {
      onClockSuspect?.call(suspect: false);
      return false;
    }
    if (_renewedRecently()) {
      // Renewed within the day and still due: the daemon's clock is the
      // likely cause. Wait for the next check instead of renewing again.
      onClockSuspect?.call(suspect: true);
      return false;
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
      _renewedAt = _now();
      try {
        await onRenewed?.call(_renewedAt!);
      } on Object catch (e) {
        debugPrint('daemon $daemonId: renewal time not saved: $e');
      }
      onClockSuspect?.call(
        suspect:
            Certificate.parse(certificate).notAfter.difference(_now()) <
            kRenewalWindow,
      );
      return true;
    } on KeychainUnavailable catch (e) {
      // The daemon may have renewed already; the old pair still works.
      debugPrint('daemon $daemonId: new certificate not stored: $e');
    } on DaemonCallException catch (e) {
      if (e.reason == 'device_revoked') {
        throw const ConnectionBlocked(Revoked());
      }
      // 16 UNAUTHENTICATED and 7 PERMISSION_DENIED: the daemon refuses this
      // certificate. Anything else is a failed attempt to try again.
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
    return false;
  }
}
