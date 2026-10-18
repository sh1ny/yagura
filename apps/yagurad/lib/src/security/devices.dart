import 'dart:math';

import '../errors.dart';
import '../host/database.dart';
import 'atomically.dart';

/// A certificate a device may present (design D4): its current one and,
/// after a renewal, the previous one until it expires.
class DeviceCertificateRow {
  const DeviceCertificateRow(this.sha256, this.notAfter);

  final String sha256;
  final DateTime notAfter;
}

class DeviceRecord {
  DeviceRecord({
    required this.id,
    required this.name,
    required this.enrolledAt,
    required this.lastSeenAt,
    required this.lastAddress,
    required this.revokedAt,
    required this.revokedBy,
    required this.certificates,
  });

  final String id;
  final String name;
  final DateTime enrolledAt;
  final DateTime? lastSeenAt;
  final String lastAddress;
  final DateTime? revokedAt;
  final String revokedBy;
  final List<DeviceCertificateRow> certificates;

  bool get revoked => revokedAt != null;

  /// The certificate issued last; the only one that may renew.
  DeviceCertificateRow? get newestCertificate =>
      certificates.isEmpty ? null : certificates.last;

  /// The end of the latest certificate.
  DateTime? get certificateExpiresAt => certificates.isEmpty
      ? null
      : certificates
            .map((c) => c.notAfter)
            .reduce((a, b) => a.isAfter(b) ? a : b);
}

/// What the auth gate knows about a certificate fingerprint.
class CertificateEntry {
  const CertificateEntry(this.deviceId, this.notAfter, this.revoked);

  final String deviceId;
  final DateTime notAfter;
  final bool revoked;
}

/// Enrolled devices and their certificates (design D4), with the in-memory
/// index the auth gate reads on every call.
class DeviceStore {
  DeviceStore(this._database, {required this._clock, this.maxDevices = 100}) {
    _reindex();
  }

  final YaguraDatabase _database;
  final DateTime Function() _clock;

  /// Enrolled devices that are not revoked.
  final int maxDevices;

  var _index = <String, CertificateEntry>{};

  // Last seen times are kept in memory and written by [flush]: an
  // authenticated stream of calls costs no write per call.
  final _seen = <String, (DateTime, String)>{};

  static final _random = Random.secure();

  int get activeCount =>
      _database.sqlite
              .select(
                'SELECT count(*) AS n FROM devices WHERE revoked_at IS NULL',
              )
              .single['n']!
          as int;

  /// The device behind [fingerprint], or null when no enrolled device holds
  /// that certificate.
  CertificateEntry? lookup(String fingerprint) => _index[fingerprint];

  /// Adds a device holding the certificate [sha256]. The caller opens the
  /// transaction when this must be atomic with something else.
  DeviceRecord enroll({
    required String name,
    required String sha256,
    required DateTime notAfter,
    required String address,
  }) {
    if (activeCount >= maxDevices) {
      throw YaguraException(
        'too_many_devices',
        'this daemon already has $maxDevices enrolled devices; revoke one '
            'first',
        details: {'limit': maxDevices},
      );
    }
    final id = 'dev-${_hex(8)}';
    final now = _clock().millisecondsSinceEpoch;
    atomically(_database, () {
      _database.sqlite
        ..execute(
          'INSERT INTO devices(id, name, enrolled_at, last_seen_at, '
          'last_address) VALUES (?, ?, ?, ?, ?)',
          [id, name, now, now, address],
        )
        ..execute(
          'INSERT INTO device_certificates(device_id, sha256, not_after) '
          'VALUES (?, ?, ?)',
          [id, sha256, notAfter.millisecondsSinceEpoch],
        );
    });
    _reindex();
    return get(id)!;
  }

  /// Adds a renewed certificate to [deviceId]. Only the certificate that
  /// asked for the renewal ([presentedSha256]) is kept beside the new one;
  /// any other certificate of the device is dropped, so a key retired by a
  /// renewal stops working with the second one (design D4).
  void addCertificate(
    String deviceId,
    String sha256,
    DateTime notAfter, {
    required String presentedSha256,
  }) {
    atomically(_database, () {
      _database.sqlite
        ..execute(
          'DELETE FROM device_certificates WHERE device_id = ? '
          'AND sha256 <> ?',
          [deviceId, presentedSha256],
        )
        ..execute(
          'INSERT INTO device_certificates(device_id, sha256, not_after) '
          'VALUES (?, ?, ?)',
          [deviceId, sha256, notAfter.millisecondsSinceEpoch],
        );
    });
    _reindex();
  }

  DeviceRecord? get(String id) {
    flush();
    return _read(
      _database.sqlite.select('SELECT * FROM devices WHERE id = ?', [id]),
    ).firstOrNull;
  }

  /// Every device, enrollment order.
  List<DeviceRecord> list() {
    flush();
    return _read(
      _database.sqlite.select('SELECT * FROM devices ORDER BY enrolled_at, id'),
    );
  }

  /// Marks [id] revoked by [by]; every certificate of the device stops
  /// working. The index is rebuilt before this returns.
  DeviceRecord revoke(String id, String by) {
    final device = get(id);
    if (device == null) throw _notFound(id);
    if (device.revoked) return device;
    _database.sqlite.execute(
      'UPDATE devices SET revoked_at = ?, revoked_by = ? WHERE id = ?',
      [_clock().millisecondsSinceEpoch, by, id],
    );
    _reindex();
    return get(id)!;
  }

  /// Revokes every device that is not revoked yet, as after a new CA.
  void revokeAll(String by) {
    _database.sqlite.execute(
      'UPDATE devices SET revoked_at = ?, revoked_by = ? '
      'WHERE revoked_at IS NULL',
      [_clock().millisecondsSinceEpoch, by],
    );
    _reindex();
  }

  DeviceRecord rename(String id, String name) {
    if (get(id) == null) throw _notFound(id);
    _database.sqlite.execute('UPDATE devices SET name = ? WHERE id = ?', [
      name,
      id,
    ]);
    return get(id)!;
  }

  /// Notes that [deviceId] made a call from [address].
  void seen(String deviceId, String address) {
    _seen[deviceId] = (_clock(), address);
  }

  /// Writes the last seen times.
  void flush() {
    if (_seen.isEmpty) return;
    final entries = [..._seen.entries];
    _seen.clear();
    atomically(_database, () {
      for (final MapEntry(key: id, value: (time, address)) in entries) {
        _database.sqlite.execute(
          'UPDATE devices SET last_seen_at = ?, last_address = ? WHERE id = ?',
          [time.millisecondsSinceEpoch, address, id],
        );
      }
    });
  }

  List<DeviceRecord> _read(Iterable<Map<String, Object?>> rows) => [
    for (final row in rows)
      DeviceRecord(
        id: row['id']! as String,
        name: row['name']! as String,
        enrolledAt: _time(row['enrolled_at']! as int),
        lastSeenAt: (row['last_seen_at'] as int?).let(_time),
        lastAddress: row['last_address']! as String,
        revokedAt: (row['revoked_at'] as int?).let(_time),
        revokedBy: row['revoked_by']! as String,
        certificates: [
          for (final c in _database.sqlite.select(
            'SELECT sha256, not_after FROM device_certificates '
            'WHERE device_id = ? ORDER BY not_after, rowid',
            [row['id']],
          ))
            DeviceCertificateRow(
              c['sha256']! as String,
              _time(c['not_after']! as int),
            ),
        ],
      ),
  ];

  void _reindex() {
    final index = <String, CertificateEntry>{};
    for (final row in _database.sqlite.select(
      'SELECT c.sha256, c.not_after, c.device_id, d.revoked_at '
      'FROM device_certificates c JOIN devices d ON d.id = c.device_id',
    )) {
      index[row['sha256']! as String] = CertificateEntry(
        row['device_id']! as String,
        _time(row['not_after']! as int),
        row['revoked_at'] != null,
      );
    }
    _index = index;
  }

  static DateTime _time(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  static String _hex(int bytes) => [
    for (var i = 0; i < bytes; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  YaguraException _notFound(String id) => YaguraException(
    'device_not_found',
    'no device has the id $id',
    details: {'deviceId': id},
  );
}

extension on int? {
  T? let<T>(T Function(int) body) => this == null ? null : body(this!);
}
