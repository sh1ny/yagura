import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The Valheim manifest used as the reference fixture (shaped like the real
/// plugin of task 9.1).
String valheimManifest() =>
    File(p.join('test', 'fixtures', 'valheim', 'plugin.yaml'))
        .readAsStringSync();

/// Replaces [from] with [to] in the Valheim manifest, failing when [from] is
/// not present so a fixture edit cannot silently do nothing.
String valheimWith(String from, String to) {
  final text = valheimManifest();
  expect(text, contains(from), reason: 'fixture edit target');
  return text.replaceFirst(from, to);
}

/// Creates `<temp>/<folder>/plugin.yaml` (and optionally `hooks.js`) in a fresh
/// temporary directory removed at tear-down, and returns the plugin directory.
String writePlugin(String manifest, {String folder = 'x', List<int>? hooks}) {
  final root = Directory.systemTemp.createTempSync('yagura_plugin_test_');
  addTearDown(() => root.deleteSync(recursive: true));
  final dir = Directory(p.join(root.path, folder))..createSync();
  File(p.join(dir.path, 'plugin.yaml')).writeAsStringSync(manifest);
  if (hooks != null) File(p.join(dir.path, 'hooks.js')).writeAsBytesSync(hooks);
  return dir.path;
}

/// A DayZ-shaped manifest: bindings, mods with two roles, a GSLT secret and
/// launch arguments that join each mod role (the shape of `plugins/dayz`).
const dayzManifestText = '''
manifest_version: 1
id: dayz
name: DayZ
version: 0.1.0
steam:
  app_id: 223350
  login: account
  gslt: { setting: gslt, required: false }
executable:
  windows: DayZServer_x64.exe
ports:
  - name: game
    default: 2302
    protocol: udp
    purpose: game
settings:
  hostname: { type: string, default: DayZ }
  maxPlayers: { type: integer, default: 60, min: 1, max: 127 }
  rconPassword: { type: secret }
  gslt: { type: secret }
bindings:
  - file: server/yagura/serverDZ.cfg
    format: dayz-cfg
    key: hostname
    setting: hostname
    create: true
mods:
  source: steam_workshop
  workshop_app_id: 221100
  stage: link
  stage_dir: server
  link_name: "@{{mod.name_safe}}"
  copy_fallback: true
  keys:
    - { from: "**/*.bikey", to: server/keys/ }
  roles: [client, server]
launch:
  args:
    - -config=yagura/serverDZ.cfg
    - "-port={{ports.game}}"
    - join: { list: mods.client, separator: ";", prefix: "-mod=" }
    - join: { list: mods.server, separator: ";", prefix: "-serverMod=" }
    - "-gslt={{secrets.gslt}}"
''';

/// [dayzManifestText] with [from] replaced by [to], failing when [from] is not
/// present.
String dayzWith(String from, String to) {
  expect(dayzManifestText, contains(from), reason: 'fixture edit target');
  return dayzManifestText.replaceFirst(from, to);
}
