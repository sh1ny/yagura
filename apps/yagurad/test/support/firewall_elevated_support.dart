import 'dart:math';

import 'package:test/test.dart';

import 'elevated_support.dart';

// Helpers of the firewall `elevated` rows. They create, read and delete rules
// of the real Windows Firewall, so they run only in the manual `elevated`
// workflow (.github/workflows/elevated.yml), never on a developer's desktop.
// Every rule a row creates is named after a random instance id of its own,
// and the clean-up removes by that name, never the whole group.

final _random = Random.secure();

/// A fresh instance id, `inst-` and twelve hex digits.
String freshInstanceId() =>
    'inst-${[for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16)].join()}';

/// A name no real rule has, for a rule the admin made.
String freshRuleName(String prefix) =>
    '$prefix ${_random.nextInt(1 << 30).toRadixString(16)}';

// A cmdlet that finds nothing under -ErrorAction SilentlyContinue still leaves
// `\$?` false, and `powershell -Command` then exits 1. The helpers whose
// "nothing there" is an answer end with `exit 0`.
Future<String> _run(String script, {Duration? timeout}) async {
  final result = await powershell(
    script,
    timeout: timeout ?? const Duration(minutes: 2),
  );
  expect(
    result.exitCode,
    0,
    reason: 'PowerShell failed:\n$script\n${result.stdout}${result.stderr}',
  );
  return '${result.stdout}'.trim();
}

/// Creates a rule the way an administrator would. [group] empty puts it in no
/// group.
Future<void> createRule(
  String name, {
  String group = '',
  String protocol = 'UDP',
  required int port,
}) async {
  addTearDown(() => removeRules(name));
  await _run(
    "New-NetFirewallRule -Name '$name' -DisplayName '$name' "
    '-Direction Inbound -Action Allow -Protocol $protocol -LocalPort $port '
    "${group.isEmpty ? '' : "-Group '$group'"} | Out-Null",
  );
}

/// The rule [name] as `Name|Group|Enabled|Direction|Action|Protocol|Port`, or
/// null when there is none.
Future<String?> describeRule(String name) async {
  final text = await _run(
    "\$r = Get-NetFirewallRule -Name '$name' -ErrorAction SilentlyContinue; "
    'if (\$r) { \$f = \$r | Get-NetFirewallPortFilter; '
    "'{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f \$r.Name, \$r.Group, \$r.Enabled, "
    '\$r.Direction, \$r.Action, \$f.Protocol, (\$f.LocalPort -join \',\') }; exit 0',
  );
  return text.isEmpty ? null : text;
}

/// The names of the rules in the group `Yagura` whose name starts with
/// [prefix].
Future<List<String>> groupRuleNames(String prefix) async {
  final text = await _run(
    "Get-NetFirewallRule -Group 'Yagura' -ErrorAction SilentlyContinue | "
    "Where-Object { \$_.Name.StartsWith('$prefix', "
    '[System.StringComparison]::Ordinal) } | '
    'ForEach-Object { \$_.Name }; exit 0',
  );
  return text.isEmpty ? [] : text.split(RegExp(r'\r?\n'));
}

/// Every local port that some rule of the group `Yagura` allows, with the
/// rule name.
Future<Map<String, String>> groupPorts() async {
  final text = await _run(
    "Get-NetFirewallRule -Group 'Yagura' -ErrorAction SilentlyContinue | "
    'ForEach-Object { \$f = \$_ | Get-NetFirewallPortFilter; '
    "'{0}|{1}' -f \$_.Name, (\$f.LocalPort -join ',') }; exit 0",
  );
  return {
    for (final line in text.isEmpty ? <String>[] : text.split(RegExp(r'\r?\n')))
      line.split('|').first: line.split('|').last,
  };
}

/// Deletes the rules whose name starts with [prefix], in any group, when
/// there are any.
Future<void> removeRules(String prefix) => _run(
  "Get-NetFirewallRule -ErrorAction SilentlyContinue | "
  "Where-Object { \$_.Name.StartsWith('$prefix', "
  '[System.StringComparison]::Ordinal) } | '
  'Remove-NetFirewallRule; exit 0',
  timeout: const Duration(minutes: 5),
);

/// Deletes every rule of the group `Yagura`; for the rows that run a real
/// service, whose daemon owns rules the row did not name.
Future<void> removeYaguraGroup() => _run(
  "Get-NetFirewallRule -Group 'Yagura' -ErrorAction SilentlyContinue | "
  'Remove-NetFirewallRule; exit 0',
  timeout: const Duration(minutes: 5),
);

/// A PowerShell script written as lines, run as one `-Command` line.
String _oneLine(String script) => script
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .join(' ');

/// Makes [count] inbound UDP allow rules named `Yagura/<id>/p000/udp`,
/// `.../p001/udp` and so on, on ports from [firstPort], with
/// `New-NetFirewallRule` and the parameters the reconcile script uses, in one
/// PowerShell process of their own (not through the reconciler). Returns how
/// long that took. The rules go when the test ends, even when it fails.
///
/// The rules cannot be made through the COM API (HNetCfg.FwPolicy2): it does
/// not set the rule ID, the cmdlets' `Name`, which the script keys on, so the
/// script would not see them.
Future<Duration> createRulesViaCmdlet({
  required String id,
  required int count,
  required int firstPort,
}) async {
  addTearDown(() => removeGroupRulesWithPrefix('Yagura/$id/'));
  final watch = Stopwatch()..start();
  await _run(
    _oneLine(
      r'''
      for ($i = 0; $i -lt __COUNT__; $i++) {
        $n = ('Yagura/__ID__/p{0:D3}/udp' -f $i);
        New-NetFirewallRule -Name $n -DisplayName $n -Description 'Opened by yagurad for a game server or the daemon API.' -Group 'Yagura' -Direction Inbound -Action Allow -Protocol UDP -LocalPort ([string](__FIRST__ + $i)) -Profile Any -Enabled True | Out-Null
      };
      exit 0
      '''
          .replaceAll('__COUNT__', '$count')
          .replaceAll('__ID__', id)
          .replaceAll('__FIRST__', '$firstPort'),
    ),
    timeout: const Duration(minutes: 20),
  );
  return (watch..stop()).elapsed;
}

/// Deletes the rules of the group `Yagura` whose name starts with [prefix],
/// in one process.
Future<void> removeGroupRulesWithPrefix(String prefix) => _run(
  _oneLine(
    r'''
    Get-NetFirewallRule -Group 'Yagura' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name.StartsWith('__PREFIX__', [System.StringComparison]::Ordinal) } |
    Remove-NetFirewallRule;
    exit 0
    '''
        .replaceAll('__PREFIX__', prefix),
  ),
  timeout: const Duration(minutes: 20),
);

/// What the firewall costs on this host, as `NAME=<number>` lines from one
/// PowerShell process: reading the group and all port filters with the
/// cmdlets, the number of rules on the host, one create, one port change and
/// one delete with the cmdlets and with the COM API, and a COM listing of the
/// group with its ports. Its own probe rules are removed again.
Future<List<String>> measureFirewall() async {
  final text = await _run(
    _oneLine(r'''
    function Measure-Step($label, [scriptblock]$work) {
      $sw = [System.Diagnostics.Stopwatch]::StartNew();
      try { & $work | Out-Null } catch { ('{0}_ERROR={1}' -f $label, $_.Exception.Message) };
      $sw.Stop();
      ('{0}={1}' -f $label, $sw.ElapsedMilliseconds)
    };
    $probe = 'YaguraProbe';
    $cmdlet = $probe + ' cmdlet ' + [guid]::NewGuid().ToString('N');
    $com = $probe + ' com ' + [guid]::NewGuid().ToString('N');
    $p = New-Object -ComObject HNetCfg.FwPolicy2;
    try {
      ('FIREWALL_TOTAL_RULES={0}' -f $p.Rules.Count);
      Measure-Step 'FIREWALL_GET_GROUP_MS' { Get-NetFirewallRule -Group 'Yagura' };
      Measure-Step 'FIREWALL_GET_PORTFILTER_ALL_MS' { Get-NetFirewallPortFilter -All };
      $one = Get-NetFirewallRule -Group 'Yagura' | Select-Object -First 1;
      if ($one) {
        ('FIREWALL_RULE_NAME={0}' -f $one.Name);
        ('FIREWALL_RULE_INSTANCEID={0}' -f $one.InstanceID);
        Measure-Step 'FIREWALL_FILTER_OF_ONE_RULE_MS' { $script:alone = $one | Get-NetFirewallPortFilter };
        ('FIREWALL_FILTER_INSTANCEID={0}' -f $alone.InstanceID);
        ('FIREWALL_FILTER_ALL_FIRST_INSTANCEID={0}' -f (Get-NetFirewallPortFilter -All | Select-Object -First 1).InstanceID)
      };
      Measure-Step 'FIREWALL_NEW_ONE_MS' { New-NetFirewallRule -Name $cmdlet -DisplayName $cmdlet -Group $probe -Direction Inbound -Action Allow -Protocol UDP -LocalPort 22222 };
      Measure-Step 'FIREWALL_SET_ONE_MS' { Set-NetFirewallRule -Name $cmdlet -LocalPort 22223 };
      Measure-Step 'FIREWALL_REMOVE_ONE_MS' { Remove-NetFirewallRule -Name $cmdlet };
      Measure-Step 'FIREWALL_COM_NEW_ONE_MS' {
        $r = New-Object -ComObject HNetCfg.FWRule;
        $r.Name = $com; $r.Grouping = $probe; $r.Protocol = 17; $r.LocalPorts = '22222';
        $r.Direction = 1; $r.Action = 1; $r.Profiles = 2147483647; $r.Enabled = $true;
        $p.Rules.Add($r)
      };
      ('FIREWALL_COM_RULE_ID={0}' -f (Get-NetFirewallRule -DisplayName $com -ErrorAction SilentlyContinue).Name);
      Measure-Step 'FIREWALL_COM_SET_ONE_MS' { $p.Rules.Item($com).LocalPorts = '22223' };
      Measure-Step 'FIREWALL_COM_REMOVE_ONE_MS' { $p.Rules.Remove($com) };
      Measure-Step 'FIREWALL_COM_LIST_GROUP_MS' {
        foreach ($r in $p.Rules) { if ($r.Grouping -eq 'Yagura') { '{0}|{1}|{2}' -f $r.Name, $r.Protocol, $r.LocalPorts } }
      }
    }
    finally {
      Remove-NetFirewallRule -Name $cmdlet -ErrorAction SilentlyContinue;
      try { $p.Rules.Remove($com) } catch { }
    };
    exit 0
    '''),
    timeout: const Duration(minutes: 10),
  );
  return text.isEmpty ? [] : text.split(RegExp(r'\r?\n'));
}

/// Polls [condition] until it holds or [timeout] passes.
Future<void> eventually(
  Future<bool> Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $reason');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
