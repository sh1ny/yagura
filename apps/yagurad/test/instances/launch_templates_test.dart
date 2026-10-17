import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import '../support/daemon_support.dart';

void main() {
  test('missing_executable_for_this_os', () async {
    final env = TestEnv();
    env.installValheim(from: '  windows: valheim_server.exe\n', to: '');
    final daemon = await env.start(os: 'windows');

    final listed = daemon.plugins.results.singleWhere((r) => r.id == 'valheim');
    expect(listed.status, PluginStatus.loaded);
    expect(listed.platforms, ['linux']);
    await expectLater(createValheim(daemon), failsWith('unsupported_platform'));
    expect(daemon.instances.list(), isEmpty);
  });
}
