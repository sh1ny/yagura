import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../errors.dart';
import '../host/database.dart';
import '../host/secret_store.dart';
import '../operations/operations.dart';
import 'operation_reporter.dart';
import 'steam_service.dart';

/// A Steam account of the daemon (design D1).
class SteamAccountInfo {
  const SteamAccountInfo({
    required this.id,
    required this.username,
    required this.status,
    required this.passwordRemembered,
    required this.createdAt,
    this.lastLoginAt,
    this.usedByInstanceIds = const [],
  });

  /// \`acct_<12 hex>\`; it names the account's SteamCMD installation.
  final String id;
  final String username;

  /// \`adding\`, \`ready\` or \`reauth_required\`.
  final String status;
  final bool passwordRemembered;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final List<String> usedByInstanceIds;
}

/// What a run for an instance needs of the account it uses.
class SteamAccountUse {
  const SteamAccountUse(this.id, this.username, this.rememberedPassword);

  final String id;
  final String username;

  /// The password the daemon remembers, read only when it is needed.
  final String? Function() rememberedPassword;
}

/// The Steam accounts (design D1, D2, D3): their rows, their passwords in the
/// secret store, and the operations that log them in.
///
/// An account has its own SteamCMD installation, so SteamCMD's cached login of
/// one account never evicts another's. A password is held in memory for the
/// operation that was given it; it is kept, encrypted, only when the admin
/// chose to remember it.
class SteamAccounts {
  SteamAccounts({
    required this.database,
    required this.secrets,
    required this.runner,
    required this.steam,
    DateTime Function()? clock,
    this.maxAccounts = 32,
    this.log,
  }) : _clock = clock ?? DateTime.now;

  final YaguraDatabase database;
  final SecretStore secrets;
  final OperationRunner runner;
  final SteamService steam;
  final DateTime Function() _clock;

  /// Accounts the daemon keeps, \`adding\` ones included.
  final int maxAccounts;
  final void Function(String message)? log;

  static final _random = Random.secure();
  static final _username = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');

  /// The secret that holds the remembered password of [accountId].
  static String secretIdOf(String accountId) => 'steam:$accountId';

  // ---- reading ---------------------------------------------------------------

  List<SteamAccountInfo> list() => [
    for (final row in database.sqlite.select(
      'SELECT * FROM steam_accounts ORDER BY created_at, rowid',
    ))
      _fromRow(row),
  ];

  SteamAccountInfo? get(String accountId) {
    final rows = database.sqlite.select(
      'SELECT * FROM steam_accounts WHERE id = ?',
      [accountId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  SteamAccountInfo _require(String accountId) =>
      get(accountId) ??
      (throw YaguraException(
        'account_not_found',
        'there is no Steam account $accountId',
        details: {'accountId': accountId},
      ));

  SteamAccountInfo _fromRow(Map<String, Object?> row) {
    final id = row['id']! as String;
    return SteamAccountInfo(
      id: id,
      username: row['username']! as String,
      status: row['status']! as String,
      passwordRemembered: secrets.contains(secretIdOf(id)),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      lastLoginAt: switch (row['last_login_at']) {
        final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
        _ => null,
      },
      usedByInstanceIds: _instancesUsing(id),
    );
  }

  List<String> _instancesUsing(String accountId) => [
    for (final row in database.sqlite.select(
      'SELECT id FROM instances WHERE steam_account_id = ? '
      'ORDER BY created_at, rowid',
      [accountId],
    ))
      row['id']! as String,
  ];

  // ---- operations ------------------------------------------------------------

  /// Starts the \`add_steam_account\` operation for a new account. The row
  /// exists, as \`adding\`, from now on, so the username is taken and the
  /// account counts toward the bound while Steam Guard is waited for.
  Operation add({
    required String username,
    required String password,
    required bool rememberPassword,
  }) {
    _checkCredentials(username, password);
    if (list().length >= maxAccounts) {
      throw YaguraException(
        'too_many_accounts',
        'the daemon already keeps $maxAccounts Steam accounts',
        details: {'limit': maxAccounts},
      );
    }
    // Steam account names are case-insensitive (the username pattern is
    // ASCII, so NOCASE covers it).
    final taken = database.sqlite.select(
      'SELECT 1 FROM steam_accounts WHERE username = ? COLLATE NOCASE',
      [username],
    );
    if (taken.isNotEmpty) {
      throw YaguraException(
        'account_exists',
        'a Steam account named "$username" is already added',
        details: {'username': username},
      );
    }
    final accountId = [
      'acct_',
      for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
    ].join();
    database.sqlite.execute(
      'INSERT INTO steam_accounts (id, username, status, password_secret_id, '
      'created_at) VALUES (?, ?, ?, ?, ?)',
      [accountId, username, 'adding', '', _clock().millisecondsSinceEpoch],
    );
    try {
      return runner.enqueue(
        accountId: accountId,
        kind: OperationKind.addSteamAccount,
        body: (ctx) =>
            _add(ctx, accountId, username, password, rememberPassword),
      );
    } on Object {
      database.sqlite.execute('DELETE FROM steam_accounts WHERE id = ?', [
        accountId,
      ]);
      rethrow;
    }
  }

  Future<void> _add(
    OperationContext ctx,
    String accountId,
    String username,
    String password,
    bool remember,
  ) async {
    try {
      await _login(ctx, accountId, username, password);
      // The password is stored only now, after Steam accepted it, and before
      // the account turns ready: a refused write fails the add.
      _keepPassword(accountId, password, remember);
      database.sqlite.execute(
        'UPDATE steam_accounts SET status = ?, password_secret_id = ?, '
        'last_login_at = ? WHERE id = ?',
        [
          'ready',
          remember ? secretIdOf(accountId) : '',
          _clock().millisecondsSinceEpoch,
          accountId,
        ],
      );
    } on Object {
      // A daemon that is stopping leaves the account `adding`; the next
      // start removes it.
      if (!runner.isClosed) await _discard(accountId);
      rethrow;
    }
  }

  /// Starts the \`reauth_steam_account\` operation. The account stays as it is
  /// until the login succeeds, which also replaces its stored password.
  Operation reauth({
    required String accountId,
    required String password,
    required bool rememberPassword,
  }) {
    final account = _require(accountId);
    _checkCredentials(account.username, password);
    if (account.status == 'adding') {
      throw YaguraException(
        'invalid_state',
        'the Steam account ${account.username} is still being added',
        details: {'accountId': accountId},
      );
    }
    return runner.enqueue(
      accountId: accountId,
      kind: OperationKind.reauthSteamAccount,
      body: (ctx) async {
        await _login(ctx, accountId, account.username, password);
        _keepPassword(accountId, password, rememberPassword);
        database.sqlite.execute(
          'UPDATE steam_accounts SET status = ?, password_secret_id = ?, '
          'last_login_at = ? WHERE id = ?',
          [
            'ready',
            rememberPassword ? secretIdOf(accountId) : '',
            _clock().millisecondsSinceEpoch,
            accountId,
          ],
        );
      },
    );
  }

  /// Logs the account in under its installation lock, without a heavy slot
  /// (design D1): a login is short and never holds one of the host's slots.
  Future<void> _login(
    OperationContext ctx,
    String accountId,
    String username,
    String password,
  ) => ctx.heavy(
    () => steam.login(
      SteamLoginRequest(
        account: accountId,
        username: username,
        password: password,
      ),
      OperationSteamReporter(ctx),
      ctx.cancel,
    ),
    installation: 'account:$accountId',
    slot: false,
  );

  /// Stores [password] as the account's secret when it is to be remembered;
  /// drops a stored one when it is not (the admin's choice is the latest one).
  void _keepPassword(String accountId, String password, bool remember) {
    final id = secretIdOf(accountId);
    if (remember) {
      secrets.put(id, Uint8List.fromList(utf8.encode(password)));
    } else if (secrets.contains(id)) {
      secrets.delete(id);
    }
  }

  /// Removes everything an account that was not added left: its row, its
  /// secret and its installation.
  Future<void> _discard(String accountId) async {
    try {
      secrets.delete(secretIdOf(accountId));
      await steam.removeInstallation(accountId);
    } on Object catch (e) {
      log?.call('cannot remove the installation of $accountId: $e');
    } finally {
      database.sqlite.execute('DELETE FROM steam_accounts WHERE id = ?', [
        accountId,
      ]);
    }
  }

  /// Removes an account (a call, not an operation). Refused with
  /// \`account_in_use\` while an instance links it or an operation for it is
  /// queued or running.
  Future<List<SteamAccountInfo>> remove(String accountId) async {
    final account = _require(accountId);
    if (account.usedByInstanceIds.isNotEmpty) {
      final ids = account.usedByInstanceIds;
      throw YaguraException(
        'account_in_use',
        'the Steam account ${account.username} is used by instance '
            '${ids.join(', ')}',
        details: {'accountId': accountId, 'instanceIds': ids},
      );
    }
    if (runner.hasActive(subjectOf('', accountId))) {
      throw YaguraException(
        'account_in_use',
        'an operation for the Steam account ${account.username} is queued or '
            'running',
        details: {'accountId': accountId},
      );
    }
    await steam.removeInstallation(accountId);
    secrets.delete(secretIdOf(accountId));
    database.sqlite.execute('DELETE FROM steam_accounts WHERE id = ?', [
      accountId,
    ]);
    return list();
  }

  // ---- startup ---------------------------------------------------------------

  /// Deletes the accounts a previous daemon left \`adding\` with their stored
  /// passwords and installations (design D1). Runs after the runner marked
  /// the unfinished operations interrupted, so no ghost account counts toward
  /// the bound, blocks a username or keeps a password.
  Future<void> recoverAdding() async {
    final rows = database.sqlite.select(
      "SELECT id FROM steam_accounts WHERE status = 'adding'",
    );
    final failed = <String>[];
    for (final row in rows) {
      final id = row['id']! as String;
      secrets.delete(secretIdOf(id));
      try {
        await steam.removeInstallation(id);
        database.sqlite.execute('DELETE FROM steam_accounts WHERE id = ?', [
          id,
        ]);
      } on Object catch (e) {
        failed.add('$id ($e)');
      }
    }
    if (failed.isNotEmpty) {
      throw YaguraException(
        'internal_error',
        'cannot remove the SteamCMD installation of ${failed.join(', ')}',
      );
    }
  }

  // ---- use by instances ------------------------------------------------------

  /// The account for a run of an instance. Throws \`steam_account_required\`
  /// when it does not exist or is still being added, and
  /// \`steam_reauth_required\` when its login is known to have expired and no
  /// password is remembered to log in again.
  SteamAccountUse useFor(String accountId) {
    final account = get(accountId);
    if (account == null || account.status == 'adding') {
      throw YaguraException(
        'steam_account_required',
        'the Steam account $accountId of this instance is not available',
        details: {'accountId': accountId},
      );
    }
    if (account.status == 'reauth_required' && !account.passwordRemembered) {
      throw YaguraException(
        'steam_reauth_required',
        'the Steam login of ${account.username} has expired; log in again '
            'with its password',
        details: {'accountId': accountId},
      );
    }
    return SteamAccountUse(account.id, account.username, () {
      final stored = secrets.get(secretIdOf(accountId));
      return stored == null ? null : utf8.decode(stored);
    });
  }

  /// A run found the cached login expired and had no password to log in with.
  void markReauthRequired(String accountId) => database.sqlite.execute(
    "UPDATE steam_accounts SET status = 'reauth_required' "
    "WHERE id = ? AND status = 'ready'",
    [accountId],
  );

  /// A run logged in: the account is ready.
  void markLoggedIn(String accountId) => database.sqlite.execute(
    "UPDATE steam_accounts SET status = 'ready', last_login_at = ? "
    "WHERE id = ? AND status IN ('ready', 'reauth_required')",
    [_clock().millisecondsSinceEpoch, accountId],
  );

  void _checkCredentials(String username, String password) {
    if (!_username.hasMatch(username)) {
      throw YaguraException(
        'steam_login_invalid',
        'a Steam username is 1 to 64 letters, digits, dots, dashes and '
            'underscores',
        details: {'field': 'username'},
      );
    }
    if (password.isEmpty ||
        password.length > 256 ||
        password.startsWith('+') ||
        password.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      throw YaguraException(
        'steam_login_invalid',
        'the password is empty, too long, starts with "+" or holds control '
            'characters, which SteamCMD cannot take on its command line',
        details: {'field': 'password'},
      );
    }
  }
}
