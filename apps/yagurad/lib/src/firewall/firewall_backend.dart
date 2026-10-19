import 'rule_names.dart';

/// An inbound allow rule the daemon wants: one port and protocol.
class DesiredRule {
  const DesiredRule({
    required this.owner,
    required this.portName,
    required this.protocol,
    required this.port,
  });

  /// `daemon` or an instance id.
  final String owner;
  final String portName;

  /// `tcp` or `udp`.
  final String protocol;
  final int port;

  String get name => buildRuleName(
    RuleName(owner: owner, portName: portName, protocol: protocol),
  );

  @override
  String toString() => '$name -> $port';
}

/// A rule found in the `Yagura` group.
class ActualRule {
  const ActualRule({
    required this.name,
    required this.protocol,
    required this.port,
  });

  final String name;

  /// Lower case: `tcp`, `udp`, or whatever else the rule holds.
  final String protocol;

  /// The local port as the firewall holds it: a number, a range, `any`.
  final String port;

  /// Whether the daemon owns it (its name follows the naming scheme).
  bool get owned => parseRuleName(name) != null;
}

/// What a reconcile did to one rule: `created`, `updated`, `deleted` or
/// `failed`. The reconciler relabels a `created` rule it had seen before as
/// `recreated`.
class RuleChange {
  const RuleChange({required this.name, required this.action, this.error = ''});

  final String name;
  final String action;
  final String error;

  @override
  String toString() => '$action $name${error.isEmpty ? '' : ' ($error)'}';
}

/// The result of one reconcile script.
class ReconcileOutcome {
  const ReconcileOutcome({
    required this.changes,
    required this.unmanaged,
    this.diagnostics = const {},
  });

  final List<RuleChange> changes;

  /// Names in the group that the daemon does not own and left alone.
  final List<String> unmanaged;

  /// What the script says about its own run (`timings`, `fallbacks`), for the
  /// timing rows; empty from a backend that has none.
  final Map<String, Object?> diagnostics;
}

/// The firewall cannot be used: the service is stopped, PowerShell is
/// missing, or the script ran out of time or failed as a whole. Nothing was
/// deleted on the strength of an incomplete look.
class FirewallUnavailable implements Exception {
  FirewallUnavailable(this.message);

  final String message;

  @override
  String toString() => 'FirewallUnavailable: $message';
}

/// The Windows Firewall as the reconciler uses it (design D11). Every call is
/// one script run; tests inject a fake, and only the `elevated` rows use the
/// real one. All calls throw [FirewallUnavailable] when the firewall cannot be
/// used or does not answer within [timeout].
abstract interface class FirewallBackend {
  /// Every rule in the `Yagura` group, owned or not.
  Future<List<ActualRule>> list({required Duration timeout});

  /// Makes the group hold exactly [desired] among the rules the daemon owns:
  /// creates the missing, updates those whose port or protocol differ and
  /// deletes the owned rest, all in one script. Rules whose name does not
  /// follow the naming scheme, and rules outside the group, are never
  /// touched. With [prune] false the owned rest is left alone: only the
  /// missing are created and the differing updated.
  Future<ReconcileOutcome> reconcile(
    List<DesiredRule> desired, {
    required Duration timeout,
    bool prune = true,
  });

  /// Deletes the owned rules named in [names], when they exist.
  Future<List<RuleChange>> remove(
    List<String> names, {
    required Duration timeout,
  });
}
