import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

PluginManifest _valheim([String? text]) {
  final result = loadPlugin(writePlugin(text ?? valheimManifest()));
  expect(result.reasons, isEmpty);
  return result.manifest!;
}

void main() {
  test('derived_port_follows_its_base', () {
    final manifest = _valheim();

    expect(resolvePorts(manifest, {'game': 2466}), {
      'game': 2466,
      'query': 2467,
    });
  });

  group('beyond the test map', () {
    test('defaults apply without overrides', () {
      expect(resolvePorts(_valheim(), {}), {'game': 2456, 'query': 2457});
    });

    test('exposed defaults to true, and to false for rcon', () {
      final text = valheimWith(
        '    purpose: query\n',
        '    purpose: query\n'
            '  - name: admin\n'
            '    default: 25575\n'
            '    protocol: tcp\n'
            '    purpose: rcon\n',
      );

      final ports = {for (final port in _valheim(text).ports) port.name: port};

      expect(ports['game']!.exposed, isTrue);
      expect(ports['admin']!.exposed, isFalse);
    });

    test('a derived port from an unknown base is rejected at load', () {
      final result = loadPlugin(
        writePlugin(valheimWith('from: game', 'from: nope')),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'ports[1].derive.from');
      expect(result.reasons.single.message, contains('nope'));
    });

    test('a port with both default and derive is rejected', () {
      final result = loadPlugin(
        writePlugin(
          valheimWith(
            '    purpose: query\n',
            '    purpose: query\n    default: 5\n',
          ),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'ports[1]');
    });

    test('duplicate port names are rejected', () {
      final result = loadPlugin(
        writePlugin(valheimWith('name: query', 'name: game')),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'ports[1].name');
    });
  });
}
