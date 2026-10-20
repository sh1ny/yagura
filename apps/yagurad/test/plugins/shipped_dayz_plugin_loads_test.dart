import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart' show PluginStatus;
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/plugins/plugin_registry.dart';

/// The plugins the repository ships (`plugins/`), loaded as the daemon loads
/// its plugins directory.
void main() {
  test('shipped_dayz_plugin_loaded', () async {
    final shipped = p.absolute('..', '..', 'plugins');
    final registry = PluginRegistry(
      pluginsDirectory: shipped,
      hooks: HookHost(),
    );

    final results = await registry.load();

    final dayz = results.singleWhere((r) => r.id == 'dayz');
    expect(dayz.status, PluginStatus.loaded, reason: '${dayz.reasons}');
    expect(dayz.reasons, isEmpty);
    final plugin = registry.find('dayz')!;
    // The templates the bindings create files from ship with the plugin.
    for (final template in ['serverDZ.cfg', 'BEServer_x64.cfg']) {
      expect(
        File(p.join(shipped, 'dayz', 'templates', template)).existsSync(),
        isTrue,
        reason: template,
      );
    }
    expect(plugin.manifest.mods, isNotNull);
  });
}
