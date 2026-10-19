import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/confined_fs.dart';
import 'package:yagurad/src/host/acl_layout.dart';
import 'package:yagurad/src/instances/instance_acls.dart';

import '../support/acl_support.dart';
import '../support/admin_support.dart' show FakeAccountSids;
import '../support/daemon_support.dart';

// Design D6, ADR 0015. The walk is the same code the Windows backend runs;
// these tests record the calls it makes through a backend that does not touch
// the machine's ACLs. The `elevated` rows run the real calls.

const server = 'S-1-5-21-1-2-3-2001';
const steam = 'S-1-5-21-1-2-3-2002';

class _Data {
  _Data(this.root, this.backend) : fs = ConfinedFs.withBackend(root, backend);

  final String root;
  final RecordingBackend backend;
  final ConfinedFs fs;

  static _Data create() {
    final env = TestEnv();
    final root = p.join(env.root.path, 'data');
    for (final dir in [
      'snapshots/deep',
      'logs',
      'plugins',
      'instances/one',
      'steamcmd/win',
      'content/v1',
    ]) {
      Directory(p.join(root, dir)).createSync(recursive: true);
    }
    for (final file in [
      'yagura.db',
      'yagurad.lock',
      'snapshots/deep/a.bin',
      'steamcmd/win/steamcmd.exe',
      'content/v1/data',
      'instances/one/save.dat',
    ]) {
      File(p.join(root, file)).writeAsStringSync('x');
    }
    return _Data(root, RecordingBackend(root));
  }

  void trustedMarker(String version, {String owner = 'BA'}) {
    File(p.join(root, aclLayoutFile)).writeAsStringSync('$version\n');
    backend.owners[aclLayoutFile] = 'O:${owner}D:P(A;;FA;;;SY)';
  }
}

void main() {
  group('the data directory walk', () {
    test('sets the explicit DACLs and the inherited entries', () {
      final data = _Data.create();

      final ran = walkDataDirectory(
        data.fs,
        serverSid: server,
        steamSid: steam,
        complete: true,
      );

      expect(ran, isTrue);
      final backend = data.backend;
      // Everything is owned by Administrators.
      expect(
        backend.writes.map((w) => w.ownerSid),
        everyElement(equals('S-1-5-32-544')),
      );
      // The three explicit DACLs are protected and written on the folders.
      expect(backend.writeFor('instances').inherit, isFalse);
      expect(backend.writeFor('instances').sddl, contains(server));
      expect(backend.writeFor('steamcmd').sddl, contains('0x1301bf;;;$steam'));
      expect(backend.writeFor('steamcmd').sddl, startsWith('D:P'));
      expect(backend.writeFor('content').sddl, contains('0x1200a9;;;$server'));
      // Children take the entries of the parent: SYSTEM and Administrators.
      for (final path in [
        'yagura.db',
        'yagurad.lock',
        'snapshots',
        'snapshots/deep',
        'snapshots/deep/a.bin',
        'logs',
        'plugins',
      ]) {
        final write = backend.writeFor(path);
        expect(write.inherit, isTrue, reason: path);
        expect(write.sddl, startsWith('D:AI'), reason: path);
        expect(write.sddl, isNot(contains(steam)), reason: path);
        expect(write.sddl, isNot(contains('BU')), reason: path);
      }
      // Below steamcmd the steam account has modify, below content the server
      // account has read and execute.
      expect(
        backend.writeFor('steamcmd/win/steamcmd.exe').sddl,
        '${'D:AI(A;ID;FA;;;SY)(A;ID;FA;;;BA)'}(A;ID;0x1301bf;;;$steam)',
      );
      expect(
        backend.writeFor('content/v1').sddl,
        contains('(A;OICIID;0x1200a9;;;$server)'),
      );
      // The instances folder is not entered.
      expect(
        backend.paths.where((path) => path.startsWith('instances/')),
        isEmpty,
      );
      // The version is recorded once the accounts were in.
      expect(readAclLayout(data.fs), 0, reason: 'owner unknown to the backend');
      expect(
        File(p.join(data.root, aclLayoutFile)).readAsStringSync().trim(),
        '$currentAclLayout',
      );
    });

    test('does not record the version before the accounts exist', () {
      final data = _Data.create();

      walkDataDirectory(data.fs, complete: false);

      expect(File(p.join(data.root, aclLayoutFile)).existsSync(), isFalse);
      expect(data.backend.writeFor('steamcmd').sddl, isNot(contains(steam)));
    });

    test('does not walk again at the current layout', () {
      final data = _Data.create()..trustedMarker('$currentAclLayout');

      final ran = walkDataDirectory(data.fs, complete: true);

      expect(ran, isFalse);
      expect(data.backend.writes, isEmpty);
    });

    test('walks again below the current layout', () {
      final data = _Data.create()..trustedMarker('0');

      expect(walkDataDirectory(data.fs, complete: true), isTrue);
    });

    // layout_marker_planted_by_a_standard_user (unit analogue)
    test('a marker a standard user owns counts as version 0', () {
      final data = _Data.create()
        ..trustedMarker('$currentAclLayout', owner: 'BU');

      expect(readAclLayout(data.fs), 0);
      expect(walkDataDirectory(data.fs, complete: true), isTrue);
      expect(data.backend.writeFor('yagura.db').ownerSid, 'S-1-5-32-544');
    });

    test('a marker with two names counts as version 0', () {
      final data = _Data.create()..trustedMarker('$currentAclLayout');
      data.backend.hardLinks[aclLayoutFile] = 2;

      expect(readAclLayout(data.fs), 0);
    });

    test('a marker that is a link counts as version 0', () {
      final data = _Data.create()..trustedMarker('$currentAclLayout');
      data.backend.links.add(aclLayoutFile);

      expect(readAclLayout(data.fs), 0);
    });

    test('a marker owned by SYSTEM or Administrators counts', () {
      for (final owner in ['SY', 'BA']) {
        final data = _Data.create()
          ..trustedMarker('$currentAclLayout', owner: owner);
        expect(readAclLayout(data.fs), currentAclLayout, reason: owner);
      }
    });

    test('a marker that is not a number counts as version 0', () {
      final data = _Data.create()..trustedMarker('seven');

      expect(readAclLayout(data.fs), 0);
    });

    // link_in_the_data_directory_at_first_service_start (unit analogue)
    test('a link in the data directory stops the walk', () {
      final data = _Data.create();
      data.backend.links.add('snapshots');

      expect(
        () => walkDataDirectory(data.fs, complete: true),
        throwsA(isA<AclLinkFound>().having((e) => e.path, 'path', 'snapshots')),
      );
      expect(data.backend.paths, isNot(contains('snapshots')));
      expect(File(p.join(data.root, aclLayoutFile)).existsSync(), isFalse);
    });

    test('a link deeper in a child stops the walk and is not entered', () {
      final data = _Data.create();
      data.backend.links.add('snapshots/deep');

      expect(
        () => walkDataDirectory(data.fs, complete: true),
        throwsA(
          isA<AclLinkFound>().having((e) => e.path, 'path', 'snapshots/deep'),
        ),
      );
      expect(data.backend.paths, isNot(contains('snapshots/deep/a.bin')));
    });
  });

  group('the instance directory ACL', () {
    test('has one entry on the directory and one for its contents', () {
      final sddl = instanceDacl(serverSid: server, steamSid: steam);

      expect(sddl, startsWith('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'));
      for (final sid in [server, steam]) {
        // On the directory itself: no DELETE (0x10000), so it cannot be
        // renamed or removed by the account.
        expect(sddl, contains('(A;;0x1200ef;;;$sid)'));
        // Inherited by what is inside, modify.
        expect(sddl, contains('(A;OICIIO;0x1301bf;;;$sid)'));
      }
      expect(0x1200ef & 0x10000, 0, reason: 'no DELETE on the directory');
      expect(0x1200ef & 0x40, isNot(0), reason: 'FILE_DELETE_CHILD');
    });

    test('leaves out an account that does not exist', () {
      expect(
        instanceDacl(serverSid: server),
        isNot(contains('S-1-5-21-1-2-3-2002')),
      );
    });

    test('writes the DACL, owner Administrators, and the contents', () {
      final data = _Data.create();
      final backend = RecordingBackend(p.join(data.root, 'instances', 'one'));
      final fs = ConfinedFs.withBackend(backend.root, backend);
      final acls = HostInstanceAcls(
        FakeAccountSids({'yagura-srv': server, 'yagura-steam': steam}),
        fs: (_) => fs,
      );

      final reached = acls.apply(backend.root);

      expect(reached, currentAclLayout);
      final root = backend.writeFor('');
      expect(root.ownerSid, 'S-1-5-32-544');
      expect(root.inherit, isFalse);
      final inherited = backend.writeFor('save.dat');
      expect(inherited.inherit, isTrue);
      expect(inherited.sddl, contains('(A;ID;0x1301bf;;;$server)'));
      expect(inherited.sddl, contains('(A;ID;0x1301bf;;;$steam)'));
    });

    test('reaches no layout while an account is missing', () {
      final data = _Data.create();
      final backend = RecordingBackend(p.join(data.root, 'instances', 'one'));
      final acls = HostInstanceAcls(
        FakeAccountSids({'yagura-srv': server}),
        fs: (_) => ConfinedFs.withBackend(backend.root, backend),
      );

      expect(acls.apply(backend.root), 0);
    });

    test('stops at a link and writes nothing below it', () {
      final data = _Data.create();
      final backend = RecordingBackend(p.join(data.root, 'instances', 'one'))
        ..links.add('save.dat');
      final acls = HostInstanceAcls(
        FakeAccountSids({'yagura-srv': server, 'yagura-steam': steam}),
        fs: (_) => ConfinedFs.withBackend(backend.root, backend),
      );

      expect(
        () => acls.apply(backend.root),
        throwsA(isA<AclLinkFound>().having((e) => e.path, 'path', 'save.dat')),
      );
    });
  });
}
