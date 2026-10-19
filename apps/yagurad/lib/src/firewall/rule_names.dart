/// The Windows Firewall group every rule the daemon owns belongs to (design
/// D11).
const firewallGroup = 'Yagura';

/// The owner segment of the daemon's own rules (the API port).
const daemonRuleOwner = 'daemon';

/// The rule for the daemon's API port.
const apiRuleName = 'Yagura/daemon/api/tcp';

/// The names the daemon owns: `Yagura/<owner>/<port-name>/<protocol>`, where
/// the owner is `daemon` or an instance id and the port name is one the
/// plugin schema allows (`^[a-z][a-z0-9_-]*$`). A rule in the group whose name
/// does not match is `unmanaged` and never touched. The PowerShell script
/// gets this very pattern (`-cmatch`), so there is one definition.
const ownedRuleNamePattern =
    r'^Yagura/(daemon|inst-[0-9a-f]{12})/[a-z0-9_-]+/(tcp|udp)$';

final _owned = RegExp(ownedRuleNamePattern);

/// The parts of an owned rule name.
class RuleName {
  const RuleName({
    required this.owner,
    required this.portName,
    required this.protocol,
  });

  /// `daemon` or an instance id.
  final String owner;
  final String portName;

  /// `tcp` or `udp`.
  final String protocol;

  /// The instance this rule belongs to; null for the daemon's own rules.
  String? get instanceId => owner == daemonRuleOwner ? null : owner;

  @override
  String toString() => buildRuleName(this);
}

/// The name of the rule for [rule].
String buildRuleName(RuleName rule) =>
    '$firewallGroup/${rule.owner}/${rule.portName}/${rule.protocol}';

/// The parts of [name], or null when it is not a name the daemon owns.
RuleName? parseRuleName(String name) {
  if (!_owned.hasMatch(name)) return null;
  final parts = name.split('/');
  return RuleName(owner: parts[1], portName: parts[2], protocol: parts[3]);
}
