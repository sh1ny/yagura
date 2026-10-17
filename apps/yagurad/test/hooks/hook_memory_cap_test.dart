import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('allocation_beyond_the_cap', () async {
    final env = TestEnv();
    env.installValheim(
      hooks:
          'exports.onPreStart = '
          '() => ({args: ["x".repeat(200 * 1024 * 1024)]});',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final first = await runStart(daemon, instance.id);

    expect(first.status, OperationStatus.failed);
    expect(first.resultReason, 'hook_out_of_memory');
    expect(env.process.launches, isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);

    // After 100 such hooks the daemon's memory is where it was (within
    // 32 MiB).
    final before = ProcessInfo.currentRss;
    for (var i = 1; i < 100; i++) {
      final done = await runStart(daemon, instance.id);
      expect(done.resultReason, 'hook_out_of_memory');
    }
    final grown = ProcessInfo.currentRss - before;
    expect(grown, lessThan(32 * 1024 * 1024), reason: 'RSS grew by $grown');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('oversized_result', () async {
    final env = TestEnv();
    env.installValheim(
      hooks:
          'exports.onPreStart = '
          '() => ({args: ["x".repeat(2 * 1024 * 1024)]});',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'hook_result_too_large');
    expect(env.process.launches, isEmpty);
  });
}
