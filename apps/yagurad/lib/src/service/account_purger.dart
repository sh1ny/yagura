import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../errors.dart';
import '../platform/acl_writer.dart';
import '../platform/win32.dart';
import '../platform/win32_accounts.dart';

/// The local accounts the service owns (ADR 0013, 0015).
const serviceAccountNames = ['yagura-srv', 'yagura-steam'];

/// The id of the `secrets` row that holds the password of [account]. The
/// service-mode daemon (task group 9) stores the generated passwords under
/// these ids, and `--purge-accounts` deletes them.
String serviceAccountSecretId(String account) => 'service-account:$account';

/// What `--purge-accounts` did to one account.
class PurgeOutcome {
  const PurgeOutcome(this.account, {required this.removed, this.reason = ''});

  final String account;

  /// Whether the account, its profile and its secret row are gone.
  final bool removed;

  /// Why an account was kept.
  final String reason;
}

/// Lists the game servers that run, so `--purge-accounts` can refuse.
abstract interface class ServerProbe {
  /// Names of the instances whose server is running; empty when none is.
  Future<List<String>> runningServers();
}

/// Deletes the service accounts, their profiles and their secret rows.
abstract interface class AccountPurger {
  /// Deletes the accounts; the secret rows go from the database in
  /// [dataDirectory], which is the one the service was configured with.
  Future<List<PurgeOutcome>> purge({String? dataDirectory});
}

/// The account calls of the purge; the real ones need administrator rights,
/// so tests use a fake.
abstract interface class AccountOperations {
  /// The string SID of [account], or null when there is no such account.
  String? sidOf(String account);

  /// Deletes the profile of the account with [sid]; 0 on success, or the
  /// Win32 error (2 when the account never had a profile).
  int deleteProfile(String sid);

  /// Deletes the account; 0 on success or `NERR_UserNotFound` (2221).
  int deleteAccount(String account);
}

class WindowsAccountOperations implements AccountOperations {
  const WindowsAccountOperations();

  @override
  String? sidOf(String account) => const WindowsAccountSids().sidOf(account);

  @override
  int deleteProfile(String sid) => deleteAccountProfile(sid);

  @override
  int deleteAccount(String account) => deleteLocalAccount(account);
}

/// `ERROR_FILE_NOT_FOUND` and `ERROR_PATH_NOT_FOUND`: the account never had
/// a profile.
const _noProfile = {2, 3};

/// Deletes both accounts with their profiles and secret rows (design D6).
///
/// An account whose profile is still in use (a process of the account has
/// not exited yet) is kept with its secret row, and reported, so a later
/// purge can finish. The data directory must be free: the service is already
/// uninstalled when this runs.
class HostAccountPurger implements AccountPurger {
  HostAccountPurger({
    required this.dataDirectory,
    this.operations = const WindowsAccountOperations(),
    this.accounts = serviceAccountNames,
  });

  /// The data directory when [purge] is not told one.
  final String Function() dataDirectory;
  final AccountOperations operations;
  final List<String> accounts;

  @override
  Future<List<PurgeOutcome>> purge({String? dataDirectory}) async {
    final outcomes = <PurgeOutcome>[];
    final removed = <String>[];
    for (final account in accounts) {
      final sid = operations.sidOf(account);
      if (sid != null) {
        final profile = operations.deleteProfile(sid);
        if (profile != 0 && !_noProfile.contains(profile)) {
          outcomes.add(
            PurgeOutcome(
              account,
              removed: false,
              reason: 'its profile is still in use (error $profile)',
            ),
          );
          continue;
        }
        final deleted = operations.deleteAccount(account);
        if (deleted != 0 && deleted != nerrUserNotFound) {
          outcomes.add(
            PurgeOutcome(
              account,
              removed: false,
              reason: 'NetUserDel failed with error $deleted',
            ),
          );
          continue;
        }
      }
      removed.add(account);
    }
    final rowsFailed = _deleteSecretRows(
      removed,
      dataDirectory ?? this.dataDirectory(),
    );
    for (final account in removed) {
      outcomes.add(
        rowsFailed == null
            ? PurgeOutcome(account, removed: true)
            : PurgeOutcome(account, removed: false, reason: rowsFailed),
      );
    }
    return outcomes;
  }

  /// Deletes the secret rows of [removed]; returns why it could not, or null.
  String? _deleteSecretRows(List<String> removed, String directory) {
    if (removed.isEmpty) return null;
    final database = p.join(directory, 'yagura.db');
    if (!File(database).existsSync()) return null;
    final Database db;
    try {
      db = sqlite3.open(database);
    } on SqliteException catch (e) {
      return 'cannot open $database: ${e.message}';
    }
    try {
      db.execute('PRAGMA busy_timeout = 5000');
      final tables = db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['secrets'],
      );
      if (tables.isEmpty) return null;
      for (final account in removed) {
        db.execute('DELETE FROM secrets WHERE id = ?', [
          serviceAccountSecretId(account),
        ]);
      }
      return null;
    } on SqliteException catch (e) {
      return 'cannot delete the secret row: ${e.message}';
    } finally {
      db.close();
    }
  }
}

/// [ServerProbe] over the admin channel, and when the daemon is down over a
/// read-only look at its database: a server runs when a run recorded as
/// running still has a live process under its PID. (A reused PID makes the
/// answer "running", which only ever refuses a purge.)
class HostServerProbe implements ServerProbe {
  HostServerProbe({
    required this.status,
    required this.dataDirectory,
    this.isRunning = _processRunning,
  });

  /// `status` over the admin channel.
  final Future<Map<String, Object?>> Function() status;
  final String Function() dataDirectory;
  final bool Function(int pid) isRunning;

  @override
  Future<List<String>> runningServers() async {
    try {
      final reported = (await status())['running_servers'];
      if (reported is List) return [for (final name in reported) '$name'];
      return const [];
    } on YaguraException catch (e) {
      if (e.reason != 'daemon_not_running') rethrow;
    }
    final database = p.join(dataDirectory(), 'yagura.db');
    if (!File(database).existsSync()) return const [];
    final Database db;
    try {
      db = sqlite3.open(database, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw YaguraException(
        'internal_error',
        'cannot tell whether game servers run: ${e.message}',
      );
    }
    try {
      return [
        // A run that is running holds its server; a pending one that has a
        // relay may be about to start one.
        for (final row in db.select(
          "SELECT i.name AS name, CASE r.state WHEN 'running' "
          'THEN r.server_pid ELSE r.relay_pid END AS pid FROM runs r '
          'JOIN instances i ON i.id = r.instance_id '
          "WHERE r.state = 'running' OR (r.state = 'pending' AND "
          'r.relay_pid > 0)',
        ))
          if (isRunning(row['pid']! as int)) '${row['name']}',
      ];
    } on SqliteException catch (e) {
      throw YaguraException(
        'internal_error',
        'cannot tell whether game servers run: ${e.message}',
      );
    } finally {
      db.close();
    }
  }
}

bool _processRunning(int pid) {
  final win32 = Win32.instance;
  final handle = win32.openProcess(
    Win32.processQueryLimitedInformation | Win32.synchronize,
    0,
    pid,
  );
  if (handle == 0) return false;
  try {
    return win32.waitForSingleObject(handle, 0) == Win32.waitTimeout;
  } finally {
    win32.closeHandle(handle);
  }
}
