import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
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

  test(
    'an account_optional plugin installs with the anonymous login',
    () async {
      final env = TestEnv();
      env.installValheim(
        from: 'login: anonymous',
        to: 'login: account_optional',
      );
      final steam = SteamHarness(env);
      final daemon = await env.start(steamService: steam.service);
      final instance = await createValheim(daemon);

      final op = daemon.instances.install(instance.id);
      final done = await daemon.operations.whenDone(op.id);

      expect(
        done.status,
        OperationStatus.succeeded,
        reason: done.resultMessage,
      );
      final args = (steam.appRuns().single['args']! as List).cast<String>();
      final login = args.indexOf('+login');
      expect(args.sublist(login, login + 2), ['+login', 'anonymous']);
    },
  );

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
