import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/process/process_host.dart';
import 'package:yagurad/src/process/run_files.dart';
import 'package:yagurad/src/process/windows_process_host.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';

/// A launch of the `fake_server` fixture in its own run directory under
/// [root].
LaunchRequest fakeLaunch(ProcessRig rig, String root, String name) {
  final dir = p.join(root, name);
  return LaunchRequest(
    instanceId: name,
    runId: 'run-$name',
    executable: rig.tools.fakeServer,
    args: ['--state-dir', p.join(dir, 'state')],
    env: const {},
    workingDirectory: dir,
    instanceDirectory: dir,
    runDirectory: p.join(dir, 'run'),
  );
}

void main() {
  test(
    'a daemon run through the Dart VM refuses to launch with a clear reason',
    () async {
      // Under `dart run` the helper modes would be handed to dart.exe, which
      // answers "Could not find a command named launch".
      final dir = Directory.systemTemp.createTempSync('yagura_host_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final host = WindowsProcessHost(
        helperExecutable: Platform.resolvedExecutable,
      );

      await expectLater(
        host.launch(
          LaunchRequest(
            instanceId: 'inst-1',
            runId: 'run-1',
            executable: p.join(dir.path, 'server.exe'),
            args: const [],
            env: const {},
            workingDirectory: dir.path,
            instanceDirectory: dir.path,
            runDirectory: p.join(dir.path, 'run'),
          ),
        ),
        failsWith('launch_failed', messageHas: ['dart build cli']),
      );
    },
    testOn: 'windows',
  );

  test(
    'a_timed_out_launch_leaves_no_server',
    () async {
      final rig = await ProcessRig.create();
      // Zero patience: the host gives up before the relay started a server.
      final host = WindowsProcessHost(
        helperExecutable: rig.tools.yagurad,
        launchTimeout: Duration.zero,
      );

      // The relay can win the race to the first poll: try again then.
      for (var attempt = 0; attempt < 5; attempt++) {
        final request = fakeLaunch(rig, rig.env.root.path, 'late$attempt');
        final RunningServer server;
        try {
          server = await host.launch(request);
        } on YaguraException catch (e) {
          expect(e.reason, 'launch_failed');
          final files = RunFiles(request.runDirectory);
          // A relay that was not stopped records its server a moment later.
          await eventually(
            () =>
                files.readRelay()?.server != null ||
                files.readExitCode() != null ||
                files.readError() != null,
            reason: 'the relay settled',
            timeout: const Duration(seconds: 20),
          );
          final recorded = files.readRelay()?.server;
          if (recorded != null) {
            expect(
              await host.isAlive(recorded),
              isFalse,
              reason: 'the server of a failed launch must not stay alive',
            );
          }
          final pidFile = File(
            p.join(request.instanceDirectory, 'state', 'pid.txt'),
          );
          if (pidFile.existsSync()) {
            await eventually(
              () => !processAlive(int.parse(pidFile.readAsStringSync())),
              reason: 'the server that was started was ended',
            );
          }
          return;
        }
        host.release(server);
        await host.terminate(server.identity);
      }
      fail('the relay recorded its server before the first poll every time');
    },
    tags: ['windows'],
    skip: Platform.isWindows ? false : 'needs Windows',
  );

  test(
    'stop_does_not_signal_a_reused_relay_pid',
    () async {
      final rig = await ProcessRig.create();
      final host = rig.newHost();
      final root = rig.env.root.path;
      final server = await host.launch(fakeLaunch(rig, root, 'a'));
      // Another application's console: a second server behind its own relay.
      final other = await host.launch(fakeLaunch(rig, root, 'b'));
      final otherRelay = other.relay!;
      // A persisted relay record whose PID now belongs to that application.
      final reused = ProcessIdentity(
        pid: otherRelay.pid,
        executable: otherRelay.executable,
        created: otherRelay.created + 1,
      );
      final attached = (await host.reattach(server.identity, relay: reused))!;

      final stoppedBy = await host.stop(
        attached,
        const StopPlan(
          strategy: StopStrategy.signal,
          grace: Duration(seconds: 5),
        ),
      );

      expect(stoppedBy, StoppedBy.graceful);
      expect(
        File(p.join(root, 'a', 'state', 'ctrlc.txt')).existsSync(),
        isTrue,
        reason: 'the server got Ctrl+C through its own console',
      );
      expect(
        File(p.join(root, 'b', 'state', 'ctrlc.txt')).existsSync(),
        isFalse,
        reason: 'the console behind the reused PID was left alone',
      );
      expect(await host.isAlive(other.identity), isTrue);
    },
    tags: ['windows'],
    skip: Platform.isWindows ? false : 'needs Windows',
  );
}
