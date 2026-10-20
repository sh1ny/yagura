import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/api_support.dart';
import '../support/steam_account_support.dart';
import '../support/steam_support.dart';

const _succeeded = pb.OperationStatus.OPERATION_STATUS_SUCCEEDED;

void main() {
  test('password_not_remembered_and_cache_valid', () async {
    final rig = await AccountRig.start();
    final account = await rig.addReady('srvadmin');
    expect(account.passwordRemembered, isFalse);
    expect(rig.daemon.secrets.contains('steam:${account.id}'), isFalse);
    rig.steam.script.rules([loginRule(1, 'cached_ok')]);
    final instance = await rig.linkedInstance(account.id);

    final installed = await rig.daemon.operations.whenDone(
      rig.daemon.instances.install(instance.id).id,
    );
    final updated = await rig.daemon.operations.whenDone(
      rig.daemon.instances.update(instance.id, skipSnapshot: true).id,
    );

    expect(
      installed.status,
      OperationStatus.succeeded,
      reason: installed.resultMessage,
    );
    expect(
      updated.status,
      OperationStatus.succeeded,
      reason: updated.resultMessage,
    );
    final runs = rig.steam.appRuns();
    expect(runs, hasLength(2));
    for (final run in runs) {
      final args = (run['args']! as List).cast<String>();
      final login = args.indexOf('+login');
      expect(args[login + 1], 'srvadmin');
      expect(args[login + 2], startsWith('+'), reason: 'username only');
      expect(
        p.equals(run['cwd']! as String, rig.installationOf(account.id)),
        isTrue,
        reason: 'it runs in the account\'s installation',
      );
    }
    expect(rig.daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect((await rig.accountNamed('srvadmin')).status, 'ready');
  });

  test('cached_login_expired', () async {
    final rig = await AccountRig.start();
    final account = await rig.addReady('srvadmin');
    rig.steam.script.rules([loginRule(1, 'cached_missing')]);
    final instance = await rig.linkedInstance(account.id);

    final done = await rig.daemon.operations.whenDone(
      rig.daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'steam_reauth_required');
    expect((await rig.accountNamed('srvadmin')).status, 'reauth_required');
    expect(
      rig.daemon.instances.get(instance.id).state,
      InstanceState.notInstalled,
    );

    // The client offers to enter the password again for that account.
    rig.steam.script.rules([loginRule(2, 'code_accepted')]);
    final reauth = await rig.reauth(account.id);
    expect(reauth.kind, 'reauth_steam_account');
    final ended = await rig.finish(reauth.id);
    expect(ended.status, _succeeded, reason: ended.resultMessage);
    expect((await rig.accountNamed('srvadmin')).status, 'ready');
  });

  test('a_flagged_account_fails_without_running_steamcmd', () async {
    final rig = await AccountRig.start();
    final account = await rig.addReady('srvadmin');
    rig.steam.script.rules([loginRule(1, 'cached_missing')]);
    final instance = await rig.linkedInstance(account.id);
    await rig.daemon.operations.whenDone(
      rig.daemon.instances.install(instance.id).id,
    );
    final runsBefore = rig.steam.runs().length;

    final again = await rig.daemon.operations.whenDone(
      rig.daemon.instances.install(instance.id).id,
    );

    expect(again.resultReason, 'steam_reauth_required');
    expect(rig.steam.runs(), hasLength(runsBefore), reason: 'no SteamCMD run');
  });

  test('remembered_password_needs_steam_guard_during_an_update', () async {
    final rig = await AccountRig.start();
    final account = await rig.addReady('srvadmin', remember: true);
    expect(account.passwordRemembered, isTrue);
    final marker = p.join(rig.env.root.path, 'logged_in');
    // The cache is gone until a login with a code works; then it is valid.
    rig.steam.script.rules([
      loginRule(3, 'code_accepted', creates: marker),
      loginRule(2, 'email_code_asked'),
      loginRule(1, 'cached_missing', unless: marker),
      loginRule(1, 'cached_ok'),
    ]);
    final instance = await rig.linkedInstance(account.id);

    final install = rig.daemon.instances.install(instance.id);
    final waiting = await rig.waitForPrompt(install.id);
    expect(waiting.instanceId, instance.id);
    expect(waiting.pendingPrompt.kind, 'email');
    expect(waiting.pendingPrompt.steamAccount, 'srvadmin');
    final events = EventLog.of(rig.api, install.id);

    await rig.respond(waiting, 'F3K9P');
    final done = await rig.daemon.operations.whenDone(install.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(rig.steam.appRuns(), isNotEmpty, reason: 'the download went on');
    expect(
      File(
        p.join(
          rig.daemon.instances.get(instance.id).directory,
          'server',
          'app_$valheimAppId.bin',
        ),
      ).existsSync(),
      isTrue,
    );
    await events.whenDone();
    expect(events.prompts, hasLength(1));
    expect(events.resolutions.single.promptResolved.outcome, 'answered');
    expect((await rig.accountNamed('srvadmin')).status, 'ready');
  });

  test('account_removed_while_in_use', () async {
    final rig = await AccountRig.start();
    final account = await rig.addReady('srvadmin');
    final instance = await rig.linkedInstance(account.id);

    final error = await failureOf(
      rig.client.removeAccount(pb.RemoveAccountRequest(accountId: account.id)),
    );

    expect(error.code, StatusCode.failedPrecondition);
    expect(errorDetailOf(error)?.reason, 'account_in_use');
    expect(
      error.message,
      contains(instance.id),
      reason: 'it names the instance',
    );
    final kept = await rig.accountNamed('srvadmin');
    expect(kept.usedByInstanceIds, [instance.id]);
    expect(Directory(rig.installationOf(account.id)).existsSync(), isTrue);
  });

  test(
    'an_unused_account_is_removed_with_its_secret_and_installation',
    () async {
      final rig = await AccountRig.start();
      final account = await rig.addReady('srvadmin', remember: true);
      expect(rig.daemon.secrets.contains('steam:${account.id}'), isTrue);

      final left = await rig.client.removeAccount(
        pb.RemoveAccountRequest(accountId: account.id),
      );

      expect(left.accounts, isEmpty);
      expect(rig.daemon.secrets.contains('steam:${account.id}'), isFalse);
      expect(Directory(rig.installationOf(account.id)).existsSync(), isFalse);
    },
  );
}
