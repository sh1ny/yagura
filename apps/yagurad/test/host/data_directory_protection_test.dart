import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/data_dir_lock.dart';
import 'package:yagurad/src/platform/win32_lock_file.dart';
import 'package:yagurad/src/host/acl_layout.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/platform/acl_writer.dart';

import '../support/acl_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';

// Design D6 and D7 as the daemon runs them. The protector, the accounts and
// the instance ACLs are fakes here (they need administrator rights); the
// `elevated` rows run the real ones.

YaguraException _notProtected(String path) => YaguraException(
  'data_dir_not_protected',
  'the data directory cannot be protected: $path',
  details: {'path': path},
);

Future<Daemon> _startService(
  TestEnv env, {
  FakeDataDirProtector? protector,
  FakeServiceAccounts? accounts,
  FakeInstanceAcls? acls,
}) => env.start(
  serviceMode: true,
  secretProtector: FakeSecretProtector(serviceSid),
  dataDirProtector: protector,
  serviceAccounts: accounts,
  instanceAcls: acls,
  accountSids: _sids(accounts),
);

AccountSidsView _sids(FakeServiceAccounts? accounts) =>
    AccountSidsView(accounts);

class AccountSidsView implements AccountSids {
  AccountSidsView(this._accounts);

  final FakeServiceAccounts? _accounts;

  @override
  String? sidOf(String account) => _accounts?.sidOf(account);
}

int _layoutOf(TestEnv env, String id) {
  // Read while the daemon has the database open: SQLite allows it.
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    return db.sqlite.select('SELECT acl_layout FROM instances WHERE id = ?', [
          id,
        ]).single['acl_layout']!
        as int;
  } finally {
    db.close();
  }
}

void main() {
  group('the data directory protection', () {
    test(
      'runs in order around the lock and before the database opens',
      () async {
        final env = TestEnv();
        final protector = FakeDataDirProtector();
        final accounts = FakeServiceAccounts();

        await _startService(env, protector: protector, accounts: accounts);

        expect(protector.events, [
          'open',
          'protect',
          'close',
          // Before the database: the accounts do not exist yet.
          'walk:-:-:false',
          // After the accounts were set up.
          'walk:S-1-5-21-1-2-3-2001:S-1-5-21-1-2-3-2002:true',
        ]);
        expect(accounts.ensured, 1);
      },
    );

    test('is not run by a development daemon', () async {
      final env = TestEnv();
      final protector = FakeDataDirProtector();

      await env.start(dataDirProtector: protector);

      expect(protector.events, isEmpty);
    });

    // data_directory_is_a_link (unit analogue)
    test('a data directory that is a link stops the start', () async {
      final env = TestEnv();
      final protector = FakeDataDirProtector()
        ..failOpen = _notProtected(env.data);

      await expectLater(
        _startService(env, protector: protector),
        failsWith(
          'data_dir_not_protected',
          messageHas: [env.data],
          details: {'step': 'data_directory_protection'},
        ),
      );

      // Nothing was created: not the directory, not the database.
      expect(protector.existedAtOpen, isFalse);
      expect(Directory(env.data).existsSync(), isFalse);
    });

    // link_in_the_data_directory_at_first_service_start (unit analogue)
    test(
      'a link found by the walk stops the start before the database',
      () async {
        final env = TestEnv();
        final junction = p.join(env.data, 'snapshots');
        final protector = FakeDataDirProtector()
          ..failWalk = _notProtected(junction);

        await expectLater(
          _startService(env, protector: protector),
          failsWith(
            'data_dir_not_protected',
            messageHas: [junction],
            details: {'step': 'data_directory_protection'},
          ),
        );

        expect(File(p.join(env.data, 'yagura.db')).existsSync(), isFalse);
        // The lock was released: the next start gets as far as the walk again.
        protector.failWalk = null;
        await _startService(env, protector: protector);
      },
    );

    // The lock file is opened before the DACL is set, so a Users process could
    // plant a link there: the service must neither follow it nor write to it.
    test('a link in place of the lock file stops the service start', () async {
      final env = TestEnv();
      final data = Directory(env.data)..createSync(recursive: true);
      final target = File(p.join(env.root.path, 'victim.txt'))
        ..writeAsStringSync('precious');
      try {
        Link(p.join(data.path, 'yagurad.lock')).createSync(target.path);
      } on FileSystemException {
        markTestSkipped('this host cannot create symbolic links');
        return;
      }

      await expectLater(
        _startService(env, protector: FakeDataDirProtector()),
        failsWith('data_dir_not_protected', messageHas: ['yagurad.lock']),
      );

      expect(target.readAsStringSync(), 'precious');
    }, skip: Platform.isWindows ? false : 'the Windows lock file');

    test('a lock file with several names stops the service start', () async {
      final env = TestEnv();
      final data = Directory(env.data)..createSync(recursive: true);
      final other = File(p.join(env.root.path, 'other.txt'))
        ..writeAsStringSync('precious');
      final made = await Process.run('cmd', [
        '/c',
        'mklink',
        '/H',
        p.join(data.path, 'yagurad.lock'),
        other.path,
      ]);
      expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');

      await expectLater(
        _startService(env, protector: FakeDataDirProtector()),
        failsWith('data_dir_not_protected', messageHas: ['hard links']),
      );

      expect(other.readAsStringSync(), 'precious');
    }, skip: Platform.isWindows ? false : 'hard link by cmd needs Windows');

    // A lock file that cannot be opened is not a protection failure: the
    // directory is unusable (host-service, "Data directory not writable").
    test(
      'a lock file that cannot be opened fails data_dir_unwritable',
      () async {
        final env = TestEnv();
        // A directory in place of the file: CreateFileW fails with an error.
        Directory(p.join(env.data, 'yagurad.lock')).createSync(recursive: true);

        await expectLater(
          _startService(env, protector: FakeDataDirProtector()),
          failsWith(
            'data_dir_unwritable',
            messageHas: ['yagurad.lock', 'CreateFileW failed with error'],
            details: {'step': 'data_directory_lock'},
          ),
        );
      },
      skip: Platform.isWindows ? false : 'the Windows lock file',
    );

    test('a lock file call that fails names the file and the error', () {
      final error = DataDirLock.lockFileUnusable(
        r'C:\data\yagurad.lock',
        const LockFileFailed('WriteFile', 112),
      );

      expect(error.reason, 'data_dir_unwritable');
      expect(error.message, contains('WriteFile failed with error 112'));
      expect(error.message, contains('yagurad.lock'));
      expect(error.details['error'], 112);
    });

    // host-service, "Data directory not writable": the probe runs in service
    // mode too, once the directory is protected.
    test('an unwritable data directory fails data_dir_unwritable', () async {
      final env = TestEnv();
      // A directory where the probe file goes: writing it fails.
      Directory(p.join(env.data, '.write-test')).createSync(recursive: true);
      final protector = FakeDataDirProtector();

      await expectLater(
        _startService(env, protector: protector),
        failsWith('data_dir_unwritable', messageHas: [env.data]),
      );

      // After the protection, not before it.
      expect(protector.events, containsAllInOrder(['open', 'protect']));
    });

    test('a failed owner or DACL write stops the start', () async {
      final env = TestEnv();
      final protector = FakeDataDirProtector()
        ..failProtect = _notProtected(env.data);

      await expectLater(
        _startService(env, protector: protector),
        failsWith('data_dir_not_protected'),
      );

      expect(File(p.join(env.data, 'yagura.db')).existsSync(), isFalse);
      expect(protector.events, contains('close'));
    });
  });

  group('the service accounts', () {
    test('are set up at every start and reported', () async {
      final env = TestEnv();
      final accounts = FakeServiceAccounts();

      final daemon = await _startService(env, accounts: accounts);

      expect(daemon.serviceAccountsManaged, isTrue);
      expect(daemon.serviceAccountsOk, isTrue);
      await env.closeDaemons();
      await _startService(env, accounts: accounts);
      expect(accounts.ensured, 2);
    });

    test('a failure is a notice, not a reason to stop', () async {
      final env = TestEnv();
      final accounts = FakeServiceAccounts(fails: true);
      final protector = FakeDataDirProtector();

      final daemon = await _startService(
        env,
        accounts: accounts,
        protector: protector,
      );

      expect(daemon.serviceAccountsOk, isFalse);
      expect(
        daemon.startupNotices.map((n) => n.step),
        contains('service_accounts'),
      );
      // The walk ran again, without recording the layout.
      expect(protector.events.last, endsWith(':false'));
    });

    test('are not managed by a development daemon', () async {
      final env = TestEnv();
      final daemon = await env.start();

      expect(daemon.serviceAccountsManaged, isFalse);
      expect(daemon.serviceAccountsOk, isFalse);
    });
  });

  group('the instance ACLs', () {
    test('an instance created in service mode gets its DACL', () async {
      final env = TestEnv()..installValheim();
      final acls = FakeInstanceAcls();
      final daemon = await _startService(
        env,
        acls: acls,
        accounts: FakeServiceAccounts(),
      );

      final created = await createValheim(daemon);

      expect(acls.applied, [created.directory]);
      expect(_layoutOf(env, created.id), currentAclLayout);
    });

    // instance_created_before_the_service (unit analogue)
    test('an older instance is migrated once', () async {
      final env = TestEnv()..installValheim();
      final dev = await env.start();
      final older = await createValheim(dev);
      await env.closeDaemons();
      final acls = FakeInstanceAcls();

      await _startService(env, acls: acls, accounts: FakeServiceAccounts());
      expect(acls.applied, [older.directory]);
      expect(_layoutOf(env, older.id), currentAclLayout);
      await env.closeDaemons();

      await _startService(env, acls: acls, accounts: FakeServiceAccounts());
      expect(acls.applied, [older.directory], reason: 'once');
    });

    test('a file with several names is named as such in the warning', () async {
      final env = TestEnv()..installValheim();
      final dev = await env.start();
      final older = await createValheim(dev);
      await env.closeDaemons();
      final acls = FakeInstanceAcls()
        ..failing[older.directory] = const AclLinkFound(
          'Saved/world.db',
          hardLinks: true,
        );

      final daemon = await _startService(
        env,
        acls: acls,
        accounts: FakeServiceAccounts(),
      );

      expect(
        daemon.instances.get(older.id).warning,
        allOf(contains('several names'), contains('fsutil hardlink list')),
      );
    });

    test('a link leaves the layout unchanged and raises a warning', () async {
      final env = TestEnv()..installValheim();
      final dev = await env.start();
      final older = await createValheim(dev);
      await env.closeDaemons();
      final acls = FakeInstanceAcls()
        ..failing[older.directory] = const AclLinkFound('Saved/link');

      final daemon = await _startService(
        env,
        acls: acls,
        accounts: FakeServiceAccounts(),
      );

      final warned = daemon.instances.get(older.id);
      expect(
        warned.warning,
        allOf(
          contains('link'),
          contains(p.join(older.directory, 'Saved', 'link')),
        ),
      );
      expect(
        daemon.instances.recoveryNotices.map((n) => n.kind),
        contains('acl_migration_failed'),
      );
      expect(
        daemon.startupNotices.map((n) => n.step),
        contains('acl_migration_failed'),
      );
      expect(_layoutOf(env, older.id), 0, reason: 'unchanged');
      // Next start, with the link removed, migrates it.
      await env.closeDaemons();
      acls.failing.clear();
      await _startService(env, acls: acls, accounts: FakeServiceAccounts());
      expect(acls.applied, hasLength(2));
      expect(_layoutOf(env, older.id), currentAclLayout);
    });

    test('launches of an instance that could not be migrated are refused, '
        'and work once the link is gone', () async {
      // Design D6 and the failure table: "that instance's launches fail until
      // the link is removed". The tree is half migrated, so a server started
      // on it could fail on files it cannot reach or run with entries every
      // local user can read.
      final env = TestEnv()..installValheim();
      final dev = await env.start();
      final older = await createInstalled(dev);
      await env.closeDaemons();
      final acls = FakeInstanceAcls()
        ..failing[older.directory] = const AclLinkFound('Saved/link');
      final daemon = await _startService(
        env,
        acls: acls,
        accounts: FakeServiceAccounts(),
      );

      final refused = await runStart(daemon, older.id);

      expect(refused.status, OperationStatus.failed);
      expect(refused.resultReason, 'acl_migration_failed');
      expect(refused.resultMessage, contains('link'));
      expect(daemon.instances.get(older.id).state, InstanceState.stopped);

      // The admin removes the link: the next Start migrates and launches,
      // without a service restart.
      acls.failing.clear();
      final started = await runStart(daemon, older.id);

      expect(started.resultReason, isEmpty, reason: started.resultMessage);
      expect(daemon.instances.get(older.id).state, InstanceState.running);
      expect(_layoutOf(env, older.id), currentAclLayout);
    });
  });
}
