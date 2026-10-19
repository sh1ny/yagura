import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagurad/src/platform/win32_logon.dart';
import 'package:yagurad/src/process/process_host.dart';
import 'package:yagurad/src/process/profile_hold.dart';
import 'package:yagurad/src/process/windows_process_host.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';
import 'windows_process_host_test.dart' show fakeLaunch;

// Design D7 (amended): the launcher unloads the game-server account's profile
// once the relay has started, before the relay starts the server, so the
// service-mode host holds a load of its own while servers of the account run.
// Without it the server has no registry hive (`HKEY_CURRENT_USER`), and
// Valheim cannot save on a stop. The real profile of the real account is the
// `elevated` Valheim row; here the load is counted.

/// A profile load that only counts.
class _CountingLoad {
  var loads = 0;
  var unloads = 0;
  Object? failWith;

  void Function() call() {
    if (failWith case final error?) throw error;
    loads++;
    return () => unloads++;
  }
}

void main() {
  group('a profile hold', () {
    test('loads once for any number of holders', () {
      final load = _CountingLoad();
      final hold = ProfileHold(load.call);

      hold
        ..retain()
        ..retain()
        ..retain();

      expect(load.loads, 1);
      expect(hold.references, 3);
      expect(hold.loaded, isTrue);
    });

    test('unloads when the last holder lets go', () {
      final load = _CountingLoad();
      final hold = ProfileHold(load.call)
        ..retain()
        ..retain();

      hold.release();
      expect(load.unloads, 0, reason: 'one holder is left');
      hold.release();

      expect(load.unloads, 1);
      expect(hold.loaded, isFalse);
      expect(hold.references, 0);
    });

    test('a failed load holds nothing, and the next holder loads again', () {
      final load = _CountingLoad()
        ..failWith = const LogonFailure('yagura-srv', 'LogonUserW', 1326);
      final hold = ProfileHold(load.call);

      expect(hold.retain, throwsA(isA<LogonFailure>()));
      expect(hold.references, 0);
      expect(hold.loaded, isFalse);

      load.failWith = null;
      hold.retain();
      expect(load.loads, 1);
      expect(hold.references, 1);
    });

    test('a release with no holder does nothing', () {
      final load = _CountingLoad();
      final hold = ProfileHold(load.call)..release();

      expect(hold.references, 0);
      expect(load.unloads, 0);
    });
  });

  group('the Windows host', () {
    test(
      'holds the profile while a launched server runs, until it ends',
      () async {
        final rig = await ProcessRig.create();
        final load = _CountingLoad();
        final hold = ProfileHold(load.call);
        final host = WindowsProcessHost(
          helperExecutable: rig.tools.yagurad,
          profileHold: hold,
        );

        final server = await host.launch(
          fakeLaunch(rig, rig.env.root.path, 'held'),
        );
        expect(hold.references, 1, reason: 'the running server holds it');
        expect(load.loads, 1);

        await host.stop(
          server,
          const StopPlan(
            strategy: StopStrategy.signal,
            grace: Duration(seconds: 5),
            force: true,
          ),
        );
        await server.exitCode.timeout(const Duration(seconds: 10));

        expect(hold.references, 0);
        expect(load.unloads, 1, reason: 'the last server has ended');
      },
      tags: ['windows'],
      skip: Platform.isWindows ? false : 'needs Windows',
    );

    test(
      'keeps the profile loaded when it lets go of a running server',
      () async {
        final rig = await ProcessRig.create();
        final load = _CountingLoad();
        final hold = ProfileHold(load.call);
        final host = WindowsProcessHost(
          helperExecutable: rig.tools.yagurad,
          profileHold: hold,
        );
        final server = await host.launch(
          fakeLaunch(rig, rig.env.root.path, 'kept'),
        );

        // What a daemon that stops does with a server that keeps running.
        host.release(server);

        expect(await host.isAlive(server.identity), isTrue);
        expect(hold.references, 1);
        expect(load.unloads, 0, reason: 'the server still needs its hive');
      },
      tags: ['windows'],
      skip: Platform.isWindows ? false : 'needs Windows',
    );

    test(
      'holds the profile for a re-attached server, until it ends',
      () async {
        final rig = await ProcessRig.create();
        final first = WindowsProcessHost(helperExecutable: rig.tools.yagurad);
        final launched = await first.launch(
          fakeLaunch(rig, rig.env.root.path, 'reattached'),
        );
        first.release(launched);
        final load = _CountingLoad();
        final hold = ProfileHold(load.call);
        final host = WindowsProcessHost(
          helperExecutable: rig.tools.yagurad,
          profileHold: hold,
        );

        final server = (await host.reattach(
          launched.identity,
          relay: launched.relay,
        ))!;
        expect(hold.references, 1);

        await host.stop(
          server,
          const StopPlan(
            strategy: StopStrategy.signal,
            grace: Duration(seconds: 5),
            force: true,
          ),
        );
        await server.exitCode.timeout(const Duration(seconds: 10));

        expect(hold.references, 0);
        expect(load.unloads, 1);
      },
      tags: ['windows'],
      skip: Platform.isWindows ? false : 'needs Windows',
    );

    test(
      'gives the launch reference back when the launch fails',
      () async {
        final rig = await ProcessRig.create();
        final load = _CountingLoad();
        final hold = ProfileHold(load.call);
        final host = WindowsProcessHost(
          helperExecutable: rig.tools.yagurad,
          profileHold: hold,
        );
        final request = fakeLaunch(rig, rig.env.root.path, 'missing');

        await expectLater(
          host.launch(
            LaunchRequest(
              instanceId: request.instanceId,
              runId: request.runId,
              executable: p.join(rig.env.root.path, 'no-such-server.exe'),
              args: const [],
              env: const {},
              workingDirectory: request.workingDirectory,
              instanceDirectory: request.instanceDirectory,
              runDirectory: request.runDirectory,
            ),
          ),
          failsWith('launch_failed'),
        );

        expect(hold.references, 0);
        expect(load.unloads, load.loads);
      },
      tags: ['windows'],
      skip: Platform.isWindows ? false : 'needs Windows',
    );

    test(
      'a profile that cannot be loaded fails the launch before the launcher',
      () async {
        final rig = await ProcessRig.create();
        final load = _CountingLoad()
          ..failWith = const LogonFailure('yagura-srv', 'LogonUserW', 1326);
        final host = WindowsProcessHost(
          helperExecutable: rig.tools.yagurad,
          account: ServerAccount(name: 'yagura-srv', password: () => 'x'),
          profileHold: ProfileHold(load.call),
        );
        final request = fakeLaunch(rig, rig.env.root.path, 'unloadable');

        await expectLater(
          host.launch(request),
          failsWith(
            'launch_logon_failed',
            messageHas: ['yagura-srv', 'logon_failed', 'LogonUserW 1326'],
          ),
        );
        expect(
          File(p.join(request.runDirectory, 'relay.json')).existsSync(),
          isFalse,
          reason: 'no launcher ran',
        );
      },
      tags: ['windows'],
      skip: Platform.isWindows ? false : 'needs Windows',
    );
  });
}
