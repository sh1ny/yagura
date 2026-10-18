import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';

Map<String, Object?> readInstanceFile(Instance instance) => jsonDecode(
  File(p.join(instance.directory, 'instance.json')).readAsStringSync(),
) as Map<String, Object?>;

UpdateSettingsRequest rename(Instance instance, String name) =>
    UpdateSettingsRequest(
      instanceId: instance.id,
      settings: {...instance.settings, 'serverName': name},
    );

void main() {
  test('change_persisted_and_mirrored', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);

    daemon.instances.updateSettings(rename(instance, 'Renamed'));
    await env.kill(daemon);

    final restarted = await env.start();
    expect(
      restarted.instances.get(instance.id).settings['serverName'],
      'Renamed',
    );
    final file = readInstanceFile(instance);
    expect((file['settings']! as Map)['serverName'], 'Renamed');
    expect(file['format_version'], 1);
    expect((file['plugin']! as Map)['id'], 'valheim');
    expect((file['plugin']! as Map)['version'], '0.1.0');
    expect(
      ((file['ports']! as List).first as Map).values,
      containsAll(['game', 2456]),
    );
  });

  test('instance_json_write_fails', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    final notices = <InstanceNotice>[];
    daemon.instances.events.listen((e) {
      if (e is InstanceNotice) notices.add(e);
    });
    // A directory where the file belongs: the atomic replace cannot succeed.
    final target = p.join(instance.directory, 'instance.json');
    File(target).deleteSync();
    Directory(target).createSync();

    final saved = daemon.instances.updateSettings(rename(instance, 'Renamed'));

    expect(saved.settings['serverName'], 'Renamed');
    await eventually(() => notices.isNotEmpty, reason: 'warning event');
    expect(notices.single.kind, 'instance_file_stale');
    expect(notices.single.instanceId, instance.id);

    // Rewritten at the next daemon start once the obstacle is gone.
    Directory(target).deleteSync();
    await env.kill(daemon);
    await env.start();
    expect(
      (readInstanceFile(instance)['settings']! as Map)['serverName'],
      'Renamed',
    );
  });

  test('secrets_excluded_from_instance_json', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final instance = await createValheim(daemon);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');

    final text = File(p.join(instance.directory, 'instance.json'))
        .readAsStringSync();
    final settings = (jsonDecode(text) as Map)['settings']! as Map;

    expect(settings['password'], {'secret': true});
    expect(text, isNot(contains('hunter2')));
    expect(settings['serverName'], 'Friends');
  });
}
