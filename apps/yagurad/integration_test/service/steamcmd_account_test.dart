@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../../test/support/account_support.dart';
import '../../test/support/elevated_support.dart';
import '../../test/support/service_client.dart';
import '../../test/support/service_rig.dart';

// steam-management, "SteamCMD runs as its own account" (design D10, ADR 0015).
// The service starts SteamCMD as `yagura-steam`, which has no access to the
// database or the other accounts' secrets. The rows install the real service
// with a fake SteamCMD (compiled fixture) and drive Install through the API
// as a paired device. They create local accounts and a Windows service, so
// they run only in the manual `elevated` workflow.

const _firstLogon = Duration(minutes: 10);

/// A service with the fake SteamCMD and a paired client, and one instance.
Future<(ServiceRig, ServiceClient, pb.Instance)> _start() async {
  final rig = await ServiceRig.create(instances: 0);
  await rig.seedFakeSteamCmd();
  await rig.install();
  final client = await ServiceClient.pair(rig);
  final instance = await client.instances.createInstance(
    pb.CreateInstanceRequest(
      pluginId: 'valheim',
      name: 'Steam account',
      settings: pb.JsonDocument(json: '{"serverName":"Steam account"}'),
    ),
  );
  return (rig, client, instance);
}

void main() {
  test('steamcmd_runs_without_system_rights', tags: ['elevated'], () async {
    final (rig, client, instance) = await _start();

    await client.succeeded(
      await client.instances.install(
        pb.LifecycleRequest(instanceId: instance.id),
      ),
      timeout: _firstLogon,
    );

    // Whatever SteamCMD wrote belongs to its account, not to SYSTEM: the
    // fake writes the app file the way the real one writes the game.
    final written = File(
      p.join(instance.directory, 'server', 'app_896660.bin'),
    );
    expect(written.existsSync(), isTrue);
    final steam = (await accountSid('yagura-steam'))!;
    expect(await ownerOf(written.path), steam);
    // And its account cannot reach the database.
    expect(await sddlOf(p.join(rig.data, 'yagura.db')), isNot(contains(steam)));
  });

  test('steamcmd_separated_from_game_servers', tags: ['elevated'], () async {
    final (rig, client, instance) = await _start();
    await client.succeeded(
      await client.instances.install(
        pb.LifecycleRequest(instanceId: instance.id),
      ),
      timeout: _firstLogon,
    );
    final srv = (await accountSid('yagura-srv'))!;
    final steam = (await accountSid('yagura-steam'))!;

    // SteamCMD's own folder is the steam account's alone.
    final folder = await sddlOf(p.join(rig.data, 'steamcmd'));
    expect(folder, contains('0x1301bf;;;$steam)'));
    expect(folder, isNot(contains(srv)));
    // The data directory names neither account, and M2 has no content store
    // yet (workshop content is M3; ADR 0015 gives it `yagura-srv` read and
    // execute only, and `yagura-steam` no entry on it).
    final data = await sddlOf(rig.data);
    expect(data, isNot(contains(srv)));
    expect(data, isNot(contains(steam)));
    expect(Directory(p.join(rig.data, 'content')).existsSync(), isFalse);
    // The two accounts are different principals, and what SteamCMD wrote is
    // not owned by the game server account.
    expect(srv, isNot(steam));
    final written = File(
      p.join(instance.directory, 'server', 'app_896660.bin'),
    );
    expect(await ownerOf(written.path), isNot(srv));
  });

  test(
    'link_planted_into_a_system_folder_during_an_update',
    tags: ['elevated'],
    () async {
      final (rig, client, instance) = await _start();

      // A folder only administrators and SYSTEM can use, standing for a
      // system folder.
      final protected = Directory(p.join(rig.work.path, 'system-folder'))
        ..createSync();
      final granted = await runCommand('icacls', [
        protected.path,
        '/inheritance:r',
        '/grant:r',
        '*S-1-5-18:(OI)(CI)F',
        '*S-1-5-32-544:(OI)(CI)F',
      ]);
      expect(granted.exitCode, 0, reason: '${granted.stdout}${granted.stderr}');
      final before = await sddlOf(protected.path);

      // The link sits where SteamCMD writes: `steamapps` of the install.
      final server = Directory(p.join(instance.directory, 'server'))
        ..createSync(recursive: true);
      final made = await runCommand('cmd', [
        '/c',
        'mklink',
        '/J',
        p.join(server.path, 'steamapps'),
        protected.path,
      ]);
      expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');

      await client.ended(
        await client.instances.install(
          pb.LifecycleRequest(instanceId: instance.id),
        ),
        timeout: _firstLogon,
      );

      // Whatever the update did, it wrote nothing through the link and the
      // folder's ACL is as it was.
      expect(protected.listSync(), isEmpty);
      expect(await sddlOf(protected.path), before);
    },
  );
}
