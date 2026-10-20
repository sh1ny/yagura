import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/files/instance_fs.dart';
import 'package:yagurad/src/platform/win32_process.dart';
import 'package:yagurad/src/process/relay_run_files.dart';
import 'package:yagurad/src/process/process_host.dart';
import 'package:yagurad/src/process/run_files.dart';
import 'package:yagurad/src/process/windows_process_host.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';
import '../support/temp_support.dart';

/// A launch of the `fake_server` fixture in its own run directory under
/// [root].
LaunchRequest fakeLaunch(ProcessRig rig, String root, String name) {
  final dir = p.join(root, name);
  // The instance directory exists before a launch (the daemon created it).
  Directory(dir).createSync(recursive: true);
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
      final dir = createCanonicalTempSync('yagura_host_');
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
    'an_abandoned_launch_ends_only_what_the_launched_relay_started',
    () async {
      // relay.json is written by the game-server account: it can name another
      // instance's server. Only a verified server of the relay the launcher
      // reported, or that relay's own child, is ended (design D9).
      final rig = await ProcessRig.create();
      final host = WindowsProcessHost(
        helperExecutable: rig.tools.yagurad,
        abandonTimeout: const Duration(milliseconds: 300),
      );
      final dir = Directory(p.join(rig.env.root.path, 'abandon'))
        ..createSync(recursive: true);
      Future<Process> start(String name) async {
        final process = await Process.start(rig.tools.fakeServer, [
          '--state-dir',
          p.join(dir.path, name),
        ]);
        addTearDown(process.kill);
        return process;
      }

      final bystander = await start('bystander');
      final launchedRelay = await start('relay');
      await eventually(
        () =>
            identityOfPid(bystander.pid) != null &&
            identityOfPid(launchedRelay.pid) != null,
        reason: 'both processes to be visible',
      );
      final runDirectory = p.join(dir.path, 'run');
      Directory(runDirectory).createSync(recursive: true);
      final files = RunFiles(runDirectory, fs: InstanceFs(dir.path));
      // The record names the bystander as the server of the launched relay,
      // which is not its parent.
      files.writeRelayAndServer(
        identityOfPid(launchedRelay.pid)!,
        identityOfPid(bystander.pid)!,
      );

      await host.abandonLaunch(files, identityOfPid(launchedRelay.pid));

      expect(
        processAlive(bystander.pid),
        isTrue,
        reason: 'a process the relay did not start is not ended',
      );
    },
    tags: ['windows'],
    skip: Platform.isWindows ? false : 'needs Windows',
  );

  test(
    'a_launcher_that_times_out_cancels_the_run',
    () async {
      // The launcher may already have started the relay: the cancel file
      // keeps it from starting (or keeping) a server after Start failed.
      final rig = await ProcessRig.create();
      // A helper that never finishes: the fixture ignores its arguments.
      final host = WindowsProcessHost(
        helperExecutable: rig.tools.fakeServer,
        launcherTimeout: const Duration(milliseconds: 300),
      );
      final request = fakeLaunch(rig, rig.env.root.path, 'slow');

      await expectLater(
        host.launch(request),
        failsWith('launch_failed', messageHas: ['launcher did not finish']),
      );

      expect(RunFiles(request.runDirectory).isCancelled, isTrue);
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
      // A persisted relay record that no longer matches the process with that
      // PID (the relay ended and its PID was reused: the start time differs).
      // The server's parent PID is still the recorded one (design D9), and the
      // relay was created before it.
      final realRelay = server.relay!;
      final reused = ProcessIdentity(
        pid: realRelay.pid,
        executable: realRelay.executable,
        created: realRelay.created + 1,
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
