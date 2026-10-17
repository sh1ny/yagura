import 'dart:async';

import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';

void main() {
  test('infinite_loop_interrupted', () async {
    final env = TestEnv();
    env.installValheim(
      hooks: 'exports.onPreStart = () => { while (true) {} };',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    final api = await ApiHarness.start(env, daemon: daemon);

    final clock = Stopwatch()..start();
    final operation = await api.instances.start(
      pb.LifecycleRequest(instanceId: instance.id),
    );

    // While the hook spins, the daemon keeps answering other calls.
    final answered = <Duration>[];
    var finished = false;
    unawaited(
      daemon.operations.whenDone(operation.id).then((_) => finished = true),
    );
    while (!finished) {
      final before = clock.elapsed;
      await api.system.getInfo(pb.GetInfoRequest());
      answered.add(clock.elapsed - before);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (clock.elapsed > const Duration(seconds: 20)) {
        fail('the start did not end');
      }
    }
    final elapsed = clock.elapsed;

    final done = await api.operations.getOperation(
      pb.GetOperationRequest(operationId: operation.id),
    );
    expect(done.status, pb.OperationStatus.OPERATION_STATUS_FAILED);
    expect(done.resultReason, 'hook_timeout');
    expect(done.resultMessage, contains('onPreStart'));
    expect(
      elapsed,
      lessThan(const Duration(seconds: 6)),
      reason: 'the start fails within 6 s',
    );
    expect(answered.length, greaterThan(10), reason: 'answered throughout');
    expect(
      answered.reduce((a, b) => a > b ? a : b),
      lessThan(const Duration(seconds: 1)),
      reason: 'no call waited for the hook',
    );
  });
}
