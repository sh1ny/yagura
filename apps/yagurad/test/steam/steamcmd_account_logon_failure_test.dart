@Tags(['windows'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_logon.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/daemon_support.dart';
import '../support/temp_support.dart';

final onWindows = Platform.isWindows ? false : 'needs Windows';

Future<SteamProcess> _start(SteamAccount account) =>
    JobObjectLauncher(account: account).start(Platform.resolvedExecutable, [
      '--version',
    ], workingDirectory: canonicalSystemTemp().path);

// Design D10, failure table: "SteamCMD as yagura-steam / Logon fails:
// Operation fails launch_logon_failed", the reason the game-server path gives
// for the same fault. A client cannot tell an account problem from a broken
// SteamCMD download when both are `steamcmd_unavailable`.
void main() {
  test('a_missing_password_is_a_logon_failure', () async {
    await expectLater(
      _start(SteamAccount(name: 'yagura-steam', password: () => null)),
      failsWith(
        'launch_logon_failed',
        messageHas: ['yagura-steam', 'no stored password'],
      ),
    );
  }, skip: onWindows);

  test('an_account_that_cannot_be_logged_on_is_a_logon_failure', () async {
    // No such account: the logon module fails before any process starts.
    await expectLater(
      _start(SteamAccount(name: 'yagura-no-such-account', password: () => 'x')),
      failsWith(
        'launch_logon_failed',
        messageHas: ['yagura-no-such-account', 'error'],
      ),
    );
  }, skip: onWindows);

  // A missing or quarantined steamcmd.exe fails CreateProcessAsUserW, not the
  // logon: it stays steamcmd_unavailable so that ADR 0014 rebuilds the
  // installation instead of sending the admin to the account.
  test('only_the_logon_steps_are_logon_failures', () {
    for (final call in [
      'LookupAccountName',
      'LogonUserW',
      'LoadUserProfileW',
      'CreateEnvironmentBlock',
      'CreateWindowStationW',
    ]) {
      expect(
        launchFailureKind(LogonFailure('yagura-steam', call, 5)),
        'logon_failed',
        reason: call,
      );
    }
    for (final call in [
      'CreateProcessAsUserW',
      'InitializeProcThreadAttributeList',
      'UpdateProcThreadAttribute',
    ]) {
      expect(
        launchFailureKind(
          LogonFailure('yagura-steam', call, 2, stage: LogonStage.process),
        ),
        'failed',
        reason: call,
      );
    }
    expect(launchFailureKind(const FileSystemException('pipe')), 'failed');
  });
}
