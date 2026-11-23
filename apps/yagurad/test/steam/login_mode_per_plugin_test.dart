import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/steam_account_support.dart';
import '../support/steam_support.dart';

void main() {
  test('anonymous_install', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(env);
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final run = steam.appRuns().single;
    final args = (run['args']! as List).cast<String>();
    final login = args.indexOf('+login');
    expect(args.sublist(login, login + 2), ['+login', 'anonymous']);
    expect(args, containsAllInOrder(['+app_update', '$valheimAppId']));
    expect(args.last, '+quit');
    final server = p.join(instance.directory, 'server');
    expect(args[args.indexOf('+force_install_dir') + 1], server);
    expect(File(p.join(server, 'app_$valheimAppId.bin')).existsSync(), isTrue);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('optional_account_not_linked', () async {
    final env = TestEnv();
    env.installValheim(from: 'login: anonymous', to: 'login: account_optional');
    final steam = SteamHarness(env);
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final args = (steam.appRuns().single['args']! as List).cast<String>();
    final login = args.indexOf('+login');
    expect(args.sublist(login, login + 2), ['+login', 'anonymous']);
  });

  test('account_install', () async {
    final rig = await AccountRig.start();
    final account = await rig.addReady('srvadmin');
    rig.steam.script.rules([loginRule(1, 'cached_ok')]);
    final instance = await rig.linkedInstance(account.id);

    final done = await rig.daemon.operations.whenDone(
      rig.daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final run = rig.steam.appRuns().single;
    final args = (run['args']! as List).cast<String>();
    final login = args.indexOf('+login');
    expect(args.sublist(login, login + 2), ['+login', 'srvadmin']);
    expect(args, containsAllInOrder(['+app_update', '$valheimAppId']));
    expect(
      p.equals(run['cwd']! as String, rig.installationOf(account.id)),
      isTrue,
      reason: "SteamCMD runs in the account's installation",
    );
    final server = p.join(instance.directory, 'server');
    expect(args[args.indexOf('+force_install_dir') + 1], server);
    expect(File(p.join(server, 'app_$valheimAppId.bin')).existsSync(), isTrue);
    expect(rig.daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('optional_account_linked', () async {
    final rig = await AccountRig.start(login: 'account_optional');
    final account = await rig.addReady('srvadmin');
    rig.steam.script.rules([loginRule(1, 'cached_ok')]);
    final instance = await rig.linkedInstance(account.id);

    final done = await rig.daemon.operations.whenDone(
      rig.daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final run = rig.steam.appRuns().single;
    final args = (run['args']! as List).cast<String>();
    final login = args.indexOf('+login');
    expect(args.sublist(login, login + 2), ['+login', 'srvadmin']);
    expect(
      p.equals(run['cwd']! as String, rig.installationOf(account.id)),
      isTrue,
    );
  });

  test('account_login_not_available', () async {
    final env = TestEnv();
    env.installValheim(from: 'login: anonymous', to: 'login: account');
    final steam = SteamHarness(env);
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'steam_account_required');
    expect(steam.launcher.started, isEmpty, reason: 'no SteamCMD process');
    expect(steam.runs(), isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);
  });
}
