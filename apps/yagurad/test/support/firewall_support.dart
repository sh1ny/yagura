import 'dart:async';

import 'package:yagurad/src/firewall/firewall_backend.dart';
import 'package:yagurad/src/firewall/rule_names.dart';
import 'package:yagurad/src/host/daemon.dart';

import 'package:yagurad/src/admin/admin_transport.dart';
import 'package:yagurad/src/admin/named_pipe.dart';

import 'admin_support.dart';
import 'daemon_support.dart';
import 'secret_support.dart';

/// A rule of the fake group.
class FakeRule {
  FakeRule(this.protocol, this.port);

  String protocol;
  String port;

  @override
  String toString() => '$protocol/$port';
}

/// The Windows Firewall group `Yagura` in memory, with the behaviour of the
/// reconcile script: it deletes the owned rules nobody wants, updates those
/// whose port or protocol differ, creates the missing, and leaves a name that
/// does not follow the naming scheme alone. Tests inject it behind
/// [FirewallBackend]; the `elevated` rows use the real firewall.
class FakeFirewall implements FirewallBackend {
  /// The rules in the group by name, foreign ones included.
  final rules = <String, FakeRule>{};

  /// One entry per call: `list`, `reconcile` or `remove`.
  final calls = <String>[];

  /// The desired set of each reconcile call.
  final reconciles = <List<DesiredRule>>[];

  /// When set, every call fails `FirewallUnavailable` with this message, as
  /// when the Windows Firewall service is stopped.
  String? unavailable;

  /// When set, a reconcile waits for this to complete, like a hung script. It
  /// gives up at its timeout, as the real backend does when it kills the
  /// process, but only after [killDelay]: the process takes that long to end.
  Completer<void>? gate;

  /// How long a hung script outlives its timeout before the call returns.
  Duration killDelay = Duration.zero;

  /// Names whose creation fails (the script reports them `failed`).
  final failing = <String>{};

  var _running = 0;

  /// The most reconciles that ran at the same time.
  var maxConcurrent = 0;

  /// Adds a rule the way an administrator would.
  void add(String name, {String protocol = 'udp', required String port}) =>
      rules[name] = FakeRule(protocol, port);

  /// The names of the rules the daemon owns.
  List<String> get ownedNames => [
    for (final name in rules.keys)
      if (parseRuleName(name) != null) name,
  ]..sort();

  /// `<protocol>/<port>` of [name], or null when there is no such rule.
  String? rule(String name) => rules[name]?.toString();

  /// Every port some owned rule allows.
  Set<String> get ownedPorts => {
    for (final entry in rules.entries)
      if (parseRuleName(entry.key) != null) entry.value.port,
  };

  void _check() {
    if (unavailable case final message?) throw FirewallUnavailable(message);
  }

  @override
  Future<List<ActualRule>> list({required Duration timeout}) async {
    calls.add('list');
    _check();
    return [
      for (final entry in rules.entries)
        ActualRule(
          name: entry.key,
          protocol: entry.value.protocol,
          port: entry.value.port,
        ),
    ];
  }

  @override
  Future<ReconcileOutcome> reconcile(
    List<DesiredRule> desired, {
    required Duration timeout,
    bool prune = true,
  }) async {
    calls.add('reconcile');
    reconciles.add(List.of(desired));
    _running++;
    if (_running > maxConcurrent) maxConcurrent = _running;
    try {
      if (gate case final held?) {
        try {
          await held.future.timeout(timeout);
        } on TimeoutException {
          await Future<void>.delayed(killDelay);
          throw FirewallUnavailable(
            'the firewall did not answer within '
            '${timeout.inMilliseconds >= 1000 ? '${timeout.inSeconds} s' : '${timeout.inMilliseconds} ms'}',
          );
        }
      }
      _check();
      final changes = <RuleChange>[];
      final wanted = {for (final rule in desired) rule.name: rule};
      for (final name in rules.keys.toList()) {
        if (prune && parseRuleName(name) != null && !wanted.containsKey(name)) {
          rules.remove(name);
          changes.add(RuleChange(name: name, action: 'deleted'));
        }
      }
      for (final rule in desired) {
        final have = rules[rule.name];
        if (have == null) {
          if (failing.contains(rule.name)) {
            changes.add(
              RuleChange(
                name: rule.name,
                action: 'failed',
                error: 'the rule cannot be created',
              ),
            );
            continue;
          }
          rules[rule.name] = FakeRule(rule.protocol, '${rule.port}');
          changes.add(RuleChange(name: rule.name, action: 'created'));
        } else if (have.protocol != rule.protocol ||
            have.port != '${rule.port}') {
          have
            ..protocol = rule.protocol
            ..port = '${rule.port}';
          changes.add(RuleChange(name: rule.name, action: 'updated'));
        }
      }
      return ReconcileOutcome(
        changes: changes,
        unmanaged: [
          for (final name in rules.keys)
            if (parseRuleName(name) == null) name,
        ],
      );
    } finally {
      _running--;
    }
  }

  @override
  Future<List<RuleChange>> remove(
    List<String> names, {
    required Duration timeout,
  }) async {
    calls.add('remove');
    _check();
    return [
      for (final name in names)
        if (parseRuleName(name) != null && rules.remove(name) != null)
          RuleChange(name: name, action: 'deleted'),
    ];
  }
}

/// The name of the rule for [portName] of instance [id].
String ruleOf(String id, String portName, String protocol) =>
    buildRuleName(RuleName(owner: id, portName: portName, protocol: protocol));

/// Starts a service-mode daemon whose firewall is [firewall].
Future<Daemon> startFirewalled(
  TestEnv env,
  FakeFirewall firewall, {
  Duration firewallTimeout = const Duration(seconds: 30),
  int port = apiPort,
  String? pipe,

  /// How the daemon looks at a holder of the pipe: a connector that trusts
  /// the holder, or null for the real check (the test process is not
  /// LocalSystem, so it trusts nobody).
  AdminConnector Function()? adminProbe,
  Duration? adminStartupWait,
}) => env.start(
  serviceMode: true,
  secretProtector: FakeSecretProtector(serviceSid),
  firewall: firewall,
  firewallTimeout: firewallTimeout,
  port: port,
  adminListener: pipe == null
      ? null
      : () => NamedPipeListener(name: pipe, sddl: currentUserPipeSddl()),
  adminProbe: adminProbe,
  adminStartupWait: adminStartupWait,
);

/// The firewall status of instance [id].
String firewallStatusOf(Daemon daemon, String id) =>
    daemon.instances.get(id).firewallStatus;
