import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';

void main() {
  test(
    'long_running_executable_tracked',
    () async {
      final rig = await ProcessRig.create();
      final daemon = await rig.start();
      final instance = await rig.createRunning(daemon);
      final pid = instance.pid;

      // The recorded PID is the executable itself, run from the install
      // directory.
      expect(
        File(rig.stateFile(instance, 'pid.txt')).readAsStringSync(),
        '$pid',
      );
      expect(processAlive(pid), isTrue);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(processAlive(pid), isTrue);
      expect(daemon.instances.get(instance.id).state, InstanceState.running);

      // Its exit is detected.
      final crashed = collectNotices(daemon, 'crashed');
      Process.killPid(pid);
      await eventually(() => crashed.isNotEmpty, reason: 'the exit to be seen');
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  test(
    'bootstrapper_exits',
    () async {
      // The "launcher" ends within the health window.
      final rig = await ProcessRig.create(
        serverArgs: ['--exit-after-ms', '500', '--exit-code', '0'],
      );
      final daemon = await rig.start(
        processHealthSettle: const Duration(seconds: 3),
      );
      final instance = await rig.createInstalledFake(daemon);

      final done = await runStart(daemon, instance.id);

      expect(done.status, OperationStatus.failed);
      expect(done.resultReason, 'launch_failed');
      expect(done.resultMessage, contains('valheim_server.exe'));
      expect(done.resultMessage, contains('exit code 0'));
      expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    },
    tags: ['windows'],
    skip: windowsOnly,
  );
  test(
    'a server that exits before it is tracked fails the start at once',
    () async {
      final rig = await ProcessRig.create(
        serverArgs: ['--exit-after-ms', '0', '--exit-code', '7'],
      );
      final daemon = await rig.start();
      final instance = await rig.createInstalledFake(daemon);
      final clock = Stopwatch()..start();

      final done = await runStart(daemon, instance.id);

      expect(done.status, OperationStatus.failed);
      expect(done.resultReason, 'launch_failed');
      expect(done.resultMessage, contains('exit code 7'));
      expect(clock.elapsed, lessThan(const Duration(seconds: 15)));
      expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    },
    tags: ['windows'],
    skip: windowsOnly,
  );
}
