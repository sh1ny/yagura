@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/platform/win32_service.dart';

import '../../test/support/account_support.dart';
import '../../test/support/process_support.dart';
import '../../test/support/service_client.dart';
import '../../test/support/service_rig.dart';

// host-service, "Game servers run under a low-privilege account" (design D7,
// ADR 0013, ADR 0015). The service creates `yagura-srv` and `yagura-steam`
// itself, starts the instances that were requested running when it comes up,
// and the rows look at the processes and the ACLs it made. These rows create
// local accounts and a Windows service, so they run only in the manual
// `elevated` workflow, on a throwaway runner, one at a time
// (`dart test --concurrency 1 -t elevated`), never on a developer's desktop.

const _firstLogon = Duration(minutes: 5);

void main() {
  test('server_process_identity', tags: ['elevated'], () async {
    final rig = await ServiceRig.create(instances: 1);
    await rig.install();

    await rig.whenServersAttached(1, timeout: _firstLogon);

    final pid = rig.runningServers().values.single;
    expect(await processOwnerSid(pid), await accountSid('yagura-srv'));
    // Users only: the account is not an administrator.
    expect(await isMemberOf('Administrators', 'yagura-srv'), isFalse);
    expect(await isMemberOf('Users', 'yagura-srv'), isTrue);
    // And it cannot open the database: no entry of its DACL names the
    // account, Users or Everyone.
    final sid = await accountSid('yagura-srv');
    expect(sid, isNotNull);
    final database = await sddlOf(p.join(rig.data, 'yagura.db'));
    expect(database, isNot(contains(sid!)));
    for (final alias in ['BU', 'WD', 'AU']) {
      expect(database, isNot(contains(';;;$alias)')), reason: alias);
    }
  });

  test('instance_created_before_the_service', tags: ['elevated'], () async {
    // Made by a dev daemon, as the current user, before the service existed.
    final rig = await ServiceRig.create(instances: 2);
    await rig.seedFakeSteamCmd();
    final rows = queryDatabase(rig.data, 'SELECT id, directory FROM instances');
    final directories = [for (final row in rows) row['directory']! as String];
    expect(directories, hasLength(2));

    await rig.install();
    await rig.whenServersAttached(2, timeout: _firstLogon);

    // Both servers run as the account and did not fail with access denied;
    // the one-time migration gave each directory its DACL.
    final srv = await accountSid('yagura-srv');
    final steam = await accountSid('yagura-steam');
    for (final pid in rig.runningServers().values) {
      expect(await processOwnerSid(pid), await accountSid('yagura-srv'));
    }
    for (final directory in directories) {
      final sddl = await sddlOf(directory);
      expect(sddl, startsWith('O:BA'), reason: directory);
      expect(sddl, contains('D:P'), reason: 'protected: $directory');
      for (final sid in [srv!, steam!]) {
        expect(sddl, contains(';;;$sid)'), reason: '$sid on $directory');
      }
      // A file the dev daemon made inherits the entries now.
      final file = Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .first;
      expect(await sddlOf(file.path), contains(';;;$srv)'));
    }
    final layouts = queryDatabase(rig.data, 'SELECT acl_layout FROM instances');
    expect(layouts.map((r) => r['acl_layout']), everyElement(1));

    // The first update of an instance the dev daemon made runs SteamCMD as
    // `yagura-steam` on it: no access denied, and what it writes is the steam
    // account's. The running server is stopped and started again around it.
    final client = await ServiceClient.pair(rig);
    final id = rows.first['id']! as String;
    await client.succeeded(
      await client.instances.update(pb.LifecycleRequest(instanceId: id)),
      timeout: _firstLogon,
    );
    final written = File(p.join(directories.first, 'server', 'app_896660.bin'));
    expect(written.existsSync(), isTrue);
    expect(await ownerOf(written.path), steam);
  });

  test('logon_fails', tags: ['elevated'], () async {
    final rig = await ServiceRig.create(instances: 1);
    await rig.install();
    await rig.whenServersAttached(1, timeout: _firstLogon);
    final pid = rig.runningServers().values.single;

    // The server stops while the service is down and the account is
    // disabled: the next start of the instance cannot log it on.
    await rig.stopService();
    await rig.eventuallyHolds(
      () => rig.serviceState == serviceStopped,
      reason: 'the service to stop',
    );
    Process.killPid(pid);
    await rig.eventuallyHolds(
      () => !processAlive(pid),
      reason: 'the server to exit',
      timeout: const Duration(seconds: 30),
    );
    final disabled = await disableAccount('yagura-srv');
    expect(disabled, isTrue);

    await rig.startService();

    await rig.eventuallyHolds(
      () => queryDatabase(
        rig.data,
        "SELECT id FROM operations WHERE result_reason = 'launch_logon_failed'",
      ).isNotEmpty,
      reason: 'the start to fail with launch_logon_failed',
      timeout: _firstLogon,
    );
    final failed = queryDatabase(
      rig.data,
      "SELECT result_message FROM operations WHERE result_reason = "
      "'launch_logon_failed'",
    ).first;
    // The message names the Windows error.
    expect('${failed['result_message']}', matches(RegExp(r'\b\d{3,4}\b')));
    // The instance stays stopped.
    expect(
      queryDatabase(rig.data, 'SELECT state FROM instances').single['state'],
      'stopped',
    );
  });

  test('game_server_account_access_set', tags: ['elevated'], () async {
    final rig = await ServiceRig.create(instances: 1);
    await rig.install();
    await rig.whenServersAttached(1, timeout: _firstLogon);
    final srv = (await accountSid('yagura-srv'))!;
    final steam = (await accountSid('yagura-steam'))!;
    final instance =
        queryDatabase(
              rig.data,
              'SELECT directory FROM instances',
            ).single['directory']!
            as String;

    // Data directory and database: SYSTEM and Administrators only, owned by
    // Administrators.
    for (final path in [rig.data, p.join(rig.data, 'yagura.db')]) {
      final sddl = await sddlOf(path);
      expect(sddl, startsWith('O:BA'), reason: path);
      expect(sddl, isNot(contains(srv)), reason: path);
      expect(sddl, isNot(contains(steam)), reason: path);
      expect(sddl, isNot(contains(';;;BU)')), reason: path);
    }
    // The instance root: traverse only for both accounts.
    final root = await sddlOf(p.join(rig.data, 'instances'));
    expect(root, contains('(A;;0x100020;;;$srv)'));
    expect(root, contains('(A;;0x100020;;;$steam)'));
    // The instance directory: one entry on the directory (no DELETE) and one
    // modify entry for its contents, for each account.
    final sddl = await sddlOf(instance);
    for (final sid in [srv, steam]) {
      expect(sddl, contains('(A;;0x1200ef;;;$sid)'));
      expect(sddl, contains('(A;OICIIO;0x1301bf;;;$sid)'));
    }
    // SteamCMD's folder: only the steam account, with modify.
    final steamcmd = await sddlOf(p.join(rig.data, 'steamcmd'));
    expect(steamcmd, contains('0x1301bf;;;$steam)'));
    expect(steamcmd, isNot(contains(srv)));
    // The accounts hold their logon rights in the local security policy:
    // batch logon for the game server account, and neither account may log on
    // interactively, remotely or over the network.
    const denied = [
      'SeDenyInteractiveLogonRight',
      'SeDenyRemoteInteractiveLogonRight',
      'SeDenyNetworkLogonRight',
    ];
    expect(
      await rightsOf('yagura-srv'),
      containsAll(['SeBatchLogonRight', ...denied]),
    );
    expect(await rightsOf('yagura-steam'), containsAll(denied));
  });
}
