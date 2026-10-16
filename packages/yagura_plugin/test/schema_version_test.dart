import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

int _version(String text) {
  final result = loadPlugin(writePlugin(text));
  expect(result.reasons, isEmpty);
  return schemaVersion(result.manifest!);
}

void main() {
  test('canonical JSON sorts keys, keeps list order and has no whitespace', () {
    expect(
      canonicalJson({
        'b': [3, 1],
        'a': {'z': null, 'y': 'x y'},
      }),
      '{"a":{"y":"x y","z":null},"b":[3,1]}',
    );
  });

  test('the Valheim schema version is a stable uint32', () {
    final version = _version(valheimManifest());

    expect(version, inInclusiveRange(0, 0xFFFFFFFF));
    expect(_version(valheimManifest()), version);
    expect(version, 1479705143, reason: 'change only with the fixture schema');
  });

  test('a schema change changes the version', () {
    final before = _version(valheimManifest());

    expect(_version(valheimWith('max: 64', 'max: 65')), isNot(before));
    expect(
      _version(valheimWith('default: Dedicated', 'default: Other')),
      isNot(before),
    );
  });

  test('changes outside the settings schema keep the version', () {
    final before = _version(valheimManifest());

    expect(
      _version(valheimWith('name: Valheim Dedicated Server', 'name: Valheim')),
      before,
    );
    expect(
      _version(valheimWith('grace_seconds: 30', 'grace_seconds: 10')),
      before,
    );
  });

  test('the order of keys in a setting does not matter', () {
    const a = 'type: integer, min: 1, max: 9';
    const b = 'max: 9, min: 1, type: integer';
    String manifest(String setting) =>
        valheimWith('  password:\n', '  slots: { $setting }\n  password:\n');

    expect(_version(manifest(a)), _version(manifest(b)));
  });
}
