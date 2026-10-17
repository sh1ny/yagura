import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';

void main() {
  test('derived_port_collides', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    await createValheim(daemon, name: 'Alpha'); // game 2456, query 2457
    final beta = await createValheim(
      daemon,
      name: 'Beta',
      ports: {'game': 2466},
    );

    // game 2455 derives query 2456, which Alpha uses as its game port.
    expect(
      () => daemon.instances.updateSettings(
        UpdateSettingsRequest(
          instanceId: beta.id,
          settings: beta.settings,
          ports: {'game': 2455},
        ),
      ),
      failsWith(
        'port_conflict',
        messageHas: ['Alpha', 'Beta', '2456'],
        details: {'port': 2456},
      ),
    );
    expect(daemon.instances.get(beta.id).portNumbers['game'], 2466);
  });
}
