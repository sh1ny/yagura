import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

const _logsAndMods = '''
manifest_version: 1
id: dayz
name: DayZ
version: 0.1.0
executable:
  windows: DayZServer_x64.exe
settings:
  logs: { type: boolean, default: false }
  serverMods: { type: string_list }
launch:
  args:
    - -config=serverDZ.cfg
    - when: settings.logs
      args: [-dologs, -adminlog, -netlog]
    - join: { list: settings.serverMods, separator: ";", prefix: "-mod=" }
''';

PluginManifest _load(String text) {
  final result = loadPlugin(writePlugin(text));
  expect(result.reasons, isEmpty);
  return result.manifest!;
}

List<String> _render(PluginManifest manifest, Map<String, Object?> settings) {
  final validated = validateSettings(manifest, settings);
  expect(validated.errors, isEmpty);
  return renderLaunchArgs(
    manifest,
    LaunchContext(
      settings: validated.values,
      ports: const {},
      paths: const {'instance': '/i', 'server': '/s'},
      os: 'linux',
    ),
  );
}

void main() {
  test('conditional_and_joined_arguments', () {
    final args = _render(_load(_logsAndMods), {
      'logs': true,
      'serverMods': ['@CF', '@VPP'],
    });

    expect(args, [
      '-config=serverDZ.cfg',
      '-dologs',
      '-adminlog',
      '-netlog',
      '-mod=@CF;@VPP',
    ]);
  });

  test('mod_roles_joined_into_arguments', () {
    final manifest = _load(dayzManifestText);
    LaunchContext contextWith(Map<String, List<String>> mods) => LaunchContext(
      settings: validateSettings(manifest, {}).values,
      ports: const {'game': 2302},
      paths: const {'instance': '/i', 'server': '/i/server'},
      os: 'windows',
      mods: mods,
    );

    final args = renderLaunchArgs(
      manifest,
      contextWith({
        'client': ['@CF', '@VPP'],
        'server': ['@VPPAdminTools'],
      }),
    );
    final emptyRole = renderLaunchArgs(
      manifest,
      contextWith({
        'client': ['@CF', '@VPP'],
        'server': <String>[],
      }),
    );
    final noMods = renderLaunchArgs(manifest, contextWith({}));

    expect(args, [
      '-config=yagura/serverDZ.cfg',
      '-port=2302',
      '-mod=@CF;@VPP',
      '-serverMod=@VPPAdminTools',
    ]);
    expect(emptyRole, [
      '-config=yagura/serverDZ.cfg',
      '-port=2302',
      '-mod=@CF;@VPP',
    ]);
    expect(noMods, ['-config=yagura/serverDZ.cfg', '-port=2302']);
  });

  test('secret_outside_the_secrets_namespace', () {
    for (final (template, mentions) in [
      // A secret setting through `settings`, and a non-secret through
      // `secrets`.
      ('-rcon={{settings.rconPassword}}', 'settings.rconPassword'),
      ('-max={{secrets.maxPlayers}}', 'secrets.maxPlayers'),
    ]) {
      final result = loadPlugin(
        writePlugin(dayzWith('-config=yagura/serverDZ.cfg', template)),
      );

      expect(result.status, PluginStatus.rejected, reason: template);
      final reason = result.reasons.single;
      expect(reason.code, 'invalid_manifest');
      expect(reason.message, contains(template), reason: 'names the template');
      expect(reason.message, contains(mentions));
      expect(reason.path, 'launch.args[0]');
    }
  });

  test('template_references_an_unknown_setting', () {
    final result = loadPlugin(
      writePlugin(
        valheimWith('"{{settings.serverName}}"', '"{{settings.doesNotExist}}"'),
      ),
    );

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.message, contains('{{settings.doesNotExist}}'));
    expect(reason.message, contains('settings.doesNotExist'));
    expect(reason.path, startsWith('launch.args['));
  });

  group('beyond the test map', () {
    late PluginManifest manifest;
    setUp(() => manifest = _load(_logsAndMods));

    test('conditions off and an empty list render nothing', () {
      expect(_render(manifest, {}), ['-config=serverDZ.cfg']);
      expect(_render(manifest, {'logs': false, 'serverMods': <String>[]}), [
        '-config=serverDZ.cfg',
      ]);
    });

    test('a value with spaces and shell characters stays one argument', () {
      final valheim = _load(valheimManifest());

      final args = renderLaunchArgs(
        valheim,
        const LaunchContext(
          settings: {'serverName': 'My Server; rm -rf /', 'worldName': 'W'},
          ports: {'game': 2456, 'query': 2457},
          paths: {'instance': '/i', 'server': '/s'},
          os: 'linux',
        ),
      );

      expect(args[args.indexOf('-name') + 1], 'My Server; rm -rf /');
      expect(args[args.indexOf('-port') + 1], '2456');
    });

    test('unless inverts a condition', () {
      final text = _logsAndMods.replaceFirst(
        '    - when: settings.logs\n      args: [-dologs, -adminlog, -netlog]\n',
        '    - unless: settings.logs\n      args: [-quiet]\n',
      );

      expect(_render(_load(text), {}), ['-config=serverDZ.cfg', '-quiet']);
      expect(_render(_load(text), {'logs': true}), ['-config=serverDZ.cfg']);
    });

    test('unknown ports, paths, conditions and joins are rejected at load', () {
      for (final (bad, path) in [
        ('"{{ports.nope}}"', 'launch.args[0]'),
        ('"{{paths.nope}}"', 'launch.args[0]'),
        ('"{{nope}}"', 'launch.args[0]'),
        ('"{{settings.serverMods}}"', 'launch.args[0]'),
        ('"{{settings.logs"', 'launch.args[0]'),
      ]) {
        final text = _logsAndMods.replaceFirst('-config=serverDZ.cfg', bad);
        final result = loadPlugin(writePlugin(text));
        expect(result.status, PluginStatus.rejected, reason: bad);
        expect(result.reasons.first.path, path, reason: bad);
      }

      final badWhen = _logsAndMods.replaceFirst(
        'when: settings.logs',
        'when: settings.serverMods',
      );
      expect(
        loadPlugin(writePlugin(badWhen)).reasons.first.path,
        'launch.args[1].when',
      );

      final badJoin = _logsAndMods.replaceFirst(
        'list: settings.serverMods',
        'list: settings.logs',
      );
      expect(
        loadPlugin(writePlugin(badJoin)).reasons.first.path,
        'launch.args[2].join.list',
      );
    });

    test('a secrets reference renders as a structured argument', () {
      final manifest = _load(
        dayzWith('-config=yagura/serverDZ.cfg', '-gslt={{secrets.gslt}}x'),
      );
      final context = LaunchContext(
        settings: validateSettings(manifest, {}).values,
        ports: const {'game': 2302},
        paths: const {'instance': '/i', 'server': '/i/server'},
        os: 'windows',
        secretsSet: const {'gslt'},
      );

      final args = renderLaunchArguments(manifest, context);

      expect(args.first.secretSetting, 'gslt');
      expect(args.first.prefix, '-gslt=');
      expect(args.first.suffix, 'x');
      expect(args.first.redacted, '-gslt=***x');
      expect(args.first.resolve({'gslt': 'T0KEN'}), '-gslt=T0KENx');
      expect(args[1].secretSetting, isNull);
      expect(args[1].resolve(const {}), '-port=2302');
      // The string form never holds a value.
      expect(renderLaunchArgs(manifest, context).first, '-gslt=***x');
    });

    test('an argument naming an unset secret renders nothing', () {
      final manifest = _load(
        dayzWith('-config=yagura/serverDZ.cfg', '-gslt={{secrets.gslt}}'),
      );

      final args = renderLaunchArgs(
        manifest,
        LaunchContext(
          settings: validateSettings(manifest, {}).values,
          ports: const {'game': 2302},
          paths: const {'instance': '/i', 'server': '/i/server'},
          os: 'windows',
        ),
      );

      expect(args, ['-port=2302']);
    });

    test('secrets are allowed in launch arguments and nowhere else', () {
      final ok = loadPlugin(
        writePlugin(
          dayzWith('-config=yagura/serverDZ.cfg', '-gslt={{secrets.gslt}}'),
        ),
      );
      expect(ok.reasons, isEmpty);
      expect(ok.status, PluginStatus.loaded);

      for (final (name, text) in [
        (
          'binding file',
          dayzWith(
            'file: server/yagura/serverDZ.cfg',
            'file: "{{secrets.gslt}}.cfg"',
          ),
        ),
        ('data path', '${dayzManifestText}data_paths: ["{{secrets.gslt}}/"]\n'),
        (
          'condition',
          dayzWith(
            '-config=yagura/serverDZ.cfg',
            '-config=x\n    - when: secrets.gslt\n      args: [-y]',
          ),
        ),
      ]) {
        final result = loadPlugin(writePlugin(text));
        expect(result.status, PluginStatus.rejected, reason: name);
      }
    });

    test('an unknown mod role or a scalar use of a role is rejected', () {
      final unknown = loadPlugin(
        writePlugin(dayzWith('list: mods.server', 'list: mods.both')),
      );
      expect(unknown.status, PluginStatus.rejected);
      expect(unknown.reasons.single.path, 'launch.args[3].join.list');
      expect(unknown.reasons.single.message, contains('mods.both'));

      final scalar = loadPlugin(
        writePlugin(
          dayzWith('-config=yagura/serverDZ.cfg', '-mods={{mods.client}}'),
        ),
      );
      expect(scalar.status, PluginStatus.rejected);
      expect(scalar.reasons.single.path, 'launch.args[0]');
      expect(scalar.reasons.single.message, contains('join'));
    });

    test('mods references need a mods section', () {
      final text = valheimWith('-nographics', '"{{mods.client}}"');

      final result = loadPlugin(writePlugin(text));

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.message, contains('mods.client'));
    });

    test('the os and paths namespaces render', () {
      final text = _logsAndMods.replaceFirst(
        '-config=serverDZ.cfg',
        '"{{paths.server}}-{{os}}-{{instance}}"',
      );

      expect(_render(_load(text), {}).first, '/s-linux-/i');
    });
  });
}
