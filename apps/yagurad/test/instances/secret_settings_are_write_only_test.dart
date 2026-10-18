import 'dart:convert';

import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/secret_store.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';

Map<String, Object?> set(bool value) => {'secret': true, 'set': value};

/// A daemon with a working secret store, and a Valheim instance on it.
Future<(Daemon, Instance)> daemonWithInstance(TestEnv env) async {
  env.installValheim();
  final daemon = await env.start(secretProtector: FakeSecretProtector(devSid));
  return (daemon, await createValheim(daemon));
}

String? stored(Daemon daemon, Instance instance) {
  final bytes = daemon.secrets.get(secretIdFor(instance.id, 'password'));
  return bytes == null ? null : utf8.decode(bytes);
}

void main() {
  test('secret_values_are_write_only', () async {
    final env = TestEnv();
    final (daemon, instance) = await daemonWithInstance(env);
    expect(instance.settings['password'], set(false));

    final after = daemon.instances.setSecret(
      instance.id,
      'password',
      'hunter2',
    );

    expect(after.settings['password'], set(true));
    expect(daemon.instances.get(instance.id).settings['password'], set(true));
    final everywhere = jsonEncode([
      for (final i in daemon.instances.list()) i.settings,
      daemon.instances.get(instance.id).settings,
    ]);
    expect(everywhere, isNot(contains('hunter2')));
    expect(stored(daemon, instance), 'hunter2');
  });

  test('settings_saved_with_the_secret_placeholder', () async {
    final env = TestEnv();
    final (daemon, instance) = await daemonWithInstance(env);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');
    final read = daemon.instances.get(instance.id);
    expect(read.settings['password'], set(true));

    final saved = daemon.instances.updateSettings(
      UpdateSettingsRequest(
        instanceId: instance.id,
        settings: read.settings,
        ports: {'game': 2466},
      ),
    );

    expect(saved.portNumbers['game'], 2466);
    expect(saved.settings['password'], set(true));
    expect(stored(daemon, instance), 'hunter2');
  });

  test('secret_value_in_a_settings_save', () async {
    final env = TestEnv();
    final (daemon, instance) = await daemonWithInstance(env);

    expect(
      () => daemon.instances.updateSettings(
        UpdateSettingsRequest(
          instanceId: instance.id,
          settings: {'serverName': 'Renamed', 'password': 'hunter2'},
        ),
      ),
      failsWith('secret_via_set_secret'),
    );

    final after = daemon.instances.get(instance.id);
    expect(after.settings['serverName'], 'Friends');
    expect(after.settings['password'], set(false));
    expect(stored(daemon, instance), isNull);
  });

  test('secret_value_in_a_create', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );

    await expectLater(
      createValheim(
        daemon,
        settings: {'serverName': 'Friends', 'password': 'hunter2'},
      ),
      failsWith('secret_via_set_secret'),
    );

    expect(daemon.instances.list(), isEmpty);
  });

  test('secret_cleared', () async {
    final env = TestEnv();
    final (daemon, instance) = await daemonWithInstance(env);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');

    final after = daemon.instances.deleteSecret(instance.id, 'password');

    expect(after.settings['password'], set(false));
    expect(daemon.instances.get(instance.id).settings['password'], set(false));
    expect(stored(daemon, instance), isNull);
  });

  test('secrets_deleted_with_the_instance', () async {
    final env = TestEnv();
    final (daemon, instance) = await daemonWithInstance(env);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');
    expect(stored(daemon, instance), 'hunter2');

    final op = daemon.instances.delete(instance.id);
    await daemon.operations.whenDone(op.id);

    expect(daemon.instances.list(), isEmpty);
    expect(stored(daemon, instance), isNull);
  });
}
