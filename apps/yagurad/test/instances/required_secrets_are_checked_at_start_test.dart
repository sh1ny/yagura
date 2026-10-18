import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';

/// An installed Valheim instance whose `password` secret is `required`.
Future<(Daemon, Instance)> installedWithRequiredSecret(TestEnv env) async {
  env.installValheim(
    from: '  password:\n    type: secret',
    to: '  password:\n    type: secret\n    required: true',
  );
  final daemon = await env.start(secretProtector: FakeSecretProtector(devSid));
  return (daemon, await createInstalled(daemon));
}

void main() {
  test('required_secret_unset_at_start', () async {
    final env = TestEnv();
    final (daemon, instance) = await installedWithRequiredSecret(env);

    expect(
      () => daemon.instances.start(instance.id),
      failsWith('secret_required', messageHas: ['password']),
    );

    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.launches, isEmpty);
  });

  test('required_secret_set', () async {
    final env = TestEnv();
    final (daemon, instance) = await installedWithRequiredSecret(env);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(env.process.launches, hasLength(1));
  });
}
