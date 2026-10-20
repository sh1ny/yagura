import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

/// The Valheim manifest with extra settings spliced in before `password`.
String _withSettings(String extra) =>
    valheimWith('  password:\n', '$extra  password:\n');

const _arkRows = '''
  itemStackOverrides:
    type: list
    label: Item stack overrides
    fields:
      class: { type: string, required: true }
      max: { type: integer, min: 1 }
''';

PluginManifest _load(String text) {
  final result = loadPlugin(writePlugin(text));
  expect(result.reasons, isEmpty);
  return result.manifest!;
}

void main() {
  test('repeatable_structure_validated', () {
    final manifest = _load(_withSettings(_arkRows));
    final rows = [
      {'class': 'PrimalItemResource_Wood_C', 'max': 100},
      {'class': 'PrimalItemResource_Stone_C', 'max': 200},
    ];

    final outcome = validateSettings(manifest, {'itemStackOverrides': rows});

    expect(outcome.errors, isEmpty);
    expect(outcome.values['itemStackOverrides'], rows);
  });

  test('row_with_missing_required_field', () {
    final manifest = _load(_withSettings(_arkRows));

    final outcome = validateSettings(manifest, {
      'itemStackOverrides': [
        {'class': 'PrimalItemResource_Wood_C', 'max': 100},
        {'max': 200},
      ],
    });

    expect(outcome.isValid, isFalse);
    expect(outcome.errors.map((e) => e.path), ['itemStackOverrides[1].class']);
  });

  group('beyond the test map', () {
    late PluginManifest manifest;
    setUp(() {
      manifest = _load(
        _withSettings('''
  slots: { type: integer, min: 1, max: 70, default: 10 }
  ratio: { type: number, min: 0.5 }
  pvp: { type: boolean, default: false }
  mode:
    type: enum
    values: [easy, hard]
    default: easy
  tags: { type: string_list, min: 0, max: 2 }
  limits:
    type: object
    fields:
      day: { type: integer, default: 5 }
      night: { type: integer, required: true }
'''),
      );
    });

    test('defaults are applied and secrets stay unset', () {
      final outcome = validateSettings(manifest, {
        'limits': {'night': 3},
      });

      expect(outcome.errors, isEmpty);
      expect(outcome.values, {
        'serverName': 'Yagura Valheim',
        'worldName': 'Dedicated',
        'slots': 10,
        'pvp': false,
        'mode': 'easy',
        'limits': {'day': 5, 'night': 3},
      });
    });

    test('type and constraint violations name their field', () {
      final outcome = validateSettings(manifest, {
        'slots': 99,
        'ratio': 0.1,
        'pvp': 'yes',
        'mode': 'medium',
        'tags': ['a', 'b', 'c'],
        'worldName': 'bad name!',
        'limits': {'day': 'x', 'night': 1},
        'unknown': 1,
      });

      expect(outcome.errors.map((e) => e.path).toSet(), {
        'slots',
        'ratio',
        'pvp',
        'mode',
        'tags',
        'worldName',
        'limits.day',
        'unknown',
      });
    });

    test('a value for a secret is refused, the placeholder is not', () {
      final refused = validateSettings(manifest, {'password': 'hunter2'});
      expect(refused.errors.single.path, 'password');
      expect(refused.errors.single.code, 'secret_via_set_secret');

      final placeholder = validateSettings(manifest, {
        'password': {'secret': true, 'set': false},
      });
      expect(placeholder.errors, isEmpty);
      expect(placeholder.values, isNot(contains('password')));
    });

    test('a required object field is enforced', () {
      final outcome = validateSettings(manifest, {
        'limits': <String, Object?>{},
      });

      expect(outcome.errors.map((e) => e.path), ['limits.night']);
    });
  });

  group('load-time checks', () {
    test('a default on a secret is rejected', () {
      final result = loadPlugin(
        writePlugin(
          valheimWith(
            '    type: secret\n',
            '    type: secret\n    default: hunter2\n',
          ),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.first.path, 'settings.password.default');
    });

    test('an enum default outside its values is rejected', () {
      final result = loadPlugin(
        writePlugin(
          _withSettings('  mode: { type: enum, values: [a, b], default: c }\n'),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'settings.mode.default');
    });

    test('an invalid setting pattern is rejected', () {
      final result = loadPlugin(
        writePlugin(
          _withSettings('  code: { type: string, pattern: "([x" }\n'),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'settings.code.pattern');
    });

    test(
      'an invalid nested pattern under a structured default is rejected',
      () {
        final result = loadPlugin(
          writePlugin(
            _withSettings('''
  box:
    type: object
    default: { code: abc }
    fields:
      code: { type: string, pattern: "([x" }
'''),
          ),
        );

        expect(result.status, PluginStatus.rejected);
        expect(result.reasons.single.path, 'settings.box.fields.code.pattern');
      },
    );

    test('an object default supplies the defaults of its fields', () {
      final manifest = _load(
        _withSettings('''
  limits:
    type: object
    default: {}
    fields:
      slots: { type: integer, required: true, default: 10 }
  rows:
    type: list
    default: [{}]
    fields:
      max: { type: integer, default: 7 }
'''),
      );

      final outcome = validateSettings(manifest, {});

      expect(outcome.errors, isEmpty);
      expect(outcome.values['limits'], {'slots': 10});
      expect(outcome.values['rows'], [
        {'max': 7},
      ]);
    });
  });
}
