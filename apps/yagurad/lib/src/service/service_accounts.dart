import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../errors.dart';
import '../host/secret_store.dart';
import '../platform/win32_account_management.dart';
import '../platform/win32_security.dart';
import 'account_purger.dart';

/// The group every service account belongs to, and only that one.
const usersGroupSid = 'S-1-5-32-545';

/// The account that runs game servers (ADR 0015).
const gameServerAccount = 'yagura-srv';

/// The account that runs SteamCMD (ADR 0014).
const steamAccount = 'yagura-steam';

/// A random password for a service account (design D7): 32 CSPRNG bytes
/// become 64 characters, one per nibble. The position picks the class
/// (upper case, lower case, digit, symbol in turn), so every password holds
/// all four and passes a complexity policy; each character carries 4 bits,
/// 256 in all.
String generatePassword(Uint8List bytes) {
  if (bytes.length != 32) {
    throw ArgumentError.value(bytes.length, 'bytes', 'needs 32 bytes');
  }
  const classes = [
    'ABCDEFGHJKLMNPQR',
    'abcdefghjkmnpqrs',
    '0123456789234567',
    r'!#$%&()*+-=?@^_~',
  ];
  final out = StringBuffer();
  for (var i = 0; i < 64; i++) {
    final byte = bytes[i ~/ 2];
    final nibble = i.isEven ? byte >> 4 : byte & 0xf;
    out.write(classes[i % 4][nibble]);
  }
  return out.toString();
}

/// The account calls of the repair, behind an interface so that the repair is
/// tested with a fake; the real ones need administrator rights.
abstract interface class AccountBackend {
  /// Whether the local account [name] exists.
  bool exists(String name);

  /// Creates [name] with [password].
  void create(String name, String password);

  /// Sets the password of [name] without a logon (`NetUserSetInfo` 1003).
  void setPassword(String name, String password);

  /// Grants the batch logon right and assigns the three deny rights.
  void assignLogonRights(String name);

  /// Makes `Users` the only local group [name] belongs to.
  void restrictMembership(String name);

  /// The string SID of [name], or null.
  String? sidOf(String name);
}

/// The service accounts as the service-mode daemon keeps them (design D7).
abstract interface class ServiceAccounts {
  /// Creates or repairs `yagura-srv` and `yagura-steam`; throws a
  /// [YaguraException] `service_accounts` naming the first failure.
  void ensure();

  /// The stored password of [account], or null before [ensure] ran.
  String? passwordOf(String account);

  /// The string SID of [account], or null when it does not exist.
  String? sidOf(String account);
}

/// Creates the accounts at every start, idempotently, and repairs drift:
/// the stored password is set on the account without a test logon (a failed
/// logon would count toward lockout), the logon rights are assigned again and
/// any membership other than `Users` is removed.
class HostServiceAccounts implements ServiceAccounts {
  HostServiceAccounts({
    required this.backend,
    required this.secrets,
    Random? random,
    this.accounts = const [gameServerAccount, steamAccount],
  }) : _random = random ?? Random.secure();

  final AccountBackend backend;

  /// Where the passwords are kept, under [serviceAccountSecretId]: purge
  /// deletes exactly those rows.
  final SecretStore secrets;
  final List<String> accounts;
  final Random _random;

  @override
  void ensure() {
    for (final account in accounts) {
      try {
        _ensure(account);
      } on YaguraException {
        rethrow;
      } on Object catch (e) {
        throw YaguraException(
          'service_accounts',
          'the account $account could not be set up: $e',
          details: {'account': account},
        );
      }
    }
  }

  void _ensure(String account) {
    final id = serviceAccountSecretId(account);
    final stored = secrets.get(id);
    var password = stored == null ? null : utf8.decode(stored);
    if (password == null || password.length != 64) {
      password = generatePassword(
        Uint8List.fromList([for (var i = 0; i < 32; i++) _random.nextInt(256)]),
      );
      // Stored first: an account created with a password nobody kept could not
      // be logged on to.
      secrets.put(id, Uint8List.fromList(utf8.encode(password)));
    }
    if (backend.exists(account)) {
      backend.setPassword(account, password);
    } else {
      backend.create(account, password);
    }
    backend.assignLogonRights(account);
    backend.restrictMembership(account);
  }

  @override
  String? passwordOf(String account) {
    final stored = secrets.get(serviceAccountSecretId(account));
    return stored == null ? null : utf8.decode(stored);
  }

  @override
  String? sidOf(String account) => backend.sidOf(account);
}

/// The Win32 calls of [AccountBackend].
class WindowsAccountBackend implements AccountBackend {
  const WindowsAccountBackend();

  @override
  bool exists(String name) => lookupAccountSid(name) != null;

  @override
  void create(String name, String password) {
    final status = createLocalAccount(
      name,
      password,
      'Yagura service account (managed; do not change)',
    );
    if (status != 0 && status != nerrUserExists) {
      throw Win32AccountError('NetUserAdd', status);
    }
  }

  @override
  void setPassword(String name, String password) {
    final status = setLocalAccountPassword(name, password);
    if (status != 0) throw Win32AccountError('NetUserSetInfo', status);
  }

  @override
  void assignLogonRights(String name) {
    final sid = lookupAccountSid(name);
    if (sid == null) throw Win32AccountError('LookupAccountName', 1332);
    final binary = stringToSid(sid);
    addAccountRights(binary, [...logonRightsGranted, ...logonRightsDenied]);
  }

  @override
  void restrictMembership(String name) {
    final users = accountNameOfSid(usersGroupSid) ?? 'Users';
    final member = qualifyLocalAccount(
      name,
      Platform.environment['COMPUTERNAME'],
    );
    addToLocalGroup(users, member);
    for (final group in localGroupsOf(name)) {
      if (group.toLowerCase() != users.toLowerCase()) {
        removeFromLocalGroup(group, member);
      }
    }
  }

  @override
  String? sidOf(String name) => lookupAccountSid(name);
}
