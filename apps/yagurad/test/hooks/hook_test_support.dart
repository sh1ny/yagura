import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/hooks/hooks.dart';

/// A fresh instance directory removed when the test ends.
Directory makeInstance() {
  final dir = Directory.systemTemp.createTempSync('yagura_hook_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

HookContext testContext() => HookContext(
  instanceId: 'inst-1',
  pluginId: 'dayz',
  pluginVersion: '1.0.0',
  os: 'windows',
  paths: {'config': 'cfg', 'keys': 'keys'},
  settings: {
    'maxPlayers': 60,
    'rconPassword': {'secret': true, 'set': false},
  },
  ports: {'game': 2302},
);

HookInvocation invocationFor(
  Directory instance,
  String source, {
  HookPoint point = HookPoint.onPreStart,
  Duration deadline = const Duration(seconds: 5),
}) => HookInvocation(
  point: point,
  source: source,
  context: testContext(),
  root: InstanceRoot(instance.path),
  deadline: deadline,
);

File writeInstanceFile(Directory instance, String relative, String content) {
  final file = File(p.join(instance.path, relative));
  file.parent.createSync(recursive: true);
  return file..writeAsStringSync(content);
}
