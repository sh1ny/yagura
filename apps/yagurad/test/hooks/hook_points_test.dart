import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('hook_not_exported', () async {
    final env = TestEnv();
    // hooks.js exports only onPreStart; the install runs onPostInstall.
    env.installValheim(hooks: 'exports.onPreStart = () => ({args: ["-x"]});');
    final daemon = await env.start();
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final events = await daemon.operations.watch(op.id).toList();

    final finished = (events.last as FinishedEvent).operation;
    expect(finished.status, OperationStatus.succeeded);
    expect(finished.warnings, isEmpty);
    // No hook ran, so nothing was logged and nothing was reported.
    expect(events.whereType<LogEvent>(), isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });
}
