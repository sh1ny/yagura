import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/acl_layout.dart';
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
  });
}
