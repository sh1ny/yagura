import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../firewall/firewall_backend.dart';
import '../firewall/firewall_reconciler.dart';
import '../firewall/rule_names.dart';
import '../host/daemon.dart';
import 'service_support.dart';

/// The `Firewall` service of a service-mode daemon (design D11).
class FirewallApi extends pb.FirewallServiceBase with GuardedService {
  FirewallApi(this.daemon, this.logSink);

  final Daemon daemon;

  @override
  final LogSink logSink;

  FirewallReconciler get _reconciler => daemon.firewall!;

  /// The rules in the group and the ones the daemon wants. A wanted rule that
  /// is not there is listed with `present: false`; a rule in the group that
  /// is not the daemon's is listed with `managed: false`. When the firewall
  /// cannot be read, the wanted rules are listed as not present and the
  /// status says `firewall_unavailable`.
  @override
  Future<pb.ListRulesResponse> listRules(
    ServiceCall call,
    pb.ListRulesRequest request,
  ) async {
    final wanted = {
      for (final rule in daemon.instances.desiredFirewallRules())
        rule.name: rule,
    };
    List<ActualRule>? actual;
    try {
      actual = await _reconciler.backend.list(timeout: _reconciler.timeout);
    } on FirewallUnavailable {
      actual = null;
    }
    final found = {
      for (final rule in actual ?? <ActualRule>[]) rule.name: rule,
    };
    final rules = <pb.FirewallRule>[];
    for (final name in {...wanted.keys, ...found.keys}.toList()..sort()) {
      final want = wanted[name];
      final have = found[name];
      final parsed = parseRuleName(name);
      rules.add(
        pb.FirewallRule(
          name: name,
          instanceId: parsed?.instanceId ?? '',
          portName: parsed?.portName ?? '',
          // What the firewall holds, when it holds the rule; else what is
          // wanted.
          port: int.tryParse(have?.port ?? '') ?? want?.port ?? 0,
          protocol: have?.protocol ?? want?.protocol ?? '',
          managed: parsed != null,
          present: have != null,
          // An unmanaged rule is nothing to change; an owned one is in step
          // when it exists as wanted.
          inStep:
              parsed == null ||
              (want != null &&
                  have != null &&
                  have.protocol == want.protocol &&
                  have.port == '${want.port}'),
        ),
      );
    }
    return pb.ListRulesResponse(
      rules: rules,
      status: actual == null ? 'firewall_unavailable' : 'ok',
    );
  }

  /// Reconciles now and reports each change. Fails `firewall_unavailable`
  /// when the firewall could not be used; individual rules that could not be
  /// set are `failed` changes.
  @override
  Future<pb.ReconcileResponse> reconcile(
    ServiceCall call,
    pb.ReconcileRequest request,
  ) async {
    final result = await _reconciler.requestAndWait();
    if (result.error.isNotEmpty) {
      throw YaguraException('firewall_unavailable', result.error);
    }
    return pb.ReconcileResponse(
      changes: [
        for (final change in result.changes)
          pb.RuleChange(
            name: change.name,
            action: change.action,
            error: change.error,
          ),
      ],
    );
  }
}
