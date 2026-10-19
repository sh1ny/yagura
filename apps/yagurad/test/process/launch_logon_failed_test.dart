import 'package:test/test.dart';
import 'package:yagurad/src/process/launcher_modes.dart';
import 'package:yagurad/src/process/windows_process_host.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';
import 'windows_process_host_test.dart' show fakeLaunch;

// Design D7: a logon that fails surfaces as `launch_logon_failed`. The real
// logon of a real account is an `elevated` row (logon_fails); here the account
// does not exist, so the logon fails without any account being involved.

void main() {
  group('credentials', () {
    test('travel as one line of JSON', () {
      const credentials = AccountCredentials('yagura-srv', 'pa"ss\\word');

      final line = credentials.encode();
      final decoded = AccountCredentials.decode(line);

      expect(line, isNot(contains('\n')));
      expect(decoded!.account, 'yagura-srv');
      expect(decoded.password, 'pa"ss\\word');
    });

    test('anything else is not credentials', () {
      expect(AccountCredentials.decode(null), isNull);
      expect(AccountCredentials.decode('not json'), isNull);
      expect(AccountCredentials.decode('{"account": 1}'), isNull);
    });
  });

  group('launch_logon_failed', () {
    test(
      'without a stored password the launch fails and starts nothing',
      () async {
        final rig = await ProcessRig.create();
        final host = WindowsProcessHost(
          helperExecutable: rig.tools.yagurad,
          account: ServerAccount(name: 'yagura-srv', password: () => null),
        );

        await expectLater(
          host.launch(fakeLaunch(rig, rig.env.root.path, 'no-password')),
          failsWith('launch_logon_failed', messageHas: ['yagura-srv']),
        );
      },
      tags: ['windows'],
    );

    test('an account that cannot log on fails the launch', () async {
      final rig = await ProcessRig.create();
      final host = WindowsProcessHost(
        helperExecutable: rig.tools.yagurad,
        launcherTimeout: const Duration(seconds: 60),
        account: ServerAccount(
          name: 'yagura-no-such-account',
          password: () => 'Wr0ng-Password-For-A-Missing-Account!',
        ),
      );

      await expectLater(
        host.launch(fakeLaunch(rig, rig.env.root.path, 'bad-logon')),
        failsWith(
          'launch_logon_failed',
          messageHas: ['yagura-no-such-account', 'logon_failed'],
        ),
      );
    }, tags: ['windows']);
  });
}
