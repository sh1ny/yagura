import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

/// The Valheim fixture with a `bindings:` section made of [entries] (each a
/// YAML list item) and, when given, [extraSettings] after the last setting.
String withBindings(List<String> entries, {String extraSettings = ''}) =>
    valheimWith(
      'launch:\n  args:',
      '$extraSettings'
          'bindings:\n${entries.join()}\nlaunch:\n  args:',
    );

String entry({
  String file = 'serverDZ.cfg',
  String format = 'dayz-cfg',
  String key = 'maxPlayers',
  String setting = 'serverName',
  String extra = '',
}) =>
    '  - file: $file\n    format: $format\n    key: $key\n'
    '    setting: $setting\n$extra';

PluginResult load(String manifest, {Map<String, String> files = const {}}) {
  final dir = writePlugin(manifest);
  for (final MapEntry(:key, :value) in files.entries) {
    File(p.join(dir, key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  return loadPlugin(dir);
}

void main() {
  test('bindings are accepted and modelled', () {
    final result = load(
      withBindings([
        entry(extra: '    game_writes: true\n'),
        entry(
          file: 'battleye/{{settings.worldName}}.cfg',
          format: 'kv',
          key: 'RConPassword',
          setting: 'password',
          extra: '    create: true\n    template: templates/be.cfg\n',
        ),
      ]),
      files: {'templates/be.cfg': 'RConPassword x\n'},
    );

    expect(result.reasons, isEmpty);
    expect(result.status, PluginStatus.loaded);
    final bindings = result.manifest!.bindings;
    expect(bindings, hasLength(2));
    expect(bindings[0].file, 'serverDZ.cfg');
    expect(bindings[0].format, 'dayz-cfg');
    expect(bindings[0].key, 'maxPlayers');
    expect(bindings[0].setting, 'serverName');
    expect(bindings[0].gameWrites, isTrue);
    expect(bindings[0].create, isFalse);
    expect(bindings[1].create, isTrue);
    expect(bindings[1].template, 'templates/be.cfg');
  });

  test('a manifest without bindings has none', () {
    final result = loadPlugin(writePlugin(valheimManifest()));

    expect(result.manifest!.bindings, isEmpty);
  });

  test('the rcon section stays unsupported', () {
    final result = load('${valheimManifest()}\nrcon:\n  anything: 1\n');

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.single.code, 'unsupported_in_this_version');
    expect(result.reasons.single.path, 'rcon');
  });

  test('formats of a later version are unsupported in this version', () {
    for (final format in ['ue-ini', 'xml', 'vdf']) {
      final result = load(withBindings([entry(format: format)]));

      expect(result.status, PluginStatus.rejected, reason: format);
      final reason = result.reasons.single;
      expect(reason.code, 'unsupported_in_this_version', reason: format);
      expect(reason.path, 'bindings[0].format');
      expect(reason.message, contains(format));
    }
  });

  test('an unknown format lists the supported ones', () {
    final result = load(withBindings([entry(format: 'toml')]));

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.code, 'invalid_manifest');
    expect(reason.path, 'bindings[0].format');
    expect(reason.message, contains('toml'));
    for (final format in ['json', 'ini', 'dayz-cfg', 'kv']) {
      expect(reason.message, contains(format));
    }
  });

  test('a binding must name a declared setting', () {
    final result = load(withBindings([entry(setting: 'doesNotExist')]));

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.path, 'bindings[0].setting');
    expect(reason.message, contains('bindings[0]'));
    expect(reason.message, contains('doesNotExist'));
  });

  test('a binding cannot name an object setting', () {
    final result = load(
      withBindings([entry(setting: 'limits')], extraSettings: '').replaceFirst(
        '    group: General\n\nbindings:',
        '    group: General\n  limits:\n    type: object\n    fields:\n'
            '      a:\n        type: integer\n\nbindings:',
      ),
    );

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.single.path, 'bindings[0].setting');
    expect(result.reasons.single.message, contains('limits'));
  });

  test('a file path stays inside the instance', () {
    for (final file in [
      '../outside.cfg',
      '/etc/outside.cfg',
      r'C:\outside.cfg',
    ]) {
      final result = load(withBindings([entry(file: "'$file'")]));

      expect(result.status, PluginStatus.rejected, reason: file);
      expect(result.reasons.single.path, 'bindings[0].file', reason: file);
      expect(result.reasons.single.message, contains('outside'), reason: file);
    }
  });

  test('a file path template may use settings, ports, paths and os', () {
    final result = load(
      withBindings([
        entry(
          file: '"{{paths.server}}/{{os}}/{{settings.worldName}}-{{ports.game}}.cfg"',
        ),
      ]),
    );

    expect(result.reasons, isEmpty);
    expect(result.status, PluginStatus.loaded);
  });

  test('a file path template names only what exists', () {
    final result = load(withBindings([entry(file: '"{{settings.nope}}.cfg"')]));

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.single.path, 'bindings[0].file');
    expect(result.reasons.single.message, contains('settings.nope'));
  });

  test('a secret setting cannot be written into a file path', () {
    final result = load(
      withBindings([entry(file: '"{{settings.password}}.cfg"')]),
    );

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.single.path, 'bindings[0].file');
  });

  test('at most 64 distinct files', () {
    final sixtyFour = [
      for (var i = 0; i < 64; i++) entry(file: 'f$i.cfg', key: 'k'),
      // More keys in a file already bound do not count again.
      entry(file: 'f0.cfg', key: 'other'),
    ];
    expect(load(withBindings(sixtyFour)).reasons, isEmpty);

    final result = load(
      withBindings([...sixtyFour, entry(file: 'f64.cfg', key: 'k')]),
    );

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.single.path, 'bindings');
    expect(result.reasons.single.message, contains('64'));
  });

  test('bindings of one file agree on the format', () {
    final result = load(
      withBindings([entry(format: 'dayz-cfg'), entry(format: 'kv', key: 'b')]),
    );

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.single.path, 'bindings[1].format');
  });

  test('a template stays inside the plugin and must exist', () {
    for (final template in ['../x.cfg', 'templates/missing.cfg']) {
      final result = load(
        withBindings([
          entry(extra: '    create: true\n    template: $template\n'),
        ]),
      );

      expect(result.status, PluginStatus.rejected, reason: template);
      expect(result.reasons.single.path, 'bindings[0].template');
    }
  });

  test('unknown binding fields are rejected', () {
    final result = load(withBindings([entry(extra: '    colour: red\n')]));

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.single.message, contains('colour'));
  });
}
