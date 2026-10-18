import 'dart:io';
import 'dart:typed_data';

import '../errors.dart';
import '../platform/win32_security.dart';
import 'database.dart';

/// Protects secret bytes for one Windows account scope (design D3).
abstract interface class SecretProtector {
  /// The SID whose DPAPI scope [protect] uses.
  String get scopeSid;

  Uint8List protect(Uint8List plain);

  /// Throws [WrongSecretKey] when [blob] can never be opened by this scope's
  /// key, and any other `secret_store_unavailable` when it cannot be opened
  /// now for another reason.
  Uint8List unprotect(Uint8List blob);
}

/// [SecretProtector.unprotect] failed because the blob belongs to another key
/// (another account, or another machine's DPAPI key): the row is foreign, not
/// merely unreadable at the moment.
class WrongSecretKey extends YaguraException {
  WrongSecretKey(String message) : super('secret_store_unavailable', message);
}

/// DPAPI user scope of the account the process runs as (ADR 0011): no
/// `CRYPTPROTECT_LOCAL_MACHINE`, so another account cannot open the blobs.
class DpapiSecretProtector implements SecretProtector {
  DpapiSecretProtector() : scopeSid = _currentSid();

  static String _currentSid() {
    try {
      return currentUserSid();
    } on Win32Error catch (e) {
      throw YaguraException('secret_store_unavailable', '$e');
    }
  }

  @override
  final String scopeSid;

  @override
  Uint8List protect(Uint8List plain) {
    try {
      return dpapiProtect(plain);
    } on Win32Error catch (e) {
      throw YaguraException('secret_store_unavailable', '$e');
    }
  }

  @override
  Uint8List unprotect(Uint8List blob) {
    try {
      return dpapiUnprotect(blob);
    } on DpapiError catch (e) {
      if (e.isWrongKey) throw WrongSecretKey('$e');
      throw YaguraException('secret_store_unavailable', '$e');
    } on Win32Error catch (e) {
      throw YaguraException('secret_store_unavailable', '$e');
    }
  }
}

/// The protector of a host without a secret store yet (Linux arrives in M5):
/// it opens, holds no rows, and refuses to protect anything.
class UnsupportedSecretProtector implements SecretProtector {
  @override
  String get scopeSid => 'unsupported';

  @override
  Uint8List protect(Uint8List plain) => throw _unsupported();

  @override
  Uint8List unprotect(Uint8List blob) => throw _unsupported();

  YaguraException _unsupported() => YaguraException(
    'secret_store_unavailable',
    'this host has no secret store yet',
  );
}

/// DPAPI on Windows; elsewhere a store that refuses to hold secrets.
SecretProtector defaultSecretProtector() =>
    Platform.isWindows ? DpapiSecretProtector() : UnsupportedSecretProtector();

/// What opening the store did to rows protected for another scope.
class SecretRecovery {
  const SecretRecovery({
    this.instanceIds = const [],
    this.instanceNames = const {},
    this.ownedIds = const [],
  });

  /// Instances that lost secret settings.
  final List<String> instanceIds;

  /// Their names by id.
  final Map<String, String> instanceNames;

  /// Ids of daemon-owned secrets (no instance) that were deleted.
  final List<String> ownedIds;

  bool get isEmpty => instanceIds.isEmpty && ownedIds.isEmpty;

  /// The text of notice `secrets_reset`: names the instances affected.
  String describe() {
    final parts = <String>[];
    if (instanceIds.isNotEmpty) {
      final named = [
        for (final id in instanceIds) '$id (${instanceNames[id] ?? ''})',
      ];
      parts.add(
        'secret settings of ${named.join(', ')} were protected for another '
        'Windows account and were deleted; set them again',
      );
    }
    if (ownedIds.isNotEmpty) {
      parts.add(
        '${ownedIds.length} secret(s) owned by the daemon were protected for '
        'another Windows account and were deleted',
      );
    }
    return parts.join('; ');
  }
}

/// The id of the secret behind setting [setting] of instance [instanceId]:
/// one secret per (instance, setting).
String secretIdFor(String instanceId, String setting) =>
    'instance:$instanceId:$setting';

/// Secrets by id (design D3).
abstract interface class SecretStore {
  /// Stores or replaces the secret [id]. A secret setting passes its
  /// [instanceId] and [setting]; the daemon's own secrets pass neither.
  void put(
    String id,
    Uint8List value, {
    String? instanceId,
    String setting = '',
  });

  /// The value of [id], or `null` when there is none.
  Uint8List? get(String id);

  /// Whether this scope holds a value for [id], without opening it.
  bool contains(String id);

  void delete(String id);
}

/// The `secrets` table behind a [SecretProtector]. Each row records the SID
/// of the scope that protected it (`scope_sid`).
class DatabaseSecretStore implements SecretStore {
  DatabaseSecretStore._(this._database, this._protector, this.recovery);

  final YaguraDatabase _database;
  final SecretProtector _protector;

  /// What [open] deleted; empty when every row was in this scope.
  final SecretRecovery recovery;

  /// Whether this host can protect secrets at all (false where the protector
  /// is the placeholder of a host without a store).
  bool get available => _protector is! UnsupportedSecretProtector;

  /// Opens the store. Rows whose scope is not the protector's cannot be
  /// read. In [serviceMode] they are deleted in one transaction and reported
  /// in [recovery]; otherwise nothing changes and this throws
  /// `secret_store_unavailable` naming both SIDs.
  ///
  /// In [serviceMode] the rows of this scope are also test-decrypted once: a
  /// data directory moved to another machine keeps the SID of LocalSystem but
  /// not its DPAPI key, so a row that fails with a wrong-key error counts as
  /// foreign. Any other failure throws `secret_store_unavailable` and deletes
  /// nothing.
  static DatabaseSecretStore open(
    YaguraDatabase database,
    SecretProtector protector, {
    required bool serviceMode,
  }) {
    final sid = protector.scopeSid;
    final foreign = database.sqlite.select(
      'SELECT s.id, s.instance_id, s.scope_sid, i.name '
      'FROM secrets s LEFT JOIN instances i ON i.id = s.instance_id '
      'WHERE s.scope_sid <> ? ORDER BY s.created_at, s.id',
      [sid],
    );
    if (foreign.isNotEmpty && !serviceMode) {
      final other = {for (final row in foreign) row['scope_sid']! as String};
      throw YaguraException(
        'secret_store_unavailable',
        'the data directory holds secrets protected for ${other.join(', ')}, '
            'but this daemon runs as $sid; use another --data-dir for a dev '
            'daemon on a host where the service runs',
        details: {'current_sid': sid, 'foreign_sids': other.toList()..sort()},
      );
    }
    final lost = [...foreign];
    if (serviceMode) {
      final own = database.sqlite.select(
        'SELECT s.id, s.instance_id, s.scope_sid, i.name, s.blob '
        'FROM secrets s LEFT JOIN instances i ON i.id = s.instance_id '
        'WHERE s.scope_sid = ? ORDER BY s.created_at, s.id',
        [sid],
      );
      for (final row in own) {
        try {
          final plain = protector.unprotect(
            Uint8List.fromList(row['blob']! as List<int>),
          );
          plain.fillRange(0, plain.length, 0);
        } on WrongSecretKey {
          // Only a wrong-key error makes a row foreign. Any other failure
          // escapes: the step exits `secret_store_unavailable` and nothing is
          // deleted, so a transient fault never costs a secret.
          lost.add(row);
        }
      }
    }
    if (lost.isEmpty) {
      return DatabaseSecretStore._(database, protector, const SecretRecovery());
    }
    final names = <String, String>{};
    final owned = <String>[];
    for (final row in lost) {
      if (row['instance_id'] case final String instance) {
        names[instance] = (row['name'] as String?) ?? '';
      } else {
        owned.add(row['id']! as String);
      }
    }
    database.transaction(() {
      for (final row in lost) {
        database.sqlite.execute('DELETE FROM secrets WHERE id = ?', [
          row['id'],
        ]);
      }
    });
    return DatabaseSecretStore._(
      database,
      protector,
      SecretRecovery(
        instanceIds: names.keys.toList(),
        instanceNames: names,
        ownedIds: owned,
      ),
    );
  }

  @override
  void put(
    String id,
    Uint8List value, {
    String? instanceId,
    String setting = '',
  }) {
    final blob = _protector.protect(value);
    _database.sqlite.execute(
      'INSERT OR REPLACE INTO secrets'
      '(id, instance_id, setting, blob, scope_sid, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        id,
        instanceId,
        setting,
        blob,
        _protector.scopeSid,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Uint8List? get(String id) {
    final rows = _database.sqlite.select(
      'SELECT blob FROM secrets WHERE id = ? AND scope_sid = ?',
      [id, _protector.scopeSid],
    );
    if (rows.isEmpty) return null;
    return _protector.unprotect(
      Uint8List.fromList(rows.single['blob'] as List<int>),
    );
  }

  @override
  bool contains(String id) => _database.sqlite.select(
    'SELECT 1 FROM secrets WHERE id = ? AND scope_sid = ?',
    [id, _protector.scopeSid],
  ).isNotEmpty;

  @override
  void delete(String id) {
    _database.sqlite.execute('DELETE FROM secrets WHERE id = ?', [id]);
  }
}
