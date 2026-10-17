import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';

void main() {
  test(
    'daemon_killed_during_a_stop',
    () async {
      // The server needs 4 s to save after Ctrl+C.
      final rig = await ProcessRig.create(
        serverArgs: ['--save-ms', '4000'],
        graceSeconds: 30,
      );
      final first = await rig.start();
      final instance = await rig.createRunning(first);
      final pid = instance.pid;
      first.instances.stop(instance.id);
      await eventually(
        () => File(rig.stateFile(instance, 'ctrlc.txt')).existsSync(),
        reason: 'Ctrl+C to reach the server',
      );
      expect(File(rig.stateFile(instance, 'saved.txt')).existsSync(), isFalse);

      // The daemon dies while the server is still saving.
      await rig.env.kill(first);
      expect(processAlive(pid), isTrue);
      final second = await rig.start();
      final crashes = collectNotices(second, 'crashed');

      expect(second.instances.get(instance.id).state, InstanceState.stopping);
      await eventually(
        () => second.instances.get(instance.id).state == InstanceState.stopped,
        timeout: const Duration(seconds: 20),
        reason: 'the stop to finish',
      );
      expect(File(rig.stateFile(instance, 'saved.txt')).existsSync(), isTrue);
      expect(processAlive(pid), isFalse);
      // Not a crash and not restarted.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(crashes, isEmpty);
      expect(second.instances.get(instance.id).state, InstanceState.stopped);
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  test('a_resumed_stop_ends_when_the_server_exits', () async {
    final env = TestEnv();
    env.installValheim();
    final first = await env.start();
    final instance = await createRunning(first);
    final server = env.process.servers.single;
    env.process.stopGate = Completer<void>().future;
    first.instances.stop(instance.id);
    await eventually(
      () => first.instances.get(instance.id).state == InstanceState.stopping,
      reason: 'the stop to begin',
    );
    await env.kill(first);
    env.process.survivors.add(server);

    final second = await env.start();
    final crashes = collectNotices(second, 'crashed');

    expect(second.instances.get(instance.id).state, InstanceState.stopping);
    server.exit(0);
    await eventually(
      () => second.instances.get(instance.id).state == InstanceState.stopped,
      reason: 'the resumed stop',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(crashes, isEmpty);
    expect(env.process.launches, hasLength(1));
    expect(second.instances.get(instance.id).state, InstanceState.stopped);
  });
}
