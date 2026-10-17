import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

void main() {
  test('valid_plugin_loaded', () {
    final result = loadPlugin(
      writePlugin(valheimManifest(), folder: 'valheim'),
    );

    expect(result.reasons, isEmpty);
    expect(result.status, PluginStatus.loaded);
    expect(result.id, 'valheim');
    expect(result.name, 'Valheim Dedicated Server');
    expect(result.version, '0.1.0');
    expect(result.platforms, ['linux', 'windows']);
    expect(result.manifest, isNotNull);
  });

  test('invalid_manifest_rejected_with_location', () {
    final text = valheimWith(
      'protocol: udp\n    purpose: game',
      'protocol: tcpp\n    purpose: game',
    );
    final line = text.split('\n').indexWhere((l) => l.contains('tcpp')) + 1;

    final result = loadPlugin(writePlugin(text, folder: 'broken'));

    expect(result.status, PluginStatus.rejected);
    expect(result.id, 'valheim');
    final reason = result.reasons.single;
    expect(reason.path, 'ports[0].protocol');
    expect(reason.line, line);
    for (final allowed in ['udp', 'tcp', 'both']) {
      expect(reason.message, contains(allowed));
    }
  });

  test('unknown_manifest_version', () {
    final result = loadPlugin(
      writePlugin(valheimWith('manifest_version: 1', 'manifest_version: 2')),
    );

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.code, 'unsupported_manifest_version');
    expect(reason.path, 'manifest_version');
    expect(reason.message, contains('[1]'));
  });

  group('beyond the test map', () {
    test('yaml syntax error is rejected with its line', () {
      final result = loadPlugin(writePlugin('id: [unclosed\nname: x\n'));

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.code, 'invalid_manifest');
      expect(result.reasons.single.line, isNotNull);
    });

    test('missing required field is named', () {
      final result = loadPlugin(
        writePlugin(valheimWith('name: Valheim Dedicated Server\n', '')),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.map((r) => r.message).join('\n'), contains('name'));
    });

    test('a name of the wrong type is rejected, not thrown', () {
      final result = loadPlugin(
        writePlugin(
          valheimWith('name: Valheim Dedicated Server\n', 'name: 42\n'),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.name, isNull);
      expect(result.reasons.map((r) => r.path), contains('name'));
    });

    test('a folder without plugin.yaml is rejected', () {
      final dir = Directory.systemTemp.createTempSync('yagura_plugin_test_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final result = loadPlugin(dir.path);

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'plugin.yaml');
    });

    test('discovery lists every folder holding a plugin.yaml', () {
      final good = writePlugin(valheimManifest(), folder: 'valheim');
      final root = p.dirname(good);
      Directory(p.join(root, 'no_manifest')).createSync();
      final bad = Directory(p.join(root, 'broken'))..createSync();
      File(p.join(bad.path, 'plugin.yaml')).writeAsStringSync('id: [');

      final results = discoverPlugins(root);

      expect(results.map((r) => r.id), ['broken', 'valheim']);
      expect(results.map((r) => r.status), [
        PluginStatus.rejected,
        PluginStatus.loaded,
      ]);
    });

    test('a plugin with only a linux executable loads as linux only', () {
      final text = valheimWith('  windows: valheim_server.exe\n', '');

      final result = loadPlugin(writePlugin(text));

      expect(result.status, PluginStatus.loaded);
      expect(result.platforms, ['linux']);
    });
  });
}
