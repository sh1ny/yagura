import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';

const placeholder = {'secret': true, 'set': false};

void main() {
  test('secret_values_refused', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();

    await expectLater(
      createValheim(
        daemon,
        settings: {'serverName': 'Friends', 'password': 'hunter2'},
      ),
      failsWith('secret_store_unavailable'),
    );
    expect(daemon.instances.list(), isEmpty);

    final instance = await createValheim(daemon);
    expect(instance.settings['password'], placeholder);
    expect(
      () => daemon.instances.updateSettings(
        UpdateSettingsRequest(
          instanceId: instance.id,
          settings: {'serverName': 'Renamed', 'password': 'hunter2'},
        ),
      ),
      failsWith('secret_store_unavailable'),
    );
    expect(
      () => daemon.instances.setSecret(instance.id, 'password', 'x'),
      failsWith('secret_store_unavailable'),
    );
    expect(
      () => daemon.instances.deleteSecret(instance.id, 'password'),
      failsWith('secret_store_unavailable'),
    );
    final after = daemon.instances.get(instance.id);
    expect(after.settings['serverName'], 'Friends');
    expect(after.settings['password'], placeholder);
  });

  test('settings_saved_with_the_secret_placeholder', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    expect(instance.settings['password'], placeholder);

    final saved = daemon.instances.updateSettings(
      UpdateSettingsRequest(
        instanceId: instance.id,
        settings: instance.settings,
        ports: {'game': 2466},
      ),
    );

    expect(saved.portNumbers['game'], 2466);
    expect(saved.settings['password'], placeholder);
    expect(daemon.instances.get(instance.id).settings['password'], placeholder);
  });
}
