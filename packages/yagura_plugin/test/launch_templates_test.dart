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

    test('the os and paths namespaces render', () {
      final text = _logsAndMods.replaceFirst(
        '-config=serverDZ.cfg',
        '"{{paths.server}}-{{os}}-{{instance}}"',
      );

      expect(_render(_load(text), {}).first, '/s-linux-/i');
    });
  });
}
