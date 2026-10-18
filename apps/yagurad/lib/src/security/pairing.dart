import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/database.dart';
import 'atomically.dart';
import 'audit.dart';
import 'devices.dart';
import 'identity.dart';

/// How long a pairing code is valid.
const pairingCodeLifetime = Duration(minutes: 10);

/// Wrong codes from one address inside [pairingWindow] that block it.
const wrongCodesPerAddress = 5;

/// Wrong codes from all addresses inside [pairingWindow] that invalidate the
/// active code.
const wrongCodesInTotal = 50;
const pairingWindow = Duration(minutes: 10);

/// Addresses the throttle remembers; at the bound the oldest is forgotten.
const throttledAddresses = 10000;

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const _codeLength = 10;

class IssuedPairingCode {
  IssuedPairingCode(this.code, this.expiresAt);

  final String code;
  final DateTime expiresAt;
}

/// Pairing codes, enrollment and renewal (design D1, D4).
class PairingService {
  PairingService({
    required this._database,
    required this._identity,
    required this._devices,
    required this._audit,
    required this._clock,
    Random? random,
  }) : _random = random ?? Random.secure();

  final YaguraDatabase _database;
  final DaemonIdentity _identity;
  final DeviceStore _devices;
  final AuditLog _audit;
  final DateTime Function() _clock;
  final Random _random;

  // Wrong codes by address, oldest address first.
  final _byAddress = <String, List<DateTime>>{};
  final _total = <DateTime>[];

  /// Issues a code; it replaces the one that was active.
  IssuedPairingCode issueCode() {
    final now = _clock();
    final code = [
      for (var i = 0; i < _codeLength; i++)
        _alphabet[_random.nextInt(_alphabet.length)],
    ].join();
    final expires = now.add(pairingCodeLifetime);
    atomically(_database, () {
      _database.sqlite
        ..execute('DELETE FROM pairing_codes')
        ..execute(
          'INSERT INTO pairing_codes(code_hash, created_at, expires_at) '
          'VALUES (?, ?, ?)',
          [
            _hash(code),
            now.millisecondsSinceEpoch,
            expires.millisecondsSinceEpoch,
          ],
        );
    });
    _total.clear();
    return IssuedPairingCode(code, expires);
  }

  /// Enrolls a device. The throttle and the code are checked before the
  /// request is parsed, so the parser is reachable only with a valid code.
  pb.EnrollResponse enroll({
    required String code,
    required String deviceName,
    required Uint8List csrDer,
    InternetAddress? address,
  }) {
    final now = _clock();
    final key = _addressKey(address);
    final recent = _recent(key, now);
    if (recent.length >= wrongCodesPerAddress) {
      throw YaguraException(
        'pairing_throttled',
        'too many wrong pairing codes from this address; try again in '
            '${pairingWindow.inMinutes} minutes',
      );
    }
    if (!_matchesActiveCode(code, now)) {
      _recordWrong(key, recent, now);
      throw YaguraException(
        'pairing_code_invalid',
        'the pairing code is wrong, already used or expired',
      );
    }
    final name = _checkName(deviceName);
    final request = _parse(csrDer);
    final certificate = _identity.issueClient(request: request, name: name);
    final parsed = Certificate.parse(certificate);
    final device = atomically(_database, () {
      // Used in the same transaction as the device row, so a failure in
      // between leaves the code usable.
      _database.sqlite.execute(
        'UPDATE pairing_codes SET used_at = ? WHERE used_at IS NULL',
        [now.millisecondsSinceEpoch],
      );
      final device = _devices.enroll(
        name: name,
        sha256: parsed.sha256,
        notAfter: parsed.notAfter,
        address: address?.address ?? '',
      );
      _audit.record(
        deviceId: device.id,
        address: address?.address ?? '',
        method: 'yagura.v1.Pairing/Enroll',
        target: device.id,
        result: 'ok',
      );
      return device;
    });
    return pb.EnrollResponse(
      deviceId: device.id,
      clientCertificateDer: certificate,
      caCertificateDer: _identity.caCertificate.der,
    );
  }

  /// Signs the request of [deviceId] for a new key; the old certificate keeps
  /// working until it expires.
  pb.EnrollResponse renew({
    required String deviceId,
    required Uint8List csrDer,
  }) {
    final device = _devices.get(deviceId);
    if (device == null || device.revoked) {
      throw YaguraException('device_revoked', 'this device is revoked');
    }
    final request = _parse(csrDer);
    final certificate = _identity.issueClient(
      request: request,
      name: device.name,
    );
    final parsed = Certificate.parse(certificate);
    _devices.addCertificate(deviceId, parsed.sha256, parsed.notAfter);
    return pb.EnrollResponse(
      deviceId: deviceId,
      clientCertificateDer: certificate,
      caCertificateDer: _identity.caCertificate.der,
    );
  }

  CertificationRequest _parse(Uint8List der) {
    try {
      return CertificationRequest.parse(der);
    } on PkiException catch (e) {
      throw YaguraException(e.reason, e.message);
    }
  }

  /// The trimmed name, or `device_name_invalid`.
  static String _checkName(String name) => checkDeviceName(name);

  bool _matchesActiveCode(String code, DateTime now) {
    final rows = _database.sqlite.select(
      'SELECT code_hash FROM pairing_codes WHERE used_at IS NULL '
      'AND expires_at > ?',
      [now.millisecondsSinceEpoch],
    );
    if (rows.isEmpty) return false;
    return rows.single['code_hash'] == _hash(_normalize(code));
  }

  static String _normalize(String code) => code
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');

  static String _hash(String code) => sha256Hex(_normalize(code).codeUnits);

  List<DateTime> _recent(String key, DateTime now) {
    final wrong = _byAddress[key];
    if (wrong == null) return const [];
    wrong.removeWhere((t) => now.difference(t) >= pairingWindow);
    if (wrong.isEmpty) _byAddress.remove(key);
    return wrong;
  }

  void _recordWrong(String key, List<DateTime> recent, DateTime now) {
    if (recent.isEmpty && !_byAddress.containsKey(key)) {
      if (_byAddress.length >= throttledAddresses) {
        _byAddress.remove(_byAddress.keys.first);
      }
      _byAddress[key] = [now];
    } else {
      recent.add(now);
    }
    _total
      ..removeWhere((t) => now.difference(t) >= pairingWindow)
      ..add(now);
    if (_total.length >= wrongCodesInTotal) {
      _database.sqlite.execute(
        'UPDATE pairing_codes SET used_at = ? WHERE used_at IS NULL',
        [now.millisecondsSinceEpoch],
      );
      _total.clear();
    }
  }

  /// IPv4 by address, IPv6 by /64, so a host cannot dodge the throttle with
  /// the addresses of its own prefix.
  static String _addressKey(InternetAddress? address) {
    if (address == null) return 'unknown';
    final raw = address.rawAddress;
    if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
      final mapped =
          raw.sublist(0, 10).every((b) => b == 0) &&
          raw[10] == 0xff &&
          raw[11] == 0xff;
      if (mapped) return raw.sublist(12).join('.');
      return '${raw.sublist(0, 8).map((b) => b.toRadixString(16)).join(':')}'
          '/64';
    }
    return address.address;
  }
}

/// A device name has 1 to 64 characters and no control characters.
String checkDeviceName(String name) {
  final trimmed = name.trim();
  final length = trimmed.runes.length;
  if (length < 1 ||
      length > 64 ||
      trimmed.runes.any((r) => r < 0x20 || r == 0x7f)) {
    throw YaguraException(
      'device_name_invalid',
      'a device name has 1 to 64 characters and no control characters',
    );
  }
  return trimmed;
}
