import 'dart:async';

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

  test('restart_update_and_validate_fail_before_stopping_the_server', () async {
    final env = TestEnv();
    final (daemon, instance) = await installedWithRequiredSecret(env);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');
    await runStart(daemon, instance.id);
    daemon.instances.deleteSecret(instance.id, 'password');
    expect(daemon.instances.get(instance.id).state, InstanceState.running);

    for (final call in [
      () => daemon.instances.restart(instance.id),
      () => daemon.instances.update(instance.id),
      () => daemon.instances.validate(instance.id),
    ]) {
      expect(call, failsWith('secret_required', messageHas: ['password']));
    }

    expect(env.process.stops, isEmpty, reason: 'the server was not stopped');
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
  });

  test('a_queued_start_checks_required_secrets_when_it_runs', () async {
    final env = TestEnv();
    env.installValheim(
      from: '  password:\n    type: secret',
      to: '  password:\n    type: secret\n    required: true',
    );
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final instance = await createValheim(daemon);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');
    final hold = env.steam.hold = Completer<void>();
    final install = daemon.instances.install(instance.id);
    // Queued behind the install: the check at the call passes.
    final start = daemon.instances.start(instance.id);
    daemon.instances.deleteSecret(instance.id, 'password');
    hold.complete();

    await daemon.operations.whenDone(install.id);
    final done = await daemon.operations.whenDone(start.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'secret_required');
    expect(env.process.launches, isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });
}
