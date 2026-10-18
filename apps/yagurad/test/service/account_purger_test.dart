import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/service/account_purger.dart';

import '../support/service_support.dart';

/// Accounts in memory: a SID per name, and a profile error per SID.
class _FakeAccounts implements AccountOperations {
  _FakeAccounts(this.sids);

  final Map<String, String> sids;
  final profileErrors = <String, int>{};
  final deleted = <String>[];
  final profilesDeleted = <String>[];
  final accountErrors = <String, int>{};

  @override
  String? sidOf(String account) => sids[account];

  @override
  int deleteProfile(String sid) {
    profilesDeleted.add(sid);
    return profileErrors[sid] ?? 0;
  }

  @override
  int deleteAccount(String account) {
    if (accountErrors[account] case final error?) return error;
    deleted.add(account);
    sids.remove(account);
    return 0;
  }
}

/// A data directory whose database holds the secret rows of the accounts and
/// of an instance.
Directory _dataDirectory() {
  final dir = Directory.systemTemp.createTempSync('yagurad_purge_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final db = YaguraDatabase.open(p.join(dir.path, 'yagura.db'));
  try {
    db.sqlite.execute(
      "INSERT INTO instances (id, name, plugin_id, plugin_version, directory, "
      "state, settings_json, created_at, state_changed_at) VALUES "
      "('i1', 'Friends', 'valheim', '1', 'd', 'stopped', '{}', 1, 1)",
    );
    for (final id in [
      serviceAccountSecretId('yagura-srv'),
      serviceAccountSecretId('yagura-steam'),
      'daemon-ca',
    ]) {
      db.sqlite.execute(
        "INSERT INTO secrets (id, setting, blob, scope_sid, created_at) "
        "VALUES (?, '', x'00', 'S-1-5-18', 1)",
        [id],
      );
    }
  } finally {
    db.close();
  }
  return dir;
}

List<String> _secretIds(Directory data) {
  final db = YaguraDatabase.open(p.join(data.path, 'yagura.db'));
  try {
    return [
      for (final row in db.sqlite.select('SELECT id FROM secrets ORDER BY id'))
        row['id']! as String,
    ];
  } finally {
    db.close();
  }
}

void main() {
  group('the account purge', () {
    test('deletes_profiles_accounts_and_secret_rows', () async {
      final data = _dataDirectory();
      final accounts = _FakeAccounts({
        'yagura-srv': 'S-1-5-21-1',
        'yagura-steam': 'S-1-5-21-2',
      });

      final outcomes = await HostAccountPurger(
        dataDirectory: () => data.path,
        operations: accounts,
      ).purge();

      expect(outcomes.map((o) => (o.account, o.removed)), [
        ('yagura-srv', true),
        ('yagura-steam', true),
      ]);
      expect(accounts.profilesDeleted, ['S-1-5-21-1', 'S-1-5-21-2']);
      expect(accounts.deleted, ['yagura-srv', 'yagura-steam']);
      // Only the two password rows go; the rest of the database stays.
      expect(_secretIds(data), ['daemon-ca']);
    });

    test('an_account_that_never_existed_is_removed_already', () async {
      final data = _dataDirectory();

      final outcomes = await HostAccountPurger(
        dataDirectory: () => data.path,
        operations: _FakeAccounts({}),
      ).purge();

      expect(outcomes.every((o) => o.removed), isTrue);
      expect(_secretIds(data), ['daemon-ca']);
    });

    test('an_account_without_a_profile_is_still_deleted', () async {
      final data = _dataDirectory();
      final accounts = _FakeAccounts({'yagura-srv': 'S-1-5-21-1'})
        ..profileErrors['S-1-5-21-1'] = 2;

      final outcomes = await HostAccountPurger(
        dataDirectory: () => data.path,
        operations: accounts,
      ).purge();

      expect(outcomes.first.removed, isTrue);
      expect(accounts.deleted, ['yagura-srv']);
    });

    test('a_profile_in_use_keeps_the_account_and_its_secret_row', () async {
      final data = _dataDirectory();
      final accounts = _FakeAccounts({
        'yagura-srv': 'S-1-5-21-1',
        'yagura-steam': 'S-1-5-21-2',
      })..profileErrors['S-1-5-21-2'] = 32;

      final outcomes = await HostAccountPurger(
        dataDirectory: () => data.path,
        operations: accounts,
      ).purge();

      final kept = outcomes.singleWhere((o) => !o.removed);
      expect(kept.account, 'yagura-steam');
      expect(kept.reason, contains('profile is still in use'));
      expect(kept.reason, contains('32'));
      expect(accounts.deleted, ['yagura-srv'], reason: 'kept, not deleted');
      expect(_secretIds(data), [
        'daemon-ca',
        serviceAccountSecretId('yagura-steam'),
      ]);

      // A later purge finishes the job.
      accounts.profileErrors.clear();
      final later = await HostAccountPurger(
        dataDirectory: () => data.path,
        operations: accounts,
      ).purge();
      expect(later.every((o) => o.removed), isTrue);
      expect(_secretIds(data), ['daemon-ca']);
    });

    test('a_failed_account_deletion_is_reported_and_kept', () async {
      final data = _dataDirectory();
      final accounts = _FakeAccounts({'yagura-srv': 'S-1-5-21-1'})
        ..accountErrors['yagura-srv'] = 5;

      final outcomes = await HostAccountPurger(
        dataDirectory: () => data.path,
        operations: accounts,
      ).purge();

      expect(outcomes.first.removed, isFalse);
      expect(outcomes.first.reason, contains('5'));
      expect(_secretIds(data), contains(serviceAccountSecretId('yagura-srv')));
    });

    test('no_database_is_no_rows_to_delete', () async {
      final empty = Directory.systemTemp.createTempSync('yagurad_purge_');
      addTearDown(() => empty.deleteSync(recursive: true));

      final outcomes = await HostAccountPurger(
        dataDirectory: () => empty.path,
        operations: _FakeAccounts({}),
      ).purge();

      expect(outcomes.every((o) => o.removed), isTrue);
    });
  });

  group('the running-server probe', () {
    test('asks_the_daemon_first', () async {
      final names = await HostServerProbe(
        status: () async => {
          'running_servers': ['Friends', 'Raid night'],
        },
        dataDirectory: () => throw StateError('the database is not needed'),
      ).runningServers();

      expect(names, ['Friends', 'Raid night']);
    });

    test('a_daemon_without_servers_reports_none', () async {
      final names = await HostServerProbe(
        status: () async => {'running_servers': <String>[]},
        dataDirectory: () => throw StateError('the database is not needed'),
      ).runningServers();

      expect(names, isEmpty);
    });

    test('another_reason_is_not_swallowed', () async {
      final probe = HostServerProbe(
        status: () async =>
            throw YaguraException('admin_channel_untrusted', 'squatter'),
        dataDirectory: () => '',
      );

      await expectLater(
        probe.runningServers(),
        throwsA(
          isA<YaguraException>().having(
            (e) => e.reason,
            'reason',
            'admin_channel_untrusted',
          ),
        ),
      );
    });

    test(
      'with_the_daemon_down_it_reads_the_runs_and_checks_the_process',
      () async {
        final data = _dataDirectory();
        final db = YaguraDatabase.open(p.join(data.path, 'yagura.db'));
        try {
          for (final (id, state, pid) in [
            ('a', 'running', 100),
            ('b', 'running', 200),
            ('c', 'ended', 300),
          ]) {
            db.sqlite.execute(
              'INSERT INTO runs (run_id, instance_id, directory, state, '
              'server_pid, created_at) VALUES (?, ?, ?, ?, ?, 1)',
              [id, 'i1', 'd', state, pid],
            );
          }
        } finally {
          db.close();
        }

        final names = await HostServerProbe(
          status: () async =>
              throw YaguraException('daemon_not_running', 'nothing serves'),
          dataDirectory: () => data.path,
          // Only PID 200 is alive.
          isRunning: (pid) => pid == 200,
        ).runningServers();

        expect(names, ['Friends']);
      },
    );

    test('without_a_database_no_server_runs', () async {
      final empty = Directory.systemTemp.createTempSync('yagurad_purge_');
      addTearDown(() => empty.deleteSync(recursive: true));

      final names = await HostServerProbe(
        status: () async =>
            throw YaguraException('daemon_not_running', 'nothing serves'),
        dataDirectory: () => empty.path,
      ).runningServers();

      expect(names, isEmpty);
    });
  });

  test('the_fake_installer_probe_and_purger_are_the_same_interfaces', () {
    // Keeps the support fakes honest against the real interfaces.
    expect(FakeServers(), isA<ServerProbe>());
    expect(FakePurger(), isA<AccountPurger>());
  });
}
