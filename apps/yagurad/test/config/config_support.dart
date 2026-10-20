import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';

/// One manifest binding as `plugin.yaml` text.
String bindingYaml({
  required String file,
  required String format,
  required String key,
  required String setting,
  bool? create,
  String? template,
  bool? gameWrites,
}) =>
    '''
  - file: $file
    format: $format
    key: $key
    setting: $setting
${create == null ? '' : '    create: $create\n'}${template == null ? '' : '    template: $template\n'}${gameWrites == null ? '' : '    game_writes: $gameWrites\n'}''';

/// Installs the Valheim fixture with two more settings, `maxPlayers` (integer)
/// and `rconPassword` (secret), a `bindings` section made of [bindings], and
/// the plugin files [templates] (relative path to content).
String installBound(
  TestEnv env, {
  required List<String> bindings,
  Map<String, String> templates = const {},
  String? hooks,
}) {
  final dir = env.installValheim(hooks: hooks);
  env.editValheim(
    '    label: Server password\n    group: General\n',
    '    label: Server password\n    group: General\n'
        '  maxPlayers:\n    type: integer\n    default: 10\n    min: 1\n'
        '    max: 127\n'
        '  rconPassword:\n    type: secret\n    label: RCON password\n',
  );
  env.editValheim(
    'launch:\n  args:',
    'bindings:\n${bindings.join()}\nlaunch:\n  args:',
  );
  for (final MapEntry(:key, :value) in templates.entries) {
    File(p.join(dir, key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  return dir;
}

/// Creates a Valheim instance with `maxPlayers` [maxPlayers] and installs it.
Future<Instance> createBound(Daemon daemon, {int maxPlayers = 40}) async {
  final instance = await createValheim(
    daemon,
    settings: {...valheimSettings(), 'maxPlayers': maxPlayers},
  );
  await daemon.operations.whenDone(daemon.instances.install(instance.id).id);
  return daemon.instances.get(instance.id);
}

/// A file inside the instance, with its directory created.
File instanceFile(Instance instance, String relative, [String? content]) {
  final file = File(p.join(instance.directory, relative));
  file.parent.createSync(recursive: true);
  if (content != null) file.writeAsStringSync(content);
  return file;
}

/// The hashes the binder recorded for [instanceId], by path; read from a
/// second connection to the daemon's database.
Map<String, String> boundFileHashes(TestEnv env, String instanceId) {
  final db = sqlite3.open(
    p.join(env.data, 'yagura.db'),
    mode: OpenMode.readOnly,
  );
  try {
    return {
      for (final row in db.select(
        'SELECT path, hash FROM bound_files WHERE instance_id = ?',
        [instanceId],
      ))
        row['path']! as String: row['hash']! as String,
    };
  } finally {
    db.close();
  }
}

String sha256Of(File file) => sha256.convert(file.readAsBytesSync()).toString();

/// The warnings of an operation that report a hand edit.
List<String> externalEdits(List<String> warnings) => [
  for (final w in warnings)
    if (w.startsWith('external_edit')) w,
];
