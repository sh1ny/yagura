import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/plugins/plugin_registry.dart';

import '../support/daemon_support.dart';

void edit(TestEnv env, String from, String to) {
  final file = File(p.join(env.pluginsDir, 'valheim', 'plugin.yaml'));
  final text = file.readAsStringSync();
  expect(text, contains(from), reason: 'edit target');
  file.writeAsStringSync(text.replaceFirst(from, to));
}

void main() {
  test('fixed_manifest_picked_up', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    edit(env, '- -nographics', '- -nographics-edited');
    final outcomes = await daemon.instances.reloadPlugins();

    expect(outcomes.single.id, 'valheim');
    expect(outcomes.single.status, PluginReloadStatus.reloaded);
    final start = daemon.instances.start(instance.id);
    await daemon.operations.whenDone(start.id);
    expect(env.process.launches.single.args, contains('-nographics-edited'));
    expect(env.process.launches.single.args, isNot(contains('-nographics')));
  });

  test('broken_edit_keeps_the_old_version', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    edit(env, 'strategy: signal', 'strategy: banana');
    final outcomes = await daemon.instances.reloadPlugins();

    expect(outcomes.single.id, 'valheim');
    expect(outcomes.single.status, PluginReloadStatus.reloadFailed);
    expect(outcomes.single.reasons, isNotEmpty);
    expect(outcomes.single.reasons.first.code, 'invalid_manifest');
    final start = daemon.instances.start(instance.id);
    await daemon.operations.whenDone(start.id);
    expect(env.process.launches.single.args, contains('-nographics'));
    expect(daemon.instances.get(instance.id).state.wireName, 'running');
  });

  test('plugins_are_not_reloaded_on_file_change', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    edit(env, '- -nographics', '- -nographics-edited');
    final start = daemon.instances.start(instance.id);
    await daemon.operations.whenDone(start.id);

    expect(env.process.launches.single.args, contains('-nographics'));
    expect(
      env.process.launches.single.args,
      isNot(contains('-nographics-edited')),
    );
  });
}
