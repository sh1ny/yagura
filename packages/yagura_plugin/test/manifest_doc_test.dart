import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

/// docs/plugins/manifest.md. A fenced block tagged `yaml` is a complete
/// manifest and must load; a block tagged `yaml fragment` is a partial snippet
/// that only has to be valid YAML. Other blocks are not checked.
final _doc = File(p.join('..', '..', 'docs', 'plugins', 'manifest.md'))
    .readAsStringSync();

final _blocks = [
  for (final m in RegExp(
    r'^```(\S*)[ \t]*(\S*)\n(.*?)^```$',
    multiLine: true,
    dotAll: true,
  ).allMatches(_doc))
    (language: m.group(1)!, modifier: m.group(2)!, body: m.group(3)!),
];

void main() {
  final complete = _blocks
      .where((b) => b.language == 'yaml' && b.modifier.isEmpty)
      .toList();
  final fragments = _blocks
      .where((b) => b.language == 'yaml' && b.modifier == 'fragment')
      .toList();

  test('the document has complete manifests and fragments to check', () {
    expect(complete.length, greaterThanOrEqualTo(2));
    expect(fragments.length, greaterThanOrEqualTo(10));
  });

  for (final (i, block) in complete.indexed) {
    test('complete manifest #${i + 1} lints clean', () {
      final result = loadPlugin(writePlugin(block.body));

      expect(result.reasons, isEmpty);
      expect(result.status, PluginStatus.loaded);
    });
  }

  for (final (i, block) in fragments.indexed) {
    test('fragment #${i + 1} is valid YAML', () {
      expect(() => loadYaml(block.body), returnsNormally);
    });
  }

  test('the walkthrough manifest is the Valheim fixture', () {
    final valheim = complete.firstWhere((b) => b.body.contains('id: valheim'));

    expect(valheim.body.trim(), valheimManifest().trim());
  });

  test('every manifest field and setting attribute is documented', () {
    final schema = jsonDecode(
      File(p.join('..', '..', 'schemas', 'plugin-manifest.v1.json'))
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final root = (schema['properties']! as Map<String, Object?>).keys;
    final definitions = schema['definitions']! as Map<String, Object?>;
    Iterable<String> propertiesOf(String name) =>
        ((definitions[name]! as Map<String, Object?>)['properties']!
                as Map<String, Object?>)
            .keys;

    final fields = {
      ...root,
      ...propertiesOf('steam'),
      ...propertiesOf('port'),
      ...propertiesOf('setting'),
      'grace_seconds',
      'start_timeout_seconds',
      'timeout_seconds',
      'encoding',
      'rotation',
    };
    for (final field in fields) {
      expect(_doc, contains('`$field`'), reason: 'undocumented field $field');
    }
  });
}
