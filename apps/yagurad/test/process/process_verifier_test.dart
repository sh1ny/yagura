import 'package:test/test.dart';
import 'package:yagurad/src/process/process_verifier.dart';

import '../support/acl_support.dart';

// Design D9: the run files are written by the game-server account, so before
// the daemon signals, ends or re-attaches a process it checks the token user,
// the parentage and the start order. The process table is a fake; the
// `windows` rows in integration_test/process run the real one.

const account = 'S-1-5-21-1-2-3-2001';
const other = 'S-1-5-18';

ProcessVerifier _verifier(FakeProcessTable table, [String? sid = account]) =>
    ProcessVerifier(table: table, accountSid: () => sid);

/// A relay (100) and its server (200), both running as the account.
FakeProcessTable _genuine() => FakeProcessTable()
  ..add(
    100,
    user: account,
    parent: 1,
    created: 10,
    executable: r'C:\y\yagurad.exe',
  )
  ..add(200, user: account, parent: 100, created: 20);

void main() {
  test('a server that is the relay\'s child as the account is verified', () {
    final table = _genuine();

    final result = _verifier(table)
        .verify(table.processes[200]!.identity, table.processes[100]!.identity);

    expect(result, isA<ServerVerified>());
  });

  test('a recorded process of another user is not verified', () {
    final table = _genuine()..add(300, user: other, parent: 100, created: 30);

    final result = _verifier(table)
        .verify(table.processes[300]!.identity, table.processes[100]!.identity);

    // The relay's own child running as the account is found instead.
    expect(result, isA<ServerFoundByFallback>());
    expect((result as ServerFoundByFallback).server.pid, 200);
  });

  test('a recorded process that is not the relay\'s child is not verified', () {
    final table = _genuine()..add(300, user: account, parent: 1, created: 30);

    final result = _verifier(table)
        .verify(table.processes[300]!.identity, table.processes[100]!.identity);

    expect(result, isA<ServerFoundByFallback>());
    expect((result as ServerFoundByFallback).server.pid, 200);
  });

  test('a recorded process created before the relay is not verified', () {
    final table = FakeProcessTable()
      ..add(100, user: account, parent: 1, created: 50)
      ..add(300, user: account, parent: 100, created: 40);

    final result = _verifier(table)
        .verify(table.processes[300]!.identity, table.processes[100]!.identity);

    expect(result, isA<RecordRejected>());
  });

  test('nothing is verified when the relay has no child either', () {
    final table = FakeProcessTable()
      ..add(100, user: account, parent: 1, created: 10)
      ..add(300, user: other, parent: 1, created: 30);

    final result = _verifier(table)
        .verify(table.processes[300]!.identity, table.processes[100]!.identity);

    expect(result, isA<RecordRejected>());
    expect((result as RecordRejected).relay!.pid, 100);
  });

  test('a relay of another user is not trusted for the fallback', () {
    final table = FakeProcessTable()
      ..add(100, user: other, parent: 1, created: 10)
      ..add(200, user: account, parent: 100, created: 20)
      ..add(300, user: account, parent: 1, created: 30);

    final result = _verifier(table)
        .verify(table.processes[300]!.identity, table.processes[100]!.identity);

    expect(result, isA<RecordRejected>());
  });

  test('a recorded server that is gone is gone', () {
    final table = _genuine();
    final gone = table.processes[200]!.identity;
    table.processes.remove(200);

    final result = _verifier(table)
        .verify(gone, table.processes[100]!.identity);

    expect(result, isA<ServerGone>());
  });

  test('a reused PID is not the recorded process', () {
    final table = _genuine();
    final recorded = table.processes[200]!.identity;
    table.add(200, user: account, parent: 100, created: 99);

    final result = _verifier(table)
        .verify(recorded, table.processes[100]!.identity);

    expect(result, isA<ServerGone>());
  });

  test('without the account nothing runs as it and nothing verifies', () {
    final table = _genuine();
    final verifier = _verifier(table, null);

    expect(verifier.runsAsAccount(200), isFalse);
    expect(
      verifier.verify(
        table.processes[200]!.identity,
        table.processes[100]!.identity,
      ),
      isA<RecordRejected>(),
    );
  });

  test('a console host is never taken for the server', () {
    final table = FakeProcessTable()
      ..add(100, user: account, parent: 1, created: 10)
      ..add(
        150,
        user: account,
        parent: 100,
        created: 15,
        executable: r'C:\Windows\System32\conhost.exe',
      )
      ..add(300, user: other, parent: 1, created: 30);

    final result = _verifier(table)
        .verify(table.processes[300]!.identity, table.processes[100]!.identity);

    expect(result, isA<RecordRejected>());
  });

  test('isOurs needs the identity and the account', () {
    final table = _genuine()..add(300, user: other, parent: 1, created: 30);
    final verifier = _verifier(table);

    expect(verifier.isOurs(table.processes[200]!.identity), isTrue);
    expect(verifier.isOurs(table.processes[300]!.identity), isFalse);
  });

  test('the user is compared without regard to case', () {
    final table = FakeProcessTable()
      ..add(100, user: account.toUpperCase(), parent: 1, created: 10);

    expect(_verifier(table).runsAsAccount(100), isTrue);
  });

  // A launcher the daemon killed on its timeout may have started the relay;
  // the OS says which process that is, relay.json does not.
  group('the relay of a killed launcher', () {
    const yagurad = r'C:\y\yagurad.exe';
    FakeProcessTable launcherAnd(int relayParent, {String? user}) =>
        FakeProcessTable()
          ..add(50, user: other, parent: 1, created: 5, executable: yagurad)
          ..add(
            100,
            user: user ?? account,
            parent: relayParent,
            created: 10,
            executable: yagurad,
          );

    test('is its child running as the account from the same executable', () {
      final table = launcherAnd(50);

      final relay = _verifier(table)
          .relayStartedBy(table.processes[50]!.identity, executable: yagurad);

      expect(relay?.pid, 100);
    });

    test('is not a process of another parent, user or executable', () {
      final stranger = launcherAnd(1);
      final wrongUser = launcherAnd(50, user: other);
      final wrongImage = launcherAnd(50);

      expect(
        _verifier(
          stranger,
        ).relayStartedBy(stranger.processes[50]!.identity, executable: yagurad),
        isNull,
      );
      expect(
        _verifier(wrongUser).relayStartedBy(
          wrongUser.processes[50]!.identity,
          executable: yagurad,
        ),
        isNull,
      );
      expect(
        _verifier(wrongImage).relayStartedBy(
          wrongImage.processes[50]!.identity,
          executable: r'C:\y\other.exe',
        ),
        isNull,
      );
    });

    test('is not a process created before the launcher', () {
      // A reused launcher PID: the "child" is older than the launcher.
      final table = FakeProcessTable()
        ..add(50, user: other, parent: 1, created: 50, executable: yagurad)
        ..add(100, user: account, parent: 50, created: 10, executable: yagurad);

      expect(
        _verifier(table)
            .relayStartedBy(table.processes[50]!.identity, executable: yagurad),
        isNull,
      );
    });
  });
}
