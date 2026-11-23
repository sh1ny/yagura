import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';
import '../support/steam_account_support.dart';
import '../support/steam_support.dart';

const _succeeded = pb.OperationStatus.OPERATION_STATUS_SUCCEEDED;
const _failed = pb.OperationStatus.OPERATION_STATUS_FAILED;
const _interrupted = pb.OperationStatus.OPERATION_STATUS_INTERRUPTED;

void main() {
  test('login_waits_default_to_the_spec_values', () {
    final service = SteamCmdService(steamcmdRoot: 'unused');
    addTearDown(service.close);
    expect(service.codeWait, const Duration(minutes: 15));
    expect(service.mobileWait, const Duration(minutes: 2));
    expect(service.loginSilence, const Duration(seconds: 60));
    expect(service.loginCap, const Duration(minutes: 10));
  });

  test('email_code_relayed', () async {
    final rig = await AccountRig.start();
    rig.steam.script.rules([
      loginRule(3, 'code_accepted'),
      loginRule(2, 'email_code_asked'),
    ]);

    final started = await rig.add('srvadmin');
    expect(started.kind, 'add_steam_account');
    expect(
      started.instanceId,
      isEmpty,
      reason: 'an account belongs to no instance',
    );
    final events = EventLog.of(rig.api, started.id);

    final waiting = await rig.waitForPrompt(started.id);
    final prompt = waiting.pendingPrompt;
    expect(prompt.kind, 'email');
    expect(prompt.steamAccount, 'srvadmin');
    final left = prompt.expiresAt.toDateTime().difference(DateTime.now());
    expect(
      left.inSeconds,
      inInclusiveRange(14 * 60, 15 * 60),
      reason: 'a code is waited for 15 minutes',
    );
    expect(
      (await rig.accountNamed('srvadmin')).status,
      'adding',
      reason: 'the account is listed while it is added',
    );

    await rig.respond(waiting, 'F3K9P');
    final done = await rig.finish(started.id);

    expect(done.status, _succeeded, reason: done.resultMessage);
    final account = await rig.accountNamed('srvadmin');
    expect(account.status, 'ready');
    expect(account.passwordRemembered, isFalse);
    expect(account.hasLastLoginAt(), isTrue);
    expect(rig.loginArguments(), [
      ['srvadmin', testPassword],
      ['srvadmin', testPassword, 'F3K9P'],
    ], reason: 'the login is retried once, with the code');
    await events.whenDone();
    expect(events.prompts.single.prompt.kind, 'email');
    expect(events.resolutions.single.promptResolved.outcome, 'answered');
    expect(
      Directory(rig.installationOf(account.id)).existsSync(),
      isTrue,
      reason: 'the account has its own SteamCMD installation',
    );
  });

  test('wrong_code', () async {
    final rig = await AccountRig.start();
    rig.steam.script.rules([
      loginRule(3, 'wrong_code'),
      loginRule(2, 'email_code_asked'),
    ]);
    final started = await rig.add('srvadmin', remember: true);
    final waiting = await rig.waitForPrompt(started.id);
    final accountId = (await rig.accountNamed('srvadmin')).id;

    await rig.respond(waiting, 'BADC0');
    final done = await rig.finish(started.id);

    expect(done.status, _failed);
    expect(done.resultReason, 'steam_guard_invalid');
    expect(await rig.accounts(), isEmpty, reason: 'the account is not saved');
    expect(
      rig.daemon.secrets.contains('steam:$accountId'),
      isFalse,
      reason: 'the password is discarded',
    );
    expect(rig.accountInstallations(), isEmpty);
    expect(
      rig.loginArguments(),
      hasLength(2),
      reason: 'the code is tried once',
    );
  });

  test('no_code_submitted_in_time', () async {
    final rig = await AccountRig.start(
      codeWait: const Duration(milliseconds: 800),
    );
    rig.steam.script.rules([loginRule(2, 'email_code_asked')]);
    final started = await rig.add('srvadmin');
    final events = EventLog.of(rig.api, started.id);

    await rig.waitForPrompt(started.id);
    final done = await rig.finish(started.id);

    expect(done.status, _failed);
    expect(done.resultReason, 'steam_guard_timeout');
    expect(await rig.accounts(), isEmpty);
    expect(rig.accountInstallations(), isEmpty);
    await events.whenDone();
    expect(events.resolutions.single.promptResolved.outcome, 'expired');
    expect(rig.loginArguments(), hasLength(1), reason: 'no second run');
  });

  test('mobile_approval_not_given', () async {
    final rig = await AccountRig.start(
      mobileWait: const Duration(seconds: 1),
      fakeEnvironment: {'FAKE_STEAMCMD_WAITING_MS': '100'},
    );
    rig.steam.script.rules([loginRule(2, 'mobile_never')]);
    final started = await rig.add('srvadmin');

    final waiting = await rig.waitForPrompt(started.id);
    expect(waiting.pendingPrompt.kind, 'mobile_approval');
    expect(waiting.pendingPrompt.steamAccount, 'srvadmin');
    final pid = rig.steam.runs().last['pid']! as int;
    final done = await rig.finish(started.id);

    expect(done.status, _failed);
    expect(done.resultReason, 'steam_guard_timeout');
    expect(await rig.accounts(), isEmpty);
    await eventually(
      () => !Process.killPid(pid),
      reason: 'the SteamCMD run is terminated',
    );
  });

  test('mobile_approval_given', () async {
    final rig = await AccountRig.start(
      fakeEnvironment: {
        'FAKE_STEAMCMD_WAITING_MS': '100',
        'FAKE_STEAMCMD_APPROVAL_DELAY_MS': '700',
      },
    );
    rig.steam.script.rules([loginRule(2, 'mobile_approved')]);
    final started = await rig.add('srvadmin');
    final events = EventLog.of(rig.api, started.id);

    final waiting = await rig.waitForPrompt(started.id);
    expect(waiting.pendingPrompt.kind, 'mobile_approval');
    final done = await rig.finish(started.id);

    expect(done.status, _succeeded, reason: done.resultMessage);
    expect((await rig.accountNamed('srvadmin')).status, 'ready');
    await events.whenDone();
    expect(events.resolutions, hasLength(1));
  });

  test('wrong_password', () async {
    final rig = await AccountRig.start();
    rig.steam.script.rules([loginRule(2, 'wrong_password')]);
    final started = await rig.add('srvadmin');
    final events = EventLog.of(rig.api, started.id);

    final done = await rig.finish(started.id);

    expect(done.status, _failed);
    expect(done.resultReason, 'steam_login_invalid');
    expect(await rig.accounts(), isEmpty);
    await events.whenDone();
    expect(events.prompts, isEmpty, reason: 'no prompt is raised');
    expect(rig.loginArguments(), hasLength(1));
  });

  test('steamcmd_does_not_respond', () async {
    // Long enough for the fake's VM to start and write its banner (it can
    // take over 1 s on a loaded machine); that line restarts the bound.
    final rig = await AccountRig.start(
      loginSilence: const Duration(seconds: 3),
    );
    rig.steam.script.rules([
      {'argc': 2, 'stall': true},
    ]);
    final started = await rig.add('srvadmin');
    final events = EventLog.of(rig.api, started.id);

    final done = await rig.finish(started.id);

    expect(done.status, _failed);
    expect(done.resultReason, 'steam_login_unresponsive');
    expect(
      done.resultMessage,
      contains('Steam Console Client'),
      reason: 'the last lines of console_log.txt',
    );
    expect(done.resultMessage, isNot(contains(testPassword)));
    expect(await rig.accounts(), isEmpty);
    await events.whenDone();
    expect(events.prompts, isEmpty);
    final pid = rig.steam.runs().last['pid']! as int;
    await eventually(
      () => !Process.killPid(pid),
      reason: 'the SteamCMD run is terminated',
    );
  });

  test('daemon_restarted_while_adding', () async {
    final env = TestEnv();
    final rig = await AccountRig.start(env: env);
    rig.steam.script.rules([loginRule(2, 'email_code_asked')]);
    final started = await rig.add('srvadmin', remember: true);
    await rig.waitForPrompt(started.id);
    final account = await rig.accountNamed('srvadmin');
    expect(Directory(rig.installationOf(account.id)).existsSync(), isTrue);
    // A leftover password of an add that stored it early: the restart must
    // not leave it behind.
    rig.daemon.secrets.put(
      'steam:${account.id}',
      Uint8List.fromList(testPassword.codeUnits),
    );

    await env.kill(rig.daemon);
    final steam = SteamHarness(
      env,
      realOutput: true,
      bootstrap: DirectoryBootstrap(),
    );
    final daemon = await env.start(
      steamService: steam.service,
      secretProtector: FakeSecretProtector(devSid),
    );
    final api = await ApiHarness.start(env, daemon: daemon);

    final op = await api.operations.getOperation(
      pb.GetOperationRequest(operationId: started.id),
    );
    expect(op.status, _interrupted);
    expect(
      (await api.steam.listAccounts(pb.ListAccountsRequest())).accounts,
      isEmpty,
    );
    expect(daemon.secrets.contains('steam:${account.id}'), isFalse);
    expect(
      Directory(p.join(steam.root, account.id)).existsSync(),
      isFalse,
      reason: 'its SteamCMD installation is removed',
    );
    final prompts = await api.operations
        .watchPrompts(pb.WatchPromptsRequest())
        .first;
    expect(prompts.snapshot.prompts, isEmpty);
  });

  test('account_already_added', () async {
    final rig = await AccountRig.start();
    await rig.addReady('srvadmin');
    final before = (await rig.api.operations.listOperations(
      pb.ListOperationsRequest(),
    )).operations.length;

    final error = await failureOf(rig.add('srvadmin'));

    expect(error.code, StatusCode.alreadyExists);
    expect(errorDetailOf(error)?.reason, 'account_exists');
    expect(
      (await rig.api.operations.listOperations(pb.ListOperationsRequest()))
          .operations,
      hasLength(before),
      reason: 'no operation is created',
    );
    expect(await rig.accounts(), hasLength(1));
  });

  test('usernames_differing_only_in_case_are_the_same_account', () async {
    // Steam account names are case-insensitive: SrvAdmin is srvadmin.
    final rig = await AccountRig.start();
    await rig.addReady('srvadmin');

    await expectLater(
      rig.add('SrvAdmin'),
      failsWithStatus(StatusCode.alreadyExists, 'account_exists'),
    );
    expect(await rig.accounts(), hasLength(1));
  });

  test('an_account_being_added_blocks_its_username', () async {
    final rig = await AccountRig.start();
    rig.steam.script.rules([loginRule(2, 'email_code_asked')]);
    final started = await rig.add('srvadmin');
    await rig.waitForPrompt(started.id);

    await expectLater(
      rig.add('srvadmin'),
      failsWithStatus(StatusCode.alreadyExists, 'account_exists'),
    );
  });

  test('too_many_accounts', () async {
    final env = TestEnv();
    final rig = await AccountRig.start(env: env);
    await env.kill(rig.daemon);
    final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
    for (var i = 0; i < 32; i++) {
      db.sqlite.execute(
        "INSERT INTO steam_accounts (id, username, status, created_at) "
        "VALUES (?, ?, 'ready', 0)",
        ['acct_${i.toString().padLeft(12, '0')}', 'user$i'],
      );
    }
    db.close();
    final steam = SteamHarness(
      env,
      realOutput: true,
      bootstrap: DirectoryBootstrap(),
    );
    final daemon = await env.start(steamService: steam.service);
    final api = await ApiHarness.start(env, daemon: daemon);

    await expectLater(
      api.steam.addAccount(
        pb.AddAccountRequest(username: 'one_too_many', password: testPassword),
      ),
      failsWithStatus(StatusCode.resourceExhausted, 'too_many_accounts'),
    );
  });
}
