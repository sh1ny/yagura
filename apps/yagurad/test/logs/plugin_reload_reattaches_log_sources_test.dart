import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/daemon_support.dart';

void main() {
  test('a plugin reload re-attaches the log sources it changed', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    await eventually(
      () => logSourcesOf(daemon, instance.id).any((s) => s.name == 'server'),
      reason: 'the declared source is attached',
    );

    // The plugin points its log source at another file; no instance event
    // follows the reload.
    final manifest = File(p.join(env.pluginsDir, 'valheim', 'plugin.yaml'));
    manifest.writeAsStringSync(
      manifest.readAsStringSync().replaceFirst(
        'path: "logs/server.log"',
        'path: "logs/game.log"',
      ),
    );
    final outcomes = await daemon.instances.reloadPlugins();
    expect(outcomes.single.toString(), contains('reloaded'));

    final file = File(p.join(instance.directory, 'logs', 'game.log'))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync('from the new file\n');
    await eventually(() {
      unawaited(daemon.logs.pollNow(instance.id));
      return daemon.logs
          .backlog(instance.id)
          .entries
          .any((e) => e.text == 'from the new file');
    }, reason: 'the new file is tailed after the reload');
  });
}
