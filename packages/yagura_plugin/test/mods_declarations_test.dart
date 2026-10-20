import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

PluginResult _load(String manifest) => loadPlugin(writePlugin(manifest));

void main() {
  group('mods', () {
    test('the declaration is modelled with its defaults', () {
      final text = dayzWith(
        'mods:\n  source: steam_workshop\n  workshop_app_id: 221100\n'
            '  stage: link\n  stage_dir: server\n'
            '  link_name: "@{{mod.name_safe}}"\n  copy_fallback: true\n',
        'mods:\n  source: steam_workshop\n  workshop_app_id: 221100\n',
      );

      final mods = _load(text).manifest!.mods!;

      expect(mods.source, ModSource.steamWorkshop);
      expect(mods.workshopAppId, 221100);
      expect(mods.stage, ModStage.link);
      expect(mods.stageDir, 'server');
      expect(mods.linkName, '{{mod.name_safe}}');
      expect(mods.copyFallback, isFalse);
      expect(mods.keys.single.from, '**/*.bikey');
      expect(mods.keys.single.to, 'server/keys/');
      expect(mods.roles, ['client', 'server']);
    });

    test('every field of the full declaration is read', () {
      final mods = _load(dayzManifestText).manifest!.mods!;

      expect(mods.stage, ModStage.link);
      expect(mods.stageDir, 'server');
      expect(mods.linkName, '@{{mod.name_safe}}');
      expect(mods.copyFallback, isTrue);
    });

    test('url_archive is refused as a source of a later version', () {
      final result = _load(
        dayzWith('source: steam_workshop', 'source: url_archive'),
      );

      expect(result.status, PluginStatus.rejected);
      final reason = result.reasons.single;
      expect(reason.code, 'unsupported_in_this_version');
      expect(reason.path, 'mods.source');
      expect(reason.message, contains('url_archive'));
    });

    test('an unknown source is a schema error naming the allowed values', () {
      final result = _load(dayzWith('source: steam_workshop', 'source: ftp'));

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.first.code, 'invalid_manifest');
      expect(result.reasons.first.path, 'mods.source');
      expect(result.reasons.first.message, contains('steam_workshop'));
    });

    test('a server-managed source stages nothing and carries item ids', () {
      final text = dayzWith(
        'mods:\n  source: steam_workshop\n  workshop_app_id: 221100\n'
            '  stage: link\n  stage_dir: server\n'
            '  link_name: "@{{mod.name_safe}}"\n  copy_fallback: true\n'
            '  keys:\n    - { from: "**/*.bikey", to: server/keys/ }\n',
        'mods:\n  source: server_managed\n  stage: none\n',
      );

      final result = _load(text);

      expect(result.reasons, isEmpty);
      expect(result.manifest!.mods!.source, ModSource.serverManaged);
      expect(result.manifest!.mods!.stage, ModStage.none);
    });

    test('stage modes must suit the source', () {
      for (final (name, from, to, path) in [
        (
          'server_managed with link',
          'source: steam_workshop',
          'source: server_managed',
          'mods.stage',
        ),
        ('workshop with none', 'stage: link', 'stage: none', 'mods.stage'),
      ]) {
        final result = _load(dayzWith(from, to));
        expect(result.status, PluginStatus.rejected, reason: name);
        expect(result.reasons.first.path, path, reason: name);
      }
    });

    test('a workshop source needs workshop_app_id', () {
      final result = _load(dayzWith('  workshop_app_id: 221100\n', ''));

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.path, 'mods.workshop_app_id');
    });

    test('stage_dir and key targets must stay inside the instance', () {
      for (final (from, to, path) in [
        ('stage_dir: server', 'stage_dir: ../outside', 'mods.stage_dir'),
        ('stage_dir: server', r'stage_dir: C:\elsewhere', 'mods.stage_dir'),
        ('to: server/keys/', 'to: ../keys/', 'mods.keys[0].to'),
        ('to: server/keys/', 'to: /abs/keys', 'mods.keys[0].to'),
      ]) {
        final result = _load(dayzWith(from, to));
        expect(result.status, PluginStatus.rejected, reason: to);
        expect(result.reasons.single.path, path, reason: to);
        expect(result.reasons.single.message, contains('instance'));
      }
    });

    test('link_name may use only the mod.name_safe reference', () {
      for (final template in [
        '"@{{mod.nope}}"',
        '"@{{settings.hostname}}"',
        '"{{mod.name_safe}}/x"',
      ]) {
        final result = _load(
          dayzWith('link_name: "@{{mod.name_safe}}"', 'link_name: $template'),
        );
        expect(result.status, PluginStatus.rejected, reason: template);
        expect(result.reasons.single.path, 'mods.link_name', reason: template);
      }
    });

    test('roles are named once, in lowercase', () {
      for (final roles in ['[]', '[client, client]', '[Client]']) {
        final result = _load(
          dayzWith('roles: [client, server]', 'roles: $roles'),
        );
        expect(result.status, PluginStatus.rejected, reason: roles);
        expect(result.reasons.first.path, startsWith('mods.roles'));
      }
    });

    test('key rules need both fields and no unknown ones', () {
      final result = _load(
        dayzWith(
          '{ from: "**/*.bikey", to: server/keys/ }',
          '{ from: "**/*.bikey" }',
        ),
      );

      expect(result.status, PluginStatus.rejected);
      expect(result.reasons.single.message, contains('"to"'));
    });
  });

  group('steam.gslt', () {
    test('names the secret setting that holds the token', () {
      final gslt = _load(dayzManifestText).manifest!.steam!.gslt!;

      expect(gslt.setting, 'gslt');
      expect(gslt.required, isFalse);
    });

    test('required defaults to false and can be set', () {
      final required = _load(dayzWith('required: false', 'required: true'))
          .manifest!
          .steam!
          .gslt!;
      final plain = _load(
        dayzWith('{ setting: gslt, required: false }', '{ setting: gslt }'),
      ).manifest!.steam!.gslt!;

      expect(required.required, isTrue);
      expect(plain.required, isFalse);
    });

    test('must name a declared top-level secret setting', () {
      for (final (setting, why) in [
        ('nope', 'which the manifest does not declare'),
        ('hostname', 'not a secret'),
      ]) {
        final result = _load(
          dayzWith('setting: gslt, required', 'setting: $setting, required'),
        );

        expect(result.status, PluginStatus.rejected, reason: setting);
        final reason = result.reasons.single;
        expect(reason.path, 'steam.gslt.setting');
        expect(reason.message, contains(setting));
        expect(reason.message, contains(why));
      }
    });
  });
}
