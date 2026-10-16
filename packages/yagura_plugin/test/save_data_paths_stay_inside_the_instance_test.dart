import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

LaunchContext _context(String instance) => LaunchContext(
  settings: const {'serverName': 'Yagura', 'worldName': 'Dedicated'},
  ports: const {'game': 2456, 'query': 2457},
  paths: {'instance': instance, 'server': p.join(instance, 'server')},
  os: 'windows',
);

void main() {
  test('valheim_save_directory_inside_the_instance', () {
    final result = loadPlugin(writePlugin(valheimManifest()));
    expect(result.reasons, isEmpty);
    final instance = p.join(p.current, 'instances', 'world1');
    final context = _context(instance);

    final args = renderLaunchArgs(result.manifest!, context);
    final saveDir = args[args.indexOf('-savedir') + 1];
    final dataPaths = resolveDataPaths(result.manifest!, context);

    expect(p.normalize(saveDir), p.join(instance, 'save'));
    expect(dataPaths.map(p.normalize), [p.join(instance, 'save')]);
  });

  test('data_path_outside_the_instance', () {
    final result = loadPlugin(
      writePlugin(valheimWith('- "save/"', '- "{{instance}}/../shared"')),
    );

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.path, 'data_paths[0]');
    expect(reason.message, contains('{{instance}}/../shared'));
  });

  group('beyond the test map', () {
    for (final outside in [
      '../shared',
      'save/../../shared',
      '/etc/passwd',
      'C:/Windows',
      r'C:\Windows',
      '{{paths.server}}/save',
      '{{instance}}',
    ]) {
      test('rejects $outside', () {
        final result = loadPlugin(
          writePlugin(valheimWith('- "save/"', "- '$outside'")),
        );

        expect(result.status, PluginStatus.rejected, reason: outside);
        expect(result.reasons.first.path, 'data_paths[0]');
      });
    }

    test('data paths cannot reference settings', () {
      final result = loadPlugin(
        writePlugin(valheimWith('- "save/"', '- "{{settings.worldName}}"')),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.first.path, 'data_paths[0]');
    });

    test('a log path outside the instance is rejected', () {
      final result = loadPlugin(
        writePlugin(
          valheimWith('path: "logs/server.log"', 'path: "../server.log"'),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.first.path, 'logs[0].path');
    });

    test('resolveInstancePath keeps paths inside and refuses others', () {
      final root = p.join(p.current, 'inst');

      expect(resolveInstancePath('save/', root), p.join(root, 'save'));
      expect(resolveInstancePath('a/../b', root), p.join(root, 'b'));
      expect(resolveInstancePath('../x', root), isNull);
    });
  });
}
