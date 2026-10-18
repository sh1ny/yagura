@Tags(['windows'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/reflection.dart';
import 'package:yagurad/src/instances/instance_roots.dart';
import 'package:yagurad/src/platform/acl_writer.dart';

import '../../test/support/admin_support.dart';
import '../../test/support/daemon_support.dart';
import '../../test/support/elevated_support.dart';

const srvSid = 'S-1-5-21-111-222-333-1001';
const steamSid = 'S-1-5-21-111-222-333-1002';

Future<AdminHarness> start(TestEnv env, {FakeAclWriter? acl}) =>
    AdminHarness.start(
      env..installValheim(),
      acl: acl,
      accounts: FakeAccountSids({
        'yagura-srv': srvSid,
        'yagura-steam': steamSid,
      }),
    );

Directory newRoot(TestEnv env, String name) =>
    Directory(p.join(env.root.path, name))..createSync(recursive: true);

void main() {
  test('instance_root_added_locally', () async {
    final env = TestEnv();
    final h = await start(env);
    final root = newRoot(env, 'servers');
    final directory = p.join(root.path, 'valheim-main');
    await expectLater(
      createValheim(h.daemon, directory: directory),
      failsWith('directory_not_allowed'),
      reason: 'not a root yet',
    );

    final result = await h.run(['roots', 'add', root.path]);

    expect(result.code, 0, reason: '$result');
    expect(result.out, contains(root.path));
    final instance = await createValheim(h.daemon, directory: directory);
    expect(instance.directory, directory);
    expect(File(p.join(directory, 'instance.json')).existsSync(), isTrue);
    // The root got the protected descriptor (ADR 0015).
    final call = h.acl.calls.single;
    expect(call.path, root.path);
    expect(call.ownerSid, 'S-1-5-32-544');
    expect(
      call.sddl,
      'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
      '(A;;0x100020;;;$srvSid)(A;;0x100020;;;$steamSid)',
    );
    // And it is audited under the host's name.
    final entry = h.daemon.security!.audit.list().single;
    expect(entry.deviceId, 'host-admin');
    expect(entry.method, 'admin/roots.add');
    expect(entry.target, root.path);
    // No remote call can add or remove a root: the API has no such method.
    final names = DescriptorIndex(pb.yaguraDescriptorSet);
    expect(
      [
        for (final service in names.services)
          for (final method in names.methods[service]!) '$service/$method',
      ].where((m) => m.toLowerCase().contains('root')),
      isEmpty,
    );
  });

  test('instance_on_another_drive', () async {
    // A second drive stands for a second volume: a root that is not under
    // the data directory's parent at all.
    final env = TestEnv();
    final h = await start(env);
    final otherDrive = Directory.systemTemp.createTempSync('yagurad_drive_');
    addTearDown(() => otherDrive.deleteSync(recursive: true));
    await h.run(['roots', 'add', otherDrive.path]);

    final instance = await createValheim(
      h.daemon,
      directory: p.join(otherDrive.path, 'valheim-main'),
    );

    expect(
      File(p.join(otherDrive.path, 'valheim-main', 'instance.json'))
          .existsSync(),
      isTrue,
      reason: 'its files live on the other drive',
    );
    expect(instance.directory, p.join(otherDrive.path, 'valheim-main'));
    // The daemon's own state stays in the data directory.
    expect(File(p.join(env.data, 'yagura.db')).existsSync(), isTrue);
    expect(Directory(p.join(env.data, 'instances')).listSync(), isEmpty);
  });

  test('root_writable_by_non_administrators', () async {
    final env = TestEnv();
    final acl = FakeAclWriter()
      ..failure = Exception('SetKernelObjectSecurity failed with error 5');
    final h = await start(env, acl: acl);
    final root = newRoot(env, 'servers');

    final result = await h.run(['roots', 'add', root.path]);

    expect(result.code, isNot(0));
    expect(result.err, contains('root_not_protected'));
    expect(result.err, contains(root.path));
    // The root was not added, so nothing can be created under it.
    expect((await h.run(['roots', 'list'])).out, isNot(contains(root.path)));
    await expectLater(
      createValheim(h.daemon, directory: p.join(root.path, 'a')),
      failsWith('directory_not_allowed'),
    );
    expect(h.daemon.security!.audit.list().single.result, 'root_not_protected');
  });

  test('root_still_in_use', () async {
    final env = TestEnv();
    final h = await start(env);
    final root = newRoot(env, 'servers');
    await h.run(['roots', 'add', root.path]);
    final instance = await createValheim(
      h.daemon,
      name: 'Friends',
      directory: p.join(root.path, 'valheim-main'),
    );

    final result = await h.run(['roots', 'remove', root.path]);

    expect(result.code, isNot(0));
    expect(result.err, contains('root_in_use'));
    expect(result.err, contains('Friends'));
    // The root stays configured.
    expect((await h.run(['roots', 'list'])).out, contains(root.path));
    await createValheim(
      h.daemon,
      name: 'More',
      ports: {'game': 3000},
      directory: p.join(root.path, 'second'),
    );
    expect(h.daemon.instances.get(instance.id).directory, isNotEmpty);
  });

  test('a_root_without_instances_is_removed', () async {
    final env = TestEnv();
    final h = await start(env);
    final root = newRoot(env, 'servers');
    await h.run(['roots', 'add', root.path]);

    final result = await h.run(['roots', 'remove', root.path]);

    expect(result.code, 0, reason: '$result');
    expect((await h.run(['roots', 'list'])).out, isNot(contains(root.path)));
    await expectLater(
      createValheim(h.daemon, directory: p.join(root.path, 'a')),
      failsWith('directory_not_allowed'),
    );
    // Removing it takes no ACL back (ADR 0015: entries are never withdrawn).
    expect(h.acl.calls, hasLength(1));
  });

  test('roots_list_shows_the_default_root_and_the_added_ones', () async {
    final env = TestEnv();
    final h = await start(env);
    final root = newRoot(env, 'servers');
    await h.run(['roots', 'add', root.path]);

    final result = await h.run(['roots', 'list']);

    expect(result.code, 0, reason: '$result');
    final lines = result.out.trim().split('\n');
    expect(
      lines.firstWhere((l) => l.contains(p.join(env.data, 'instances'))),
      contains('default'),
    );
    expect(
      lines.firstWhere((l) => l.contains(root.path)),
      isNot(contains('default')),
    );
  });

  test('roots_survive_a_daemon_restart', () async {
    final env = TestEnv();
    final h = await start(env);
    final root = newRoot(env, 'servers');
    await h.run(['roots', 'add', root.path]);
    await env.closeDaemons();

    final again = await AdminHarness.start(
      env,
      pipeName: h.pipeName,
      accounts: FakeAccountSids(),
    );

    expect((await again.run(['roots', 'list'])).out, contains(root.path));
    await createValheim(again.daemon, directory: p.join(root.path, 'a'));
  });

  test('adding_a_root_twice_changes_nothing_but_the_descriptor', () async {
    final env = TestEnv();
    final h = await start(env);
    final root = newRoot(env, 'servers');

    expect((await h.run(['roots', 'add', root.path])).code, 0);
    expect((await h.run(['roots', 'add', root.path])).code, 0);

    final listed = (await h.run(['roots', 'list'])).out
        .split('\n')
        .where((l) => l.contains(root.path));
    expect(listed, hasLength(1));
    expect(
      h.acl.calls,
      hasLength(2),
      reason: 'the descriptor is written again',
    );
  });

  test('a_root_that_cannot_be_one_is_refused_without_an_acl_change', () async {
    final env = TestEnv();
    final h = await start(env);
    final file = File(p.join(env.root.path, 'file.txt'))
      ..writeAsStringSync('x');
    final missing = p.join(env.root.path, 'missing');
    final drive = p.rootPrefix(env.root.path);
    final inData = Directory(p.join(env.data, 'plugins'));
    final inInstances = Directory(p.join(env.data, 'instances', 'sub'))
      ..createSync(recursive: true);
    final inside = newRoot(env, 'outer');
    await h.run(['roots', 'add', inside.path]);
    h.acl.calls.clear();

    final cases = <String, String>{
      file.path: 'root_not_protected',
      missing: 'root_not_protected',
      drive: 'directory_not_allowed',
      env.data: 'directory_not_allowed',
      inData.path: 'directory_not_allowed',
      inInstances.path: 'directory_not_allowed',
      p.join(inside.path, 'nested'): 'directory_not_allowed',
      env.root.path: 'directory_not_allowed',
    };
    Directory(p.join(inside.path, 'nested')).createSync();
    for (final MapEntry(key: path, value: reason) in cases.entries) {
      final result = await h.run(['roots', 'add', path]);
      expect(result.code, isNot(0), reason: path);
      expect(result.err, contains(reason), reason: '$path\n$result');
    }

    expect(h.acl.calls, isEmpty);
    expect(
      (await h.run(['roots', 'list'])).out.trim().split('\n'),
      hasLength(2),
      reason: 'the default root and the one valid root',
    );
  });

  test('a_relative_path_is_made_absolute_by_the_command', () async {
    final env = TestEnv();
    final h = await start(env);
    final root = newRoot(env, 'servers');
    final relative = p.relative(root.path);

    final result = await h.run(['roots', 'add', relative]);

    expect(result.code, 0, reason: '$result');
    expect(h.acl.calls.single.path, p.normalize(p.absolute(relative)));
  });

  test('a_roots_command_without_its_argument_is_a_usage_error', () async {
    final env = TestEnv();
    final h = await start(env);

    for (final arguments in [
      ['roots'],
      ['roots', 'add'],
      ['roots', 'remove'],
      ['roots', 'frobnicate'],
      ['roots', 'list', 'extra'],
    ]) {
      final result = await h.run(arguments);
      expect(result.code, 64, reason: '$arguments: $result');
      expect(result.err, contains('usage: yagurad roots'));
    }
  });

  test('a_root_dacl_is_built_from_the_accounts_that_exist', () {
    expect(
      rootDaclSddl(),
      'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)',
      reason: 'no account yet: administrators and the system only',
    );
    expect(
      rootDaclSddl(serverSid: srvSid),
      'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;;0x100020;;;$srvSid)',
    );
    expect(
      rootDaclSddl(serverSid: srvSid, steamSid: steamSid),
      endsWith('(A;;0x100020;;;$srvSid)(A;;0x100020;;;$steamSid)'),
    );
  });

  // The real descriptor, written by SetKernelObjectSecurity with the real
  // owner, needs administrator rights: the elevated workflow.
  test(
    'roots_add_writes_the_real_protected_descriptor',
    tags: ['elevated'],
    () async {
      final root = Directory.systemTemp.createTempSync('yagurad_root_');
      addTearDown(() => root.deleteSync(recursive: true));

      const WindowsAclWriter().writeProtectedDacl(
        root.path,
        rootDaclSddl(),
        ownerSid: administratorsSid,
      );

      final acl = Process.runSync('icacls', [root.path]).stdout as String;
      expect(acl, contains(r'BUILTIN\Administrators:(OI)(CI)(F)'));
      expect(acl, contains(r'NT AUTHORITY\SYSTEM:(OI)(CI)(F)'));
      expect(
        acl,
        isNot(contains('(I)')),
        reason: 'protected: nothing inherited',
      );
      expect(acl, isNot(contains(r'BUILTIN\Users')));
      final owner = powershell('(Get-Acl -LiteralPath "${root.path}").Owner');
      expect((owner.stdout as String).trim(), r'BUILTIN\Administrators');
    },
  );
}
