import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/src/manifest_schema.g.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

final _schemaFile = File(
  p.join('..', '..', 'schemas', 'plugin-manifest.v1.json'),
);

Map<String, Object?> _valheim() =>
    jsonDecode(jsonEncode(loadYaml(valheimManifest()))) as Map<String, Object?>;

/// Applies [edit] to a fresh copy of the Valheim manifest and validates it
/// against the schema file itself (not through the loader).
List<String> _schemaErrors(void Function(Map<String, Object?> m) edit) {
  final manifest = _valheim();
  edit(manifest);
  final schema = JsonSchema.create(_schemaFile.readAsStringSync());
  return [for (final e in schema.validate(manifest).errors) e.toString()];
}

Map<String, Object?> _map(Object? value) => value! as Map<String, Object?>;

void main() {
  test('the schema accepts the Valheim manifest', () {
    expect(_schemaErrors((_) {}), isEmpty);
  });

  test('steam.size_hint_bytes is optional', () {
    expect(
      _schemaErrors((m) => _map(m['steam']).remove('size_hint_bytes')),
      isEmpty,
    );
  });

  final invalid = <String, void Function(Map<String, Object?>)>{
    'missing id': (m) => m.remove('id'),
    'missing launch': (m) => m.remove('launch'),
    'bad id': (m) => m['id'] = 'Valheim Server',
    'unknown top-level field': (m) => m['surprise'] = 1,
    'empty executable': (m) => m['executable'] = <String, Object?>{},
    'unknown executable os': (m) => _map(m['executable'])['macos'] = 'x',
    'port protocol tcpp': (m) =>
        _map((m['ports']! as List<Object?>)[0])['protocol'] = 'tcpp',
    'port purpose unknown': (m) =>
        _map((m['ports']! as List<Object?>)[0])['purpose'] = 'voice',
    'port with default and derive': (m) =>
        _map((m['ports']! as List<Object?>)[1])['default'] = 5,
    'port with neither default nor derive': (m) =>
        _map((m['ports']! as List<Object?>)[0]).remove('default'),
    'port number out of range': (m) =>
        _map((m['ports']! as List<Object?>)[0])['default'] = 70000,
    'secret with a default': (m) =>
        _map(_map(m['settings'])['password'])['default'] = 'hunter2',
    'unknown setting type': (m) =>
        _map(_map(m['settings'])['worldName'])['type'] = 'color',
    'enum without values': (m) =>
        _map(m['settings'])['mode'] = {'type': 'enum'},
    'list without fields': (m) =>
        _map(m['settings'])['rows'] = {'type': 'list'},
    'object without fields': (m) =>
        _map(m['settings'])['group'] = {'type': 'object'},
    'nested bad setting type': (m) => _map(m['settings'])['rows'] = {
      'type': 'list',
      'fields': {
        'x': {'type': 'nope'},
      },
    },
    'launch entry not a string or group': (m) =>
        _map(m['launch'])['args'] = [5],
    'launch group without args': (m) => _map(m['launch'])['args'] = [
      {'when': 'settings.logs'},
    ],
    'hooks timeout above the cap': (m) => m['hooks'] = {'timeout_seconds': 300},
    'hooks timeout zero': (m) => m['hooks'] = {'timeout_seconds': 0},
    'stop strategy unknown': (m) => _map(m['stop'])['strategy'] = 'pause',
    'health type unknown': (m) => _map(m['health'])['type'] = 'telepathy',
    'log_match without a pattern': (m) => _map(m['health']).remove('log_match'),
    'log_match without a source': (m) => _map(m['health']).remove('source'),
    'port health without a port': (m) => m['health'] = {'type': 'port'},
    'negative size hint': (m) => _map(m['steam'])['size_hint_bytes'] = -1,
    'log rotation unknown': (m) =>
        _map((m['logs']! as List<Object?>)[0])['rotation'] = 'daily',
    'data_paths not a list': (m) => m['data_paths'] = 'save/',
  };

  for (final MapEntry(:key, :value) in invalid.entries) {
    test('the schema rejects: $key', () {
      expect(_schemaErrors(value), isNotEmpty);
    });
  }

  test('the embedded schema matches schemas/plugin-manifest.v1.json', () {
    // Regenerate with: dart run tool/embed_schema.dart
    expect(manifestSchemaV1, _schemaFile.readAsStringSync());
  });
}
