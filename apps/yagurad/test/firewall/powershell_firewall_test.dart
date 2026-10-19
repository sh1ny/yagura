@Tags(['windows'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/firewall/firewall_backend.dart';
import 'package:yagurad/src/firewall/firewall_script.dart';
import 'package:yagurad/src/firewall/powershell_firewall.dart';

// How the backend runs PowerShell and reads its answer, with a harmless
// command in place of the script. The script itself is in
// firewall_script_test.dart; the real firewall is the `elevated` rows.

const _timeout = Duration(seconds: 20);

/// Where the stubs' request files go; every test ends with it empty.
final requests = Directory(
  p.join(Directory.systemTemp.path, 'yagurad_ps_test_$pid'),
);

/// A backend whose PowerShell runs [command] instead of the script.
PowerShellFirewall stub(String command) => PowerShellFirewall(
  directory: requests.path,
  arguments: (_) => ['-NoProfile', '-NonInteractive', '-Command', command],
);

/// A command that prints [json] and ends.
String say(String json) => "[Console]::Out.Write('$json')";

void main() {
  tearDownAll(() {
    if (requests.existsSync()) requests.deleteSync(recursive: true);
  });

  tearDown(() {
    // No request file outlives its run, whatever the run did.
    if (requests.existsSync()) expect(requests.listSync(), isEmpty);
  });

  test('the_request_is_a_file_and_stdin_is_not_used', () async {
    final backend = stub(
      r'''$r = [System.IO.File]::ReadAllText($env:YAGURA_FIREWALL_REQUEST) | ConvertFrom-Json; '''
      r'''[Console]::Out.Write('{"changes":[{"name":"' + $r.mode + '/' + $r.group + '","action":"created"}],"unmanaged":[]}')''',
    );

    final outcome = await backend.reconcile(const [], timeout: _timeout);

    expect(outcome.changes.single.name, 'reconcile/Yagura');
  });

  test('a_request_directory_that_cannot_be_made_is_unavailable', () async {
    final blocker = File(
      p.join(Directory.systemTemp.path, 'yagurad_ps_file_$pid'),
    )..writeAsStringSync('');
    addTearDown(blocker.deleteSync);
    final backend = PowerShellFirewall(
      directory: p.join(blocker.path, 'inside'),
      arguments: (_) => ['-NoProfile', '-Command', 'exit 0'],
    );

    await expectLater(
      backend.list(timeout: _timeout),
      throwsA(
        isA<FirewallUnavailable>().having(
          (e) => e.message,
          'message',
          contains('cannot be written'),
        ),
      ),
    );
  });

  test('stale_requests_are_swept_and_a_folder_of_ours_goes', () async {
    requests.createSync(recursive: true);
    final stale = File(p.join(requests.path, 'request-old.json'))
      ..writeAsStringSync('{}');
    stale.setLastModifiedSync(
      DateTime.now().subtract(const Duration(hours: 1)),
    );
    final other = File(p.join(requests.path, 'notes.txt'))
      ..writeAsStringSync('');
    final backend = stub(say('{"rules":[]}'));

    await backend.list(timeout: _timeout);

    expect(stale.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
    other.deleteSync();

    final own = Directory(
      p.join(Directory.systemTemp.path, 'yagurad_ps_own_$pid'),
    );
    addTearDown(() {
      if (own.existsSync()) own.deleteSync(recursive: true);
    });
    await PowerShellFirewall(
      directory: own.path,
      removeDirectory: true,
      arguments: (_) => ['-NoProfile', '-Command', say('{"rules":[]}')],
    ).list(timeout: _timeout);
    expect(own.existsSync(), isFalse);
  });

  test('reads_the_changes_and_the_unmanaged_names', () async {
    final backend = stub(
      say(
        '{"changes":[{"name":"a","action":"created","error":""},'
        '{"name":"b","action":"failed","error":"denied"}],'
        '"unmanaged":["x","y"]}',
      ),
    );

    final outcome = await backend.reconcile(const [], timeout: _timeout);

    expect(outcome.changes.map((c) => '$c'), [
      'created a',
      'failed b (denied)',
    ]);
    expect(outcome.unmanaged, ['x', 'y']);
  });

  test('a_single_name_is_read_as_a_list', () async {
    final backend = stub(
      say(
        '{"changes":{"name":"a","action":"deleted","error":""},'
        '"unmanaged":"x"}',
      ),
    );

    final outcome = await backend.reconcile(const [], timeout: _timeout);

    expect(outcome.changes.single.action, 'deleted');
    expect(outcome.unmanaged, ['x']);
  });

  test('lists_the_rules', () async {
    final backend = stub(
      say(
        '{"rules":[{"name":"a","protocol":"udp","port":"2456","owned":true}]}',
      ),
    );

    final rules = await backend.list(timeout: _timeout);

    expect(rules.single.name, 'a');
    expect(rules.single.port, '2456');
  });

  test('an_error_answer_is_unavailable', () async {
    final backend = stub(
      say('{"error":"the Windows Firewall service (mpssvc) is not running"}'),
    );

    await expectLater(
      backend.list(timeout: _timeout),
      throwsA(
        isA<FirewallUnavailable>().having(
          (e) => e.message,
          'message',
          contains('mpssvc'),
        ),
      ),
    );
  });

  test('no_answer_is_unavailable_and_names_the_exit_code', () async {
    final backend = stub("[Console]::Error.WriteLine('it broke'); exit 5");

    await expectLater(
      backend.list(timeout: _timeout),
      throwsA(
        isA<FirewallUnavailable>().having(
          (e) => e.message,
          'message',
          allOf(contains('code 5'), contains('it broke')),
        ),
      ),
    );
  });

  test('a_run_past_its_timeout_is_ended_and_unavailable', () async {
    final backend = stub('Start-Sleep -Seconds 60');
    final watch = Stopwatch()..start();

    await expectLater(
      backend.list(timeout: const Duration(seconds: 2)),
      throwsA(
        isA<FirewallUnavailable>().having(
          (e) => e.message,
          'message',
          contains('did not answer'),
        ),
      ),
    );

    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('a_timeout_says_where_the_script_was', () async {
    final backend = stub(
      "[Console]::Error.WriteLine('yagura-firewall: get_rules done at 800 ms'); "
      "[Console]::Error.WriteLine('yagura-firewall: get_filters done at 900 ms'); "
      'Start-Sleep -Seconds 60',
    );

    await expectLater(
      backend.list(timeout: const Duration(seconds: 3)),
      throwsA(
        isA<FirewallUnavailable>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('last progress:'),
            contains('get_rules done at 800 ms'),
            contains('get_filters done at 900 ms'),
          ),
        ),
      ),
    );
  });

  test('a_timeout_without_progress_says_so', () async {
    await expectLater(
      stub('Start-Sleep -Seconds 60').list(timeout: const Duration(seconds: 2)),
      throwsA(
        isA<FirewallUnavailable>().having(
          (e) => e.message,
          'message',
          contains('wrote no progress'),
        ),
      ),
    );
  });

  test('the_scripts_own_timings_are_passed_on', () async {
    final backend = stub(
      say(
        '{"changes":[],"unmanaged":[],"fallbacks":0,"joinedByName":0,'
        '"timings":{"join":12}}',
      ),
    );

    final outcome = await backend.reconcile(const [], timeout: _timeout);

    expect(outcome.diagnostics, {
      'fallbacks': 0,
      'joinedByName': 0,
      'timings': {'join': 12},
    });
  });

  test('a_missing_powershell_is_unavailable', () async {
    final backend = PowerShellFirewall(
      directory: requests.path,
      executable: p.join(Directory.systemTemp.path, 'no', 'powershell.exe'),
    );

    await expectLater(
      backend.remove(const ['a'], timeout: _timeout),
      throwsA(isA<FirewallUnavailable>()),
    );
  });

  test('the_encoded_script_fits_the_command_line', () {
    // CreateProcess takes 32,767 characters; -EncodedCommand is UTF-16 in
    // base64, 8/3 of the script's bytes. Past 24,000 the script must move to
    // a file.
    final encoded = (firewallScript.length * 2 * 4 / 3).ceil();
    expect(encoded, lessThan(24000));
  });
}
