import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/steam_account_support.dart';
import '../support/secret_support.dart';

const _succeeded = pb.OperationStatus.OPERATION_STATUS_SUCCEEDED;
const _failed = pb.OperationStatus.OPERATION_STATUS_FAILED;

void main() {
  test('password_absent_from_output', () async {
    // Plain mode: the fake prints at once and writes no log, and it echoes
    // its command line, which carries the password and the code.
    final rig = await AccountRig.start(
      realOutput: false,
      fakeEnvironment: {'FAKE_STEAMCMD_ECHO_ARGV': '1'},
    );
    rig.steam.script.rules([
      loginRule(3, 'code_accepted'),
      loginRule(2, 'email_code_asked'),
    ]);
    final started = await rig.add('srvadmin');
    final events = EventLog.of(rig.api, started.id);
    final waiting = await rig.waitForPrompt(started.id);
    await rig.respond(waiting, 'F3K9P');
    final done = await rig.finish(started.id);
    expect(done.status, _succeeded, reason: done.resultMessage);
    await events.whenDone();

    final echoed = events.events
        .where((e) => e.hasLog() && e.log.text.contains('Command line: +login'))
        .toList();
    expect(echoed, isNotEmpty, reason: 'the echo reached the operation');
    for (final line in echoed) {
      expect(line.log.text, contains('***'));
    }
    expect(events.allText, isNot(contains(testPassword)));
    expect(events.allText, isNot(contains('F3K9P')));
    expect(done.writeToJson(), isNot(contains(testPassword)));
    final logs = [
      ...rig.steam.log,
      ...rig.api.logLines,
      for (final notice in rig.daemon.startupNotices) notice.message,
    ].join('\n');
    expect(logs, isNot(contains(testPassword)));
    expect(logs, isNot(contains('F3K9P')));
    expect(
      filesContaining(Directory(rig.env.data), testPassword),
      isEmpty,
      reason: 'no file of the data directory holds the password',
    );
    expect(filesContaining(Directory(rig.env.data), 'F3K9P'), isEmpty);
  });

  test('password_absent_from_a_failure', () async {
    // The command line is echoed and the login fails: the failure carries the
    // last output lines, which must not hold the password.
    final rig = await AccountRig.start(
      realOutput: false,
      fakeEnvironment: {'FAKE_STEAMCMD_ECHO_ARGV': '1'},
    );
    rig.steam.script.rules([loginRule(2, 'wrong_password')]);

    final done = await rig.finish((await rig.add('srvadmin')).id);

    expect(done.status, _failed);
    expect(done.resultReason, 'steam_login_invalid');
    expect(done.writeToJson(), isNot(contains(testPassword)));
    expect(
      rig.api.logLines.join('\n') + rig.steam.log.join('\n'),
      isNot(contains(testPassword)),
    );
  });

  test('remember_password', () async {
    final rig = await AccountRig.start();
    final kept = await rig.addReady('remembered', remember: true);
    final dropped = await rig.addReady('forgotten', password: 'Other-pw-8-Q');

    expect(kept.passwordRemembered, isTrue);
    expect(dropped.passwordRemembered, isFalse);
    expect(
      rig.daemon.secrets.get('steam:${kept.id}'),
      Uint8List.fromList(testPassword.codeUnits),
      reason: 'the password is in the secret store',
    );
    expect(rig.daemon.secrets.contains('steam:${dropped.id}'), isFalse);
    expect(
      filesContaining(Directory(rig.env.data), testPassword),
      isEmpty,
      reason: 'the store keeps it encrypted: no plain copy on disk',
    );
    expect(filesContaining(Directory(rig.env.data), 'Other-pw-8-Q'), isEmpty);
  });

  test('secret_store_refuses_the_password', () async {
    final protector = FlakySecretProtector(devSid);
    final rig = await AccountRig.start(secretProtector: protector);
    protector.failWrites = true;
    rig.steam.script.rules([loginRule(2, 'code_accepted')]);

    final done = await rig.finish(
      (await rig.add('srvadmin', remember: true)).id,
    );

    expect(done.status, _failed);
    expect(done.resultReason, 'secret_store_unavailable');
    expect(await rig.accounts(), isEmpty, reason: 'no account is saved');
    expect(rig.accountInstallations(), isEmpty);
  });
}
