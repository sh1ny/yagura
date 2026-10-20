@Tags(['windows'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/firewall/firewall_backend.dart';
import 'package:yagurad/src/firewall/firewall_script.dart';
import 'package:yagurad/src/firewall/rule_names.dart';
import 'package:yagurad/src/firewall/powershell_firewall.dart';

import '../support/temp_support.dart';

// The reconcile script of design D11 against stand-ins for the firewall
// cmdlets, in Windows PowerShell. Nothing here reads or writes the firewall of
// the machine: the stand-ins are functions, which PowerShell prefers to the
// cmdlets of the same name, and the harness stops before it runs the script
// unless every one of them resolves to such a function. The same script
// against the real firewall is the `elevated` rows.

const _standIns = r'''
$ErrorActionPreference = 'Stop'
$state = @(ConvertFrom-Json $env:YAGURA_FAKE_STATE | ForEach-Object { $_ })
$log = $env:YAGURA_FAKE_LOG

function Get-Service {
  [CmdletBinding()] param($Name)
  [pscustomobject]@{ Status = $env:YAGURA_FAKE_SERVICE }
}
function Get-NetFirewallRule {
  [CmdletBinding()] param($Group, $Name)
  if ($null -ne $Name) {
    $removed = @(Get-Content -Path $log | Where-Object { $_ -like 'remove *' } | ForEach-Object { $_.Substring(7) -split ' ' })
    if ($removed -contains $Name) { return }
    foreach ($rule in $state) { if ($rule.name -eq $Name) { [pscustomobject]@{ Name = $rule.name; InstanceID = $rule.name } } }
    return
  }
  Add-Content -Path "$log.groups" -Value "group $Group"
  if ($state.Count -eq 0) {
    $record = New-Object System.Management.Automation.ErrorRecord (New-Object System.Exception 'No MSFT_NetFirewallRule objects found'), 'CmdletizationQuery_NotFound_Group', 'ObjectNotFound', $Group
    $PSCmdlet.WriteError($record)
    return
  }
  foreach ($rule in $state) { [pscustomobject]@{ Name = $rule.name; InstanceID = $rule.name } }
}
function Get-NetFirewallPortFilter {
  [CmdletBinding()] param([switch]$All, $AssociatedNetFirewallRule, [Parameter(ValueFromPipeline = $true)]$InputObject)
  begin { $piped = 0 }
  process {
    if ($null -ne $InputObject) {
      $piped++
      $r = $state | Where-Object { $_.name -eq $InputObject.Name }
      [pscustomobject]@{ InstanceID = "filter:$($r.name)"; Protocol = $r.protocol.ToUpperInvariant(); LocalPort = @($r.port) }
    }
  }
  end {
    if ($piped -gt 0) { Add-Content -Path "$log.filters" -Value "filters piped $piped" }
    elseif ($null -ne $AssociatedNetFirewallRule) {
      Add-Content -Path "$log.filters" -Value "filters alone $($AssociatedNetFirewallRule.Name)"
      $r = $state | Where-Object { $_.name -eq $AssociatedNetFirewallRule.Name }
      [pscustomobject]@{ InstanceID = "filter:$($r.name)"; Protocol = $r.protocol.ToUpperInvariant(); LocalPort = @($r.port) }
    }
    elseif ($All) {
      Add-Content -Path "$log.filters" -Value 'filters all'
      foreach ($rule in $state) {
        # Ids of the filters are the rules' (YAGURA_FAKE_FILTER_IDS=other: not).
        $id = if ($env:YAGURA_FAKE_FILTER_IDS -eq 'other') { "filter:$($rule.name)" } else { $rule.name }
        [pscustomobject]@{ InstanceID = $id; Protocol = $rule.protocol.ToUpperInvariant(); LocalPort = @($rule.port) }
      }
    }
  }
}
function New-NetFirewallRule {
  [CmdletBinding()] param($Name, $DisplayName, $Description, $Group, $Direction, $Action, $Protocol, $LocalPort, $Profile, $Enabled)
  if ($env:YAGURA_FAKE_FAIL -and $Name -eq $env:YAGURA_FAKE_FAIL) { throw "Access is denied for $Name" }
  Add-Content -Path $log -Value "new $Name $Protocol $LocalPort $Group $Direction $Action $Profile $Enabled"
}
function Set-NetFirewallRule {
  [CmdletBinding()] param($Name, $Protocol, $LocalPort)
  Add-Content -Path $log -Value "set $Name $Protocol $LocalPort"
}
function Remove-NetFirewallRule {
  [CmdletBinding()] param($Name)
  # A batch with the failing rule in it removes the ones before it, then fails.
  if ($env:YAGURA_FAKE_FAIL_REMOVE) {
    foreach ($one in @($Name)) {
      if ($one -eq $env:YAGURA_FAKE_FAIL_REMOVE) { throw "Access is denied for $one" }
      Add-Content -Path $log -Value "remove $one"
    }
    return
  }
  Add-Content -Path $log -Value "remove $Name"
}

foreach ($cmdlet in @('Get-Service','Get-NetFirewallRule','Get-NetFirewallPortFilter','New-NetFirewallRule','Set-NetFirewallRule','Remove-NetFirewallRule')) {
  if ((Get-Command $cmdlet).CommandType -ne 'Function') {
    [Console]::Error.WriteLine("$cmdlet is not the stand-in")
    [Environment]::Exit(3)
  }
}
''';

/// The stand-ins, then the script from a file.
const _harness =
    '''
$_standIns
. \$env:YAGURA_SCRIPT
''';

const _a = 'Yagura/inst-0123456789ab/game/udp';
const _b = 'Yagura/inst-0123456789ab/query/udp';

class ScriptRun {
  ScriptRun(
    this.answer,
    this.log,
    this.exitCode,
    this.stderr, {
    this.filterCalls = const [],
    this.groups = const [],
  });

  final Map<String, Object?> answer;
  final List<String> log;
  final int exitCode;
  final String stderr;

  /// How the stand-in port filter cmdlet was asked, one entry per call:
  /// all, piped (with a count) or alone (with a rule name).
  final List<String> filterCalls;

  /// The groups the stand-in `Get-NetFirewallRule` was asked for.
  final List<String> groups;

  List<Map<String, Object?>> get changes => [
    for (final c in answer['changes']! as List) c as Map<String, Object?>,
  ];

  Map<String, String> get actions => {
    for (final c in changes) c['name']! as String: c['action']! as String,
  };
}

Map<String, String> rule(String name, String protocol, String port) => {
  'name': name,
  'protocol': protocol,
  'port': port,
};

Future<ScriptRun> runScript(
  Directory dir,
  Map<String, Object?> request, {
  List<Map<String, String>> rules = const [],
  String service = 'Running',
  String? failName,
  String? failRemove,
  bool otherFilterIds = false,
}) async {
  final script = File(p.join(dir.path, 'firewall.ps1'))
    ..writeAsStringSync(firewallScript);
  final harness = File(p.join(dir.path, 'harness.ps1'))
    ..writeAsStringSync(_harness);
  final log = File(p.join(dir.path, 'effects.log'))..writeAsStringSync('');
  final requestFile = File(p.join(dir.path, 'request.json'))
    ..writeAsStringSync(jsonEncode(request));
  final process = await Process.start(
    p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    ),
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      harness.path,
    ],
    environment: {
      'YAGURA_FAKE_STATE': jsonEncode(rules),
      'YAGURA_FAKE_LOG': log.path,
      'YAGURA_FAKE_SERVICE': service,
      'YAGURA_SCRIPT': script.path,
      requestPathVariable: requestFile.path,
      'YAGURA_FAKE_FAIL': ?failName,
      'YAGURA_FAKE_FAIL_REMOVE': ?failRemove,
      if (otherFilterIds) 'YAGURA_FAKE_FILTER_IDS': 'other',
    },
  );
  process.stdin.close().ignore();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode.timeout(const Duration(seconds: 90));
  final text = await out;
  expect(text.codeUnits.every((c) => c < 128), isTrue, reason: 'ASCII only');
  return ScriptRun(
    text.trim().isEmpty
        ? const {}
        : jsonDecode(text.trim()) as Map<String, Object?>,
    log.readAsLinesSync().where((l) => l.isNotEmpty).toList(),
    code,
    await err,
    groups: File('${log.path}.groups').existsSync()
        ? File('${log.path}.groups').readAsLinesSync()
        : const [],
    filterCalls: File('${log.path}.filters').existsSync()
        ? File('${log.path}.filters')
              .readAsLinesSync()
              .where((l) => l.isNotEmpty)
              .toList()
        : const [],
  );
}

void main() {
  late Directory dir;

  setUp(() {
    dir = createCanonicalTempSync('yagurad_firewall_script_');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('the_script_runs_only_against_the_stand_ins', () async {
    final run = await runScript(dir, {'mode': 'list'});

    expect(run.exitCode, 0, reason: run.stderr);
    // Progress lines only: nothing else is written to standard error.
    expect(
      const LineSplitter().convert(run.stderr).where((l) => l.isNotEmpty),
      everyElement(startsWith('yagura-firewall: ')),
    );
    expect(run.answer['rules'], isEmpty);
  });

  // powershell.exe hung on a request of a few hundred rules sent on standard
  // input. This goes the way the daemon does (encoded command, a request
  // file), with the stand-ins in place of the cmdlets, so a hang that depends
  // on the size of the request shows here.
  test('a_large_request_goes_through_the_runner', () async {
    final log = File(p.join(dir.path, 'effects.log'))..writeAsStringSync('');
    final prelude = [
      "\$env:YAGURA_FAKE_STATE = '[]'",
      "\$env:YAGURA_FAKE_LOG = '${log.path}'",
      "\$env:YAGURA_FAKE_SERVICE = 'Running'",
      _standIns,
    ].join('\n');
    final requests = p.join(dir.path, 'requests');
    final backend = PowerShellFirewall(directory: requests, prelude: prelude);
    final wanted = [
      for (var i = 0; i < 400; i++)
        DesiredRule(
          owner: 'inst-0123456789ab',
          portName: 'port-${i.toString().padLeft(3, '0')}',
          protocol: 'udp',
          port: 20000 + i,
        ),
    ];

    final outcome = await backend.reconcile(
      wanted,
      timeout: const Duration(seconds: 90),
    );

    expect(outcome.changes, hasLength(400));
    expect(outcome.changes.every((c) => c.action == 'created'), isTrue);
    expect(
      log.readAsLinesSync().where((l) => l.startsWith('new ')),
      hasLength(400),
    );
    // The request file is gone.
    expect(Directory(requests).listSync(), isEmpty);
  });

  test('a_group_of_rules_makes_no_lookup_per_rule', () async {
    final rules = [
      for (var i = 0; i < 30; i++)
        rule('Yagura/inst-0123456789ab/p$i/udp', 'UDP', '${3000 + i}'),
    ];

    final run = await runScript(dir, {'mode': 'list'}, rules: rules);

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.answer['rules'], hasLength(30));
    expect(run.filterCalls, ['filters all']);
    expect(run.answer['fallbacks'], 0);
    expect(run.answer['joinedByName'], 0);
  });

  test('filters_with_other_ids_are_piped_once_and_checked', () async {
    final rules = [
      for (var i = 0; i < 30; i++)
        rule('Yagura/inst-0123456789ab/p$i/udp', 'UDP', '${3000 + i}'),
    ];

    final run = await runScript(
      dir,
      {'mode': 'list'},
      rules: rules,
      otherFilterIds: true,
    );

    expect(run.exitCode, 0, reason: run.stderr);
    final ports = {
      for (final r in run.answer['rules']! as List)
        (r as Map)['name']: r['port'],
    };
    expect(ports['Yagura/inst-0123456789ab/p7/udp'], '3007');
    expect(ports['Yagura/inst-0123456789ab/p29/udp'], '3029');
    // One bulk read, one pipe of all rules, and a check of the first and the
    // last rule alone: not a lookup per rule.
    expect(run.filterCalls.where((c) => c == 'filters all'), hasLength(1));
    expect(run.filterCalls, contains('filters piped 30'));
    expect(
      run.filterCalls.where((c) => c.startsWith('filters alone')),
      hasLength(2),
    );
    expect(run.answer['fallbacks'], 2);
    expect(run.stderr, contains('no port filter has the instance id'));
  });

  test('the_answer_reports_the_time_of_each_phase', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'reconcile',
        'desired': [rule(_a, 'udp', '2466')],
      },
      rules: [rule(_b, 'UDP', '2457')],
    );

    expect(run.exitCode, 0, reason: run.stderr);
    final timings = run.answer['timings']! as Map;
    expect(
      timings.keys,
      containsAll([
        'read_request',
        'service_check',
        'get_rules',
        'get_filters',
        'join',
        'deletes',
        'sets_and_creates',
        'creates',
      ]),
    );
    for (final phase in ['get_rules', 'get_filters', 'join']) {
      expect(run.stderr, contains('yagura-firewall: $phase done at'));
    }
  });

  test('list_reports_every_rule_of_the_group_with_its_owned_flag', () async {
    final run = await runScript(
      dir,
      {'mode': 'list'},
      rules: [
        rule(_a, 'UDP', '2456'),
        rule('Yagura/handmade', 'TCP', '9999'),
        rule('yagura/inst-0123456789ab/game/udp', 'UDP', '1'),
      ],
    );

    expect(run.exitCode, 0, reason: run.stderr);
    final listed = {
      for (final r in run.answer['rules']! as List)
        (r as Map)['name']: [r['protocol'], r['port'], r['owned']],
    };
    expect(listed, {
      _a: ['udp', '2456', true],
      'Yagura/handmade': ['tcp', '9999', false],
      // A lower-case lookalike is not the daemon's.
      'yagura/inst-0123456789ab/game/udp': ['udp', '1', false],
    });
  });

  test('reconcile_creates_updates_and_deletes_owned_rules_only', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'reconcile',
        'desired': [
          rule(_a, 'udp', '2466'),
          rule('Yagura/daemon/api/tcp', 'tcp', '7443'),
        ],
      },
      rules: [
        rule(_a, 'UDP', '2456'),
        rule(_b, 'UDP', '2457'),
        rule('Yagura/handmade', 'UDP', '2456'),
        rule('yagura/inst-0123456789ab/lower/udp', 'UDP', '2456'),
      ],
    );

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.actions, {
      _a: 'updated',
      _b: 'deleted',
      'Yagura/daemon/api/tcp': 'created',
    });
    expect(run.answer['unmanaged'], [
      'Yagura/handmade',
      'yagura/inst-0123456789ab/lower/udp',
    ]);
    // Creates and updates first, deletes last: a run stopped at its limit has
    // deleted the least.
    expect(run.log, [
      'new Yagura/daemon/api/tcp TCP 7443 Yagura Inbound Allow Any True',
      'set $_a UDP 2466',
      'remove $_b',
    ]);
  });

  test('a_request_cannot_change_the_group_or_the_pattern', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'reconcile',
        'desired': <Object?>[],
        // The only guards on what the script may touch are in its text.
        'group': 'Other',
        'owned': '.*',
      },
      rules: [rule(_a, 'UDP', '2456'), rule('Yagura/handmade', 'UDP', '9999')],
    );

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.groups, ['group Yagura']);
    expect(run.actions, {_a: 'deleted'});
    expect(run.log, ['remove $_a']);
    expect(run.answer['unmanaged'], ['Yagura/handmade']);

    final removal = await runScript(
      dir,
      {
        'mode': 'remove',
        'names': ['Yagura/handmade'],
        'owned': '',
      },
      rules: [rule('Yagura/handmade', 'UDP', '9999')],
    );
    expect(removal.actions, {'Yagura/handmade': 'failed'});
    expect(removal.log, isEmpty);
  });

  test('the_script_text_holds_the_group_and_the_pattern', () {
    expect(firewallScript, contains("\$group = 'Yagura'"));
    expect(firewallScript, contains(ownedRuleNamePattern));
    expect(firewallScript, isNot(contains('__GROUP__')));
    expect(firewallScript, isNot(contains('__OWNED__')));
  });

  test('a_prune_scope_limits_what_a_reconcile_deletes', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'reconcile',
        'desired': <Object?>[],
        'scope': 'Yagura/inst-0123456789ab/game/',
      },
      rules: [rule(_a, 'UDP', '2456'), rule(_b, 'UDP', '2457')],
    );

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.actions, {_a: 'deleted'});
    expect(run.log, ['remove $_a']);
  });

  test('a_scope_outside_the_group_fails_the_run', () async {
    final run = await runScript(
      dir,
      {'mode': 'reconcile', 'desired': <Object?>[], 'scope': 'Other/'},
      rules: [rule(_a, 'UDP', '2456')],
    );

    expect(run.answer['error'], contains('scope'));
    expect(run.log, isEmpty);
  });

  test('a_rule_that_matches_is_not_touched', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'reconcile',
        'desired': [rule(_a, 'udp', '2456')],
      },
      rules: [rule(_a, 'UDP', '2456')],
    );

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.changes, isEmpty);
    expect(run.log, isEmpty);
  });

  test('an_empty_group_is_not_a_failure', () async {
    final run = await runScript(dir, {
      'mode': 'reconcile',
      'desired': [rule(_a, 'udp', '2456')],
    });

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.answer.containsKey('error'), isFalse, reason: '${run.answer}');
    expect(run.actions, {_a: 'created'});
  });

  test('without_prune_the_owned_rest_stays', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'reconcile',
        'prune': false,
        'desired': [rule('Yagura/daemon/api/tcp', 'tcp', '7443')],
      },
      rules: [rule(_b, 'UDP', '2457')],
    );

    expect(run.actions, {'Yagura/daemon/api/tcp': 'created'});
    expect(run.log.where((l) => l.startsWith('remove')), isEmpty);
  });

  test('a_failing_rule_is_reported_and_the_others_go_on', () async {
    final run = await runScript(dir, {
      'mode': 'reconcile',
      'desired': [rule(_a, 'udp', '2456'), rule(_b, 'udp', '2457')],
    }, failName: _a);

    expect(run.actions, {_a: 'failed', _b: 'created'});
    final failed = run.changes.firstWhere((c) => c['action'] == 'failed');
    expect(failed['error'], contains('Access is denied'));
  });

  test('a_reconcile_deletes_in_one_call', () async {
    final run = await runScript(
      dir,
      {'mode': 'reconcile', 'desired': <Object?>[]},
      rules: [rule(_a, 'UDP', '2456'), rule(_b, 'UDP', '2457')],
    );

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.actions, {_a: 'deleted', _b: 'deleted'});
    expect(run.log, ['remove $_a $_b']);
  });

  test('a_failed_batch_delete_is_tried_rule_by_rule', () async {
    const c = 'Yagura/inst-0123456789ab/rcon/tcp';
    final run = await runScript(
      dir,
      {'mode': 'reconcile', 'desired': <Object?>[]},
      rules: [
        rule(_a, 'UDP', '2456'),
        rule(_b, 'UDP', '2457'),
        rule(c, 'TCP', '2458'),
      ],
      failRemove: _b,
    );

    // The batch removed $_a before it failed on $_b; the retry of $_a finds
    // nothing, which is still a deletion.
    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.actions, {_a: 'deleted', _b: 'failed', c: 'deleted'});
    final failed = run.changes.firstWhere((x) => x['action'] == 'failed');
    expect(failed['error'], contains('Access is denied'));
  });

  test('a_stopped_firewall_service_fails_the_whole_run', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'reconcile',
        'desired': [rule(_a, 'udp', '2456')],
      },
      rules: [rule(_b, 'UDP', '2457')],
      service: 'Stopped',
    );

    expect(run.answer['error'], contains('mpssvc'));
    expect(run.answer.containsKey('changes'), isFalse);
    expect(run.log, isEmpty);
  });

  test('remove_deletes_the_named_owned_rules_that_exist', () async {
    final run = await runScript(
      dir,
      {
        'mode': 'remove',
        'names': [_a, 'Yagura/inst-ffffffffffff/game/udp', 'Yagura/handmade'],
      },
      rules: [
        rule(_a, 'UDP', '2456'),
        rule(_b, 'UDP', '2457'),
        rule('Yagura/handmade', 'UDP', '2456'),
      ],
    );

    expect(run.actions, {_a: 'deleted', 'Yagura/handmade': 'failed'});
    expect(run.log, ['remove $_a']);
  });
}
