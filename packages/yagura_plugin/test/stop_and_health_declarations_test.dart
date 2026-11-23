import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

void main() {
  test('bindings_and_mods_sections_accepted', () {
    final result = loadPlugin(writePlugin(dayzManifestText));

    expect(result.reasons, isEmpty);
    expect(result.status, PluginStatus.loaded);
    final manifest = result.manifest!;
    expect(manifest.bindings, hasLength(1));
    expect(manifest.mods, isNotNull);
    expect(manifest.mods!.source, ModSource.steamWorkshop);
    expect(manifest.mods!.roles, ['client', 'server']);

    // Only an rcon section would be rejected.
    final withRcon = loadPlugin(
      writePlugin('${dayzManifestText}rcon:\n  port: game\n'),
    );
    expect(withRcon.status, PluginStatus.rejected);
    expect(withRcon.reasons.single.path, 'rcon');
  });

  test('invalid_health_regex', () {
    final result = loadPlugin(
      writePlugin(
        valheimWith(
          'log_match: "Game server connected"',
          'log_match: "([unclosed"',
        ),
      ),
    );

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.path, 'health.log_match');
    expect(reason.message, contains('([unclosed'));
    expect(reason.message, matches(RegExp('[Uu]nterminated|[Mm]issing|group')));
  });

  test('unsupported_stop_strategy', () {
    final result = loadPlugin(
      writePlugin(valheimWith('strategy: signal', 'strategy: rcon')),
    );

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.code, 'unsupported_in_this_version');
    expect(reason.path, 'stop.strategy');
  });

  group('beyond the test map', () {
    test('health type query is unsupported in this version', () {
      final result = loadPlugin(
        writePlugin(
          valheimWith(
            'type: log_match\n  log_match: "Game server connected"\n  source: server\n',
            'type: query\n',
          ),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.code, 'unsupported_in_this_version');
      expect(result.reasons.single.path, 'health.type');
    });

    test('the rcon section is unsupported in this version', () {
      final result = loadPlugin(
        writePlugin('${valheimManifest()}\nrcon:\n  anything: 1\n'),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.code, 'unsupported_in_this_version');
      expect(result.reasons.single.path, 'rcon');
    });

    test('log_match must name a declared log source', () {
      final result = loadPlugin(
        writePlugin(valheimWith('source: server', 'source: nowhere')),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'health.source');
    });

    test('a port health check must name a declared port', () {
      final result = loadPlugin(
        writePlugin(
          valheimWith(
            'type: log_match\n  log_match: "Game server connected"\n  source: server\n',
            'type: port\n  port: nope\n',
          ),
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'health.port');
    });

    test('kill is a supported stop strategy', () {
      final result = loadPlugin(
        writePlugin(valheimWith('strategy: signal', 'strategy: kill')),
      );

      expect(result.status, PluginStatus.loaded);
    });
  });
}
