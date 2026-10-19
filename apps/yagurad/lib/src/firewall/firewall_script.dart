import 'rule_names.dart';

/// The PowerShell script of one firewall run (design D11): it reads the rules
/// of the `Yagura` group with their port filters and, in the same run, applies
/// what the request asks for. One script per reconcile keeps the cost to one
/// PowerShell start and one pass over the rules.
///
/// The request is one JSON document in the file named by the environment
/// variable `YAGURA_FIREWALL_REQUEST` (not standard input: a run with a large
/// request on standard input hung in CI); the answer is
/// one JSON document on standard output, ASCII only:
///
/// ```
/// { "mode": "list" | "reconcile" | "remove",
///   "desired": [ { "name", "protocol", "port" } ],   // reconcile
///   "prune": true,                                    // reconcile: delete the
///                                                     // owned rest (default)
///   "scope": "Yagura/",                               // reconcile: narrows the
///                                                     // deletes (optional)
///   "names": [ "..." ] }                              // remove
/// ```
///
/// Answers: `{rules: [{name, protocol, port, owned}]}` for `list`,
/// `{changes: [{name, action, error}], unmanaged: [name]}` for `reconcile` and
/// `remove`, and `{error: text}` when the run as a whole failed. A change that
/// failed is recorded with action `failed` and does not stop the others.
///
/// Every answer also carries `timings` (milliseconds spent in each phase),
/// `fallbacks` (rules whose port filter had to be asked for alone) and
/// `joinedByName`, for the timing rows; and each phase writes one progress line
/// to standard error, so a run that hangs says where.
///
/// A rule is touched only when its name matches `owned` (`-cmatch`, so the
/// match is case-sensitive) and it is in the group, and the lookups of names
/// are ordinal, so a rule named `yagura/...` is never taken for `Yagura/...`.
/// The group and the name pattern are part of the script text, not of the
/// request: they are code, and a request file can neither widen nor empty
/// them. The request may only narrow what a reconcile deletes, with `scope`, a
/// name prefix under `Yagura/` (the daemon uses `Yagura/`; the elevated tests
/// use the prefix of their own instance). The script never exits: it ends by
/// writing the answer, and tests run it against stand-ins for the cmdlets.
///
/// Lines that are only a comment are left out of the script that runs: it goes
/// on the command line, which has room for about 9,000 characters of it.
final firewallScript = _template
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n')
    .replaceAll('__GROUP__', firewallGroup)
    .replaceAll('__OWNED__', ownedRuleNamePattern);

const _template = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::Error.WriteLine('yagura-firewall: started')

# Time spent per phase, and the clock the phases are cut from.
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$timings = @{}
$mark = @{ last = 0 }
$fallbacks = 0
$joinedByName = 0

function Phase($name) {
  $now = $clock.ElapsedMilliseconds
  $timings[$name] = [long]$timings[$name] + ($now - $mark.last)
  $mark.last = $now
  [Console]::Error.WriteLine("yagura-firewall: $name done at $now ms")
}

function Spent($name, $since) {
  $timings[$name] = [long]$timings[$name] + ($clock.ElapsedMilliseconds - $since)
}

function Send($result) {
  $result.timings = $timings
  $result.fallbacks = $fallbacks
  $result.joinedByName = $joinedByName
  [Console]::Out.Write((ConvertTo-Json -InputObject $result -Compress -Depth 6))
}

function Plain($text) {
  return ([string]$text -replace '[^\x20-\x7e]', '?')
}

function New-Names() {
  return [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)
}

try {
  $path = $env:YAGURA_FIREWALL_REQUEST
  if ([string]::IsNullOrEmpty($path)) { throw 'no request file was given' }
  if (([System.IO.File]::GetAttributes($path) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'the request file is a link'
  }
  $request = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
  $group = '__GROUP__'
  $owned = '__OWNED__'
  if ([string]::IsNullOrEmpty($group) -or [string]::IsNullOrEmpty($owned)) {
    throw 'the script has no group or name pattern'
  }
  # What a reconcile may delete: owned names under this prefix.
  $scope = $group + '/'
  if (-not [string]::IsNullOrEmpty([string]$request.scope)) { $scope = [string]$request.scope }
  if (-not $scope.StartsWith($group + '/', [System.StringComparison]::Ordinal)) {
    throw 'the prune scope is not under the group'
  }
  Phase 'read_request'

  # The cmdlets can answer from the policy store while the service is down;
  # a run that cannot be trusted to have changed anything must not claim to.
  $service = Get-Service -Name 'mpssvc'
  if ($service.Status -ne 'Running') {
    throw 'the Windows Firewall service (mpssvc) is not running'
  }
  Phase 'service_check'

  # An empty group is "not found", which is not a failure.
  $problems = @()
  $rules = @(Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue -ErrorVariable problems)
  foreach ($problem in $problems) {
    if ($problem.FullyQualifiedErrorId -notlike 'CmdletizationQuery_NotFound*' -and $problem.CategoryInfo.Category -ne 'ObjectNotFound') {
      throw $problem
    }
  }
  Phase 'get_rules'

  # The port filters of all rules in one query, matched to their rule by the
  # instance id both carry, or failing that by the rule's name. Rules that
  # still have no match are piped to the cmdlet together, once; the answer is
  # trusted only when it has one filter per rule and its first and last agree
  # with a lookup of that rule alone. Anything else is asked for alone, which
  # costs a query per rule: `fallbacks` counts those lookups and stays zero
  # when the ids match.
  $filters = New-Names
  if ($rules.Count -gt 0) {
    foreach ($filter in @(Get-NetFirewallPortFilter -All)) {
      $filters[[string]$filter.InstanceID] = $filter
    }
  }
  Phase 'get_filters'

  $found = New-Names
  $missing = New-Object System.Collections.ArrayList
  foreach ($rule in $rules) {
    $filter = $null
    if ($filters.TryGetValue([string]$rule.InstanceID, [ref]$filter)) {
      $found[[string]$rule.Name] = $filter
    }
    elseif ($filters.TryGetValue([string]$rule.Name, [ref]$filter)) {
      $found[[string]$rule.Name] = $filter
      $joinedByName++
    }
    else {
      [void]$missing.Add($rule)
    }
  }

  if ($missing.Count -gt 0) {
    $first = $missing[0]
    [Console]::Error.WriteLine("yagura-firewall: no port filter has the instance id '$($first.InstanceID)' of rule '$($first.Name)' ($($missing.Count) rules, $($filters.Count) filters)")
    $batch = @($missing | Get-NetFirewallPortFilter)
    $trusted = $batch.Count -eq $missing.Count
    foreach ($index in @(0, ($missing.Count - 1) | Select-Object -Unique)) {
      if (-not $trusted) { break }
      $fallbacks++
      $alone = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $missing[$index]
      if ([string]$alone.Protocol -ne [string]$batch[$index].Protocol -or
          (@($alone.LocalPort) -join ',') -ne (@($batch[$index].LocalPort) -join ',')) {
        $trusted = $false
      }
    }
    for ($index = 0; $index -lt $missing.Count; $index++) {
      if ($trusted) {
        $found[[string]$missing[$index].Name] = $batch[$index]
      }
      else {
        $fallbacks++
        $found[[string]$missing[$index].Name] = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $missing[$index]
      }
    }
  }

  $actual = New-Names
  foreach ($rule in $rules) {
    $filter = $found[[string]$rule.Name]
    $protocol = ([string]$filter.Protocol).ToLowerInvariant()
    if ($protocol -eq '6') { $protocol = 'tcp' }
    elseif ($protocol -eq '17') { $protocol = 'udp' }
    $actual[[string]$rule.Name] = @{
      name = [string]$rule.Name
      protocol = $protocol
      port = (@($filter.LocalPort) -join ',').ToLowerInvariant()
    }
  }
  Phase 'join'

  $changes = New-Object System.Collections.ArrayList
  $unmanaged = New-Object System.Collections.ArrayList
  foreach ($name in @($actual.Keys | Sort-Object)) {
    if (-not ($name -cmatch $owned)) { [void]$unmanaged.Add($name) }
  }

  function Record($name, $action, $problem) {
    [void]$changes.Add(@{ name = $name; action = $action; error = $problem })
  }

  if ($request.mode -eq 'list') {
    $listed = New-Object System.Collections.ArrayList
    foreach ($name in @($actual.Keys | Sort-Object)) {
      $rule = $actual[$name]
      [void]$listed.Add(@{
        name = $rule.name
        protocol = $rule.protocol
        port = $rule.port
        owned = [bool]($name -cmatch $owned)
      })
    }
    Phase 'list'
    Send @{ rules = @($listed) }
  }
  elseif ($request.mode -eq 'remove') {
    foreach ($name in @($request.names)) {
      $name = [string]$name
      if (-not ($name -cmatch $owned)) {
        Record $name 'failed' 'not a rule the daemon owns'
      }
      elseif ($actual.ContainsKey($name)) {
        try {
          Remove-NetFirewallRule -Name $name
          Record $name 'deleted' ''
        }
        catch {
          Record $name 'failed' (Plain $_.Exception.Message)
        }
      }
    }
    Phase 'deletes'
    Send @{ changes = @($changes); unmanaged = @($unmanaged) }
  }
  else {
    $wanted = New-Names
    foreach ($rule in @($request.desired)) { $wanted[[string]$rule.name] = $rule }

    foreach ($name in @($wanted.Keys | Sort-Object)) {
      $rule = $wanted[$name]
      $protocol = ([string]$rule.protocol).ToLowerInvariant()
      $port = [string]$rule.port
      if (-not ($name -cmatch $owned)) {
        Record $name 'failed' 'not a rule the daemon owns'
      }
      elseif ($actual.ContainsKey($name)) {
        $current = $actual[$name]
        if ($current.protocol -ne $protocol -or $current.port -ne $port) {
          $since = $clock.ElapsedMilliseconds
          try {
            Set-NetFirewallRule -Name $name -Protocol $protocol.ToUpperInvariant() -LocalPort $port
            Record $name 'updated' ''
          }
          catch {
            Record $name 'failed' (Plain $_.Exception.Message)
          }
          Spent 'sets' $since
        }
      }
      else {
        $since = $clock.ElapsedMilliseconds
        try {
          New-NetFirewallRule -Name $name -DisplayName $name -Description 'Opened by yagurad for a game server or the daemon API. Do not edit: yagurad keeps this rule in step with the instance ports.' -Group $group -Direction Inbound -Action Allow -Protocol $protocol.ToUpperInvariant() -LocalPort $port -Profile Any -Enabled True | Out-Null
          Record $name 'created' ''
        }
        catch {
          Record $name 'failed' (Plain $_.Exception.Message)
        }
        Spent 'creates' $since
      }
    }
    Phase 'sets_and_creates'

    # Owned rules that nothing wants any more (the install of the service adds
    # its one rule without judging the rest).
    $prune = $request.prune -ne $false
    $gone = @(foreach ($name in @($actual.Keys | Sort-Object)) {
      if ($prune -and ($name -cmatch $owned) -and $name.StartsWith($scope, [System.StringComparison]::Ordinal) -and -not $wanted.ContainsKey($name)) { $name }
    })
    # One call for all of them: each call costs about 400 ms, whatever it
    # removes. When it fails, each rule is tried alone, and a rule the batch
    # already removed counts as deleted.
    if ($gone) {
      try { Remove-NetFirewallRule -Name $gone; foreach ($n in $gone) { Record $n 'deleted' '' } }
      catch {
        foreach ($n in $gone) {
          try { Remove-NetFirewallRule -Name $n; Record $n 'deleted' '' }
          catch {
            $m = Plain $_.Exception.Message
            if (Get-NetFirewallRule -Name $n -ErrorAction SilentlyContinue) { Record $n 'failed' $m } else { Record $n 'deleted' '' }
          }
        }
      }
    }

    Phase 'deletes'
    Send @{ changes = @($changes); unmanaged = @($unmanaged) }
  }
}
catch {
  Send @{ error = (Plain $_.Exception.Message) }
}
''';
