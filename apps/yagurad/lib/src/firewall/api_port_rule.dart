import 'dart:async';

import 'firewall_backend.dart';
import 'rule_names.dart';

/// The daemon's API port rule, as the `service` commands manage it (design
/// D11): created at install, removed at uninstall. Both fail with
/// [FirewallUnavailable] when the firewall cannot be used. The running
/// daemon's reconciler keeps the rule afterwards.
abstract interface class ApiPortRule {
  /// Makes sure `Yagura/daemon/api/tcp` allows [port]; other rules are left
  /// alone.
  Future<void> ensure(int port);

  /// Deletes `Yagura/daemon/api/tcp`, when it exists.
  Future<void> remove();
}

/// [ApiPortRule] over a [FirewallBackend].
class FirewallApiPortRule implements ApiPortRule {
  FirewallApiPortRule(
    this.backend, {
    this.timeout = const Duration(seconds: 30),
  });

  final FirewallBackend backend;
  final Duration timeout;

  @override
  Future<void> ensure(int port) async {
    final outcome = await _bounded(
      backend.reconcile(
        [
          DesiredRule(
            owner: daemonRuleOwner,
            portName: 'api',
            protocol: 'tcp',
            port: port,
          ),
        ],
        timeout: timeout,
        prune: false,
      ),
    );
    _throwIfFailed(outcome.changes);
  }

  @override
  Future<void> remove() async => _throwIfFailed(
    await _bounded(backend.remove([apiRuleName], timeout: timeout)),
  );

  /// A backend that does not answer in [timeout] is unavailable, whatever it
  /// does with the timeout it was given.
  Future<T> _bounded<T>(Future<T> call) => call.timeout(
    timeout,
    onTimeout: () => throw FirewallUnavailable(
      'the firewall did not answer within ${timeout.inSeconds} s',
    ),
  );

  static void _throwIfFailed(List<RuleChange> changes) {
    for (final change in changes) {
      if (change.action == 'failed') {
        throw FirewallUnavailable('${change.name}: ${change.error}');
      }
    }
  }
}
