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
