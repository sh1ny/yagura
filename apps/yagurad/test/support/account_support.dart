import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:yagurad/src/files/confined_fs.dart';
import 'package:yagurad/src/platform/acl_writer.dart';
import 'package:yagurad/src/platform/win32_account_management.dart';
import 'package:yagurad/src/platform/win32_security.dart';

import 'elevated_support.dart';

// Helpers of the `elevated` rows that look at accounts, ACLs and process
// owners. Accounts, ACLs and owners are asked of Windows directly (the
// daemon's own read-only calls); PowerShell's Security module did not load in
// the CI session, so nothing here depends on it. External commands go through
// `runCommand` of elevated_support.dart: asynchronous, with a hard timeout.

/// The string SID of the local account [name], or null. Asked of Windows
/// directly (`LookupAccountName`): no PowerShell module is involved.
Future<String?> accountSid(String name) async =>
    const WindowsAccountSids().sidOf(name);

/// The owner and DACL of [path] as SDDL (`O:BAD:P(A;...)`), read through a
/// handle opened without following a link.
Future<String> sddlOf(String path) async {
  final directory = FileSystemEntity.isDirectorySync(path);
  final fs = ConfinedFs(directory ? path : p.dirname(path));
  return fs.securityOf(directory ? '' : p.basename(path));
}

/// The SID of the owner of [path], as SDDL writes it (a string SID, or an
/// alias such as `BA`).
Future<String> ownerOf(String path) async {
  final sddl = await sddlOf(path);
  final match = RegExp(r'^O:(.*?)(?=D:|G:|S:|$)').firstMatch(sddl);
  return match?[1] ?? '';
}

/// The SID of the account a process runs as, or null when it is gone or
/// cannot be read.
Future<String?> processOwnerSid(int pid) async => processUserSid(pid);

/// Whether the local account [name] is a member of [group].
Future<bool> isMemberOf(String group, String name) async {
  final result = await runCommand('net', ['localgroup', group]);
  return '${result.stdout}'
      .split(RegExp(r'\r?\n'))
      .any((line) => line.trim().toLowerCase() == name.toLowerCase());
}

/// Removes the two service accounts and their profiles. The daemon makes them
/// with these fixed names, so a row that installs the service removes them
/// when it ends; on the throwaway runner nothing else uses them.
Future<void> removeServiceAccounts() async {
  for (final name in ['yagura-srv', 'yagura-steam']) {
    // The rights go first: `net user /delete` leaves the SID in the local
    // security policy with them.
    final sid = const WindowsAccountSids().sidOf(name);
    if (sid != null) {
      try {
        removeAllAccountRights(stringToSid(sid));
      } on Win32AccountError {
        // The account is deleted all the same.
      }
    }
    await runCommand('net', ['user', name, '/delete'], failOnTimeout: false);
    await powershell(
      "Get-CimInstance Win32_UserProfile | Where-Object { \$_.LocalPath -like "
      "'*\\$name' } | Remove-CimInstance -ErrorAction SilentlyContinue",
      failOnTimeout: false,
    );
  }
}

/// A read-only look at the daemon's database, which the service holds open.
List<Map<String, Object?>> queryDatabase(
  String dataDirectory,
  String sql, [
  List<Object?> parameters = const [],
]) {
  final path = p.join(dataDirectory, 'yagura.db');
  if (!File(path).existsSync()) return [];
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return [
      for (final row in db.select(sql, parameters))
        {for (final key in row.keys) key: row[key]},
    ];
  } finally {
    db.close();
  }
}

/// Disables the local account [name]; its next logon fails.
Future<bool> disableAccount(String name) async =>
    (await runCommand('net', ['user', name, '/active:no'])).exitCode == 0;

/// The rights the local security policy holds for the account [name], read
/// with `LsaEnumerateAccountRights` (read-only): `SeBatchLogonRight`, the
/// `SeDeny...LogonRight` ones. Empty when the account does not exist.
Future<List<String>> rightsOf(String name) async {
  final sid = const WindowsAccountSids().sidOf(name);
  return sid == null ? const [] : accountRights(stringToSid(sid));
}
