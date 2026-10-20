import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';
import 'config_support.dart';

final _maxPlayers = bindingYaml(
  file: 'serverDZ.cfg',
  format: 'dayz-cfg',
  key: 'maxPlayers',
  setting: 'maxPlayers',
);

/// Starts, stops and returns the instance with its file applied once.
Future<void> startAndStop(Daemon daemon, Instance instance) async {
  final started = await runStart(daemon, instance.id);
  expect(started.status, OperationStatus.succeeded, reason: started.resultMessage);
  expect(started.warnings, isEmpty);
  final stopped = await runStop(daemon, instance.id);
  expect(stopped.status, OperationStatus.succeeded);
}

void main() {
  test('admin_edit_to_an_unbound_key_kept', () async {
    final env = TestEnv();
    installBound(env, bindings: [_maxPlayers]);
    final daemon = await env.start();
    final instance = await createBound(daemon, maxPlayers: 40);
    final file = instanceFile(
      instance,
      'serverDZ.cfg',
      'hostname = "Friends";\nmaxPlayers = 10;\n',
    );
    await startAndStop(daemon, instance);

    file.writeAsStringSync('${file.readAsStringSync()}disableRespawnDialog = 1;\n');
    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(file.readAsStringSync(), contains('disableRespawnDialog = 1;'));
    expect(file.readAsStringSync(), contains('maxPlayers = 40;'));
    expect(externalEdits(done.warnings), isEmpty);
  });

  test('admin_edit_to_a_bound_key_reported', () async {
    final env = TestEnv();
    installBound(env, bindings: [_maxPlayers]);
    final daemon = await env.start();
    final instance = await createBound(daemon, maxPlayers: 40);
    final file = instanceFile(
      instance,
      'serverDZ.cfg',
      'hostname = "Friends";\nmaxPlayers = 10;\n',
    );
    await startAndStop(daemon, instance);

    file.writeAsStringSync('hostname = "Friends";\nmaxPlayers = 60;\n');
    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(file.readAsStringSync(), 'hostname = "Friends";\nmaxPlayers = 40;\n');
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
    final events = externalEdits(done.warnings);
    expect(events, hasLength(1));
    expect(
      events.single,
      allOf(contains('serverDZ.cfg'), contains('maxPlayers'), contains('60')),
    );
  });

  test('secret_values_masked_in_the_event', () async {
    const secret = 'Zr0-correct-horse';
    const handEdited = 'typed-by-the-admin';
    final env = TestEnv();
    installBound(
      env,
      bindings: [
        bindingYaml(
          file: 'battleye/BEServer_x64.cfg',
          format: 'kv',
          key: 'RConPassword',
          setting: 'rconPassword',
          create: true,
          template: 'templates/BEServer_x64.cfg',
        ),
      ],
      templates: {'templates/BEServer_x64.cfg': 'RConPassword changeme\n'},
    );
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final instance = await createBound(daemon);
    daemon.instances.setSecret(instance.id, 'rconPassword', secret);
    await startAndStop(daemon, instance);

    final file = instanceFile(instance, 'battleye/BEServer_x64.cfg');
    file.writeAsStringSync('RConPassword $handEdited\n');
    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(file.readAsStringSync(), 'RConPassword $secret\n');
    final events = externalEdits(done.warnings);
    expect(events, hasLength(1));
    expect(events.single, allOf(contains('RConPassword'), contains('***')));
    expect(events.single, isNot(contains(secret)));
    expect(events.single, isNot(contains(handEdited)));
  });

  test('game_rewrites_its_own_config', () async {
    final env = TestEnv();
    installBound(
      env,
      bindings: [
        bindingYaml(
          file: 'serverDZ.cfg',
          format: 'dayz-cfg',
          key: 'maxPlayers',
          setting: 'maxPlayers',
          gameWrites: true,
        ),
      ],
    );
    final daemon = await env.start();
    final instance = await createBound(daemon, maxPlayers: 40);
    final file = instanceFile(
      instance,
      'serverDZ.cfg',
      'hostname = "Friends";\nmaxPlayers = 10;\n',
    );
    await startAndStop(daemon, instance);

    // The game rewrote the file on shutdown.
    file.writeAsStringSync('hostname = "Friends";\nmaxPlayers = 99;\n');
    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(file.readAsStringSync(), 'hostname = "Friends";\nmaxPlayers = 40;\n');
    expect(externalEdits(done.warnings), isEmpty);
  });
}
