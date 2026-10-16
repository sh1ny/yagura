import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/plugins/plugin_registry.dart';

import '../support/daemon_support.dart';

void main() {
  test('syntax_error_at_load', () async {
    final env = TestEnv();
    env.installValheim(hooks: 'var a = 1;\nvar b = ;\n');
    final registry = PluginRegistry(
      pluginsDirectory: env.pluginsDir,
      hooks: HookHost(),
    );

    final results = await registry.load();

    final valheim = results.singleWhere((r) => r.id == 'valheim');
    expect(valheim.status, PluginStatus.rejected);
    expect(valheim.reasons, hasLength(1));
    expect(valheim.reasons.single.code, 'hook_syntax_error');
    expect(valheim.reasons.single.path, 'hooks.js');
    expect(valheim.reasons.single.line, 2);
    // No instance operation can run a rejected plugin's hooks.
    expect(registry.find('valheim'), isNull);
  });
}
