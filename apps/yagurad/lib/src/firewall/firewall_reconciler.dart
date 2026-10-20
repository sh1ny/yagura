import 'dart:async';

import 'firewall_backend.dart';
import 'rule_names.dart';

/// What one reconcile did.
class ReconcileResult {
  const ReconcileResult({
    this.changes = const [],
    this.unmanaged = const [],
    this.error = '',
  });

  /// Each rule the run created, updated, recreated or deleted, and the ones
  /// it could not change (`failed`).
  final List<RuleChange> changes;

  /// Rules in the group the daemon does not own and left alone.
  final List<String> unmanaged;

  /// Why the run failed as a whole (`firewall_unavailable`); empty when it
  /// ran.
  final String error;

  /// Whether every rule is as wanted.
  bool get ok => error.isEmpty && !changes.any((c) => c.action == 'failed');

  /// Why the run was not ok, in one line; empty when it was.
  String get problem {
    if (error.isNotEmpty) return error;
    final failed = [
      for (final c in changes)
        if (c.action == 'failed') '${c.name} (${c.error})',
    ];
    return failed.isEmpty
        ? ''
        : 'these rules could not be set: ${failed.join(', ')}';
  }
}

/// Keeps the owned firewall rules in step with what the instances need
/// (design D11).
///
/// Reconciles are single-flight: while one runs, further requests share one
/// pending run that starts when it ends, so a burst of changes costs two
/// scripts at most. The desired rules are read when a run starts, never
/// stored. A run that fails marks the instances it concerns degraded until a
/// later run succeeds. A run that is stopped at its limit may have applied part
/// of its changes (the script applies creates and updates before deletes); the
/// next run completes them.
class FirewallReconciler {
  FirewallReconciler({
    required this.backend,
    required this.desired,
    required this.timeout,
    this.onStatusChanged,
  });

  final FirewallBackend backend;

  /// The rules wanted now: the instances' exposed ports and the API port.
  final List<DesiredRule> Function() desired;

  /// The most one run may take; the same bound goes to the backend.
  final Duration timeout;

  /// Called with the owners (instance ids, or `daemon`) whose degraded state
  /// changed when a run ended.
  final void Function(Set<String> owners)? onStatusChanged;

  var _busy = false;
  var _closed = false;
  Future<ReconcileResult> _current = Future.value(const ReconcileResult());
  Completer<ReconcileResult>? _pending;
  ReconcileResult? _last;
  Set<String>? _known;
  var _degraded = <String>{};

  /// Whether the last run found every rule as wanted (`GetHealth.firewall_ok`).
  bool get ok => _last?.ok ?? true;

  /// The last run, if any.
  ReconcileResult? get last => _last;

  /// Whether the last run left rules of instance [id] (or `daemon`) unsure.
  bool isDegraded(String id) => _degraded.contains(id);

  /// `present` when the daemon's own API port rule is as wanted, else
  /// `degraded` (`status` of the admin channel).
  String get apiRuleStatus =>
      isDegraded(daemonRuleOwner) ? 'degraded' : 'present';

  /// Completes when no run is going or waiting.
  Future<void> get whenIdle async {
    while (_busy) {
      await _current;
    }
  }

  /// Asks for a reconcile and returns the result of the run that covers
  /// every change made before this call: the running one is not enough, as it
  /// may have read the state earlier, so a run that starts after it serves.
  Future<ReconcileResult> request() {
    if (_closed) {
      return Future.value(const ReconcileResult(error: _closedMessage));
    }
    if (!_busy) return _begin();
    return (_pending ??= Completer<ReconcileResult>()).future;
  }

  /// [request], for an operation that reports the result: at most twice
  /// [timeout] (a running reconcile, then the operation's own).
  Future<ReconcileResult> requestAndWait() async {
    try {
      return await request().timeout(timeout * 2);
    } on TimeoutException {
      return ReconcileResult(error: _unanswered(timeout * 2));
    }
  }

  /// Ends the waiting: no run starts after this.
  void close() {
    _closed = true;
    _pending?.complete(const ReconcileResult(error: _closedMessage));
    _pending = null;
  }

  /// What a backend gets beyond its [timeout] to end its script and return.
  static const _backendGrace = Duration(seconds: 15);

  static const _closedMessage = 'the daemon is stopping';

  Future<ReconcileResult> _begin() {
    _busy = true;
    final run = _run();
    _current = run;
    unawaited(
      run.whenComplete(() {
        _busy = false;
        final next = _pending;
        _pending = null;
        if (next == null) return;
        if (_closed) {
          next.complete(const ReconcileResult(error: _closedMessage));
        } else {
          next.complete(_begin());
        }
      }),
    );
    return run;
  }

  static String _unanswered(Duration timeout) =>
      'the firewall did not answer within '
      '${timeout.inMilliseconds >= 1000 ? '${timeout.inSeconds} s' : '${timeout.inMilliseconds} ms'}';

  Future<ReconcileResult> _run() async {
    var wanted = const <DesiredRule>[];
    ReconcileResult result;
    try {
      wanted = desired();
      // The rules of installed instances existed before this daemon started,
      // as far as it knows: one it has to make again was removed by hand.
      _known ??= {
        for (final rule in wanted)
          if (rule.owner != daemonRuleOwner) rule.name,
      };
      // The backend owns the timeout: it counts from its own start, ends the
      // script at the limit and returns once that script has ended. The run is
      // over only then, so the next never overlaps it. The longer bound here
      // is for a backend that ignores its timeout.
      final outcome = await backend
          .reconcile(wanted, timeout: timeout)
          .timeout(
            timeout + _backendGrace,
            onTimeout: () => throw FirewallUnavailable(_unanswered(timeout)),
          );
      final known = _known!;
      result = ReconcileResult(
        changes: [
          for (final change in outcome.changes)
            if (change.action == 'created' && known.contains(change.name))
              RuleChange(name: change.name, action: 'recreated')
            else
              change,
        ],
        unmanaged: outcome.unmanaged,
      );
      final failed = {
        for (final change in result.changes)
          if (change.action == 'failed') change.name,
      };
      _known = {
        for (final rule in wanted)
          if (!failed.contains(rule.name)) rule.name,
      };
    } on FirewallUnavailable catch (e) {
      result = ReconcileResult(error: e.message);
    } on Object catch (e) {
      result = ReconcileResult(error: 'the firewall cannot be used: $e');
    }
    _settle(result, wanted);
    return result;
  }

  void _settle(ReconcileResult result, List<DesiredRule> wanted) {
    final Set<String> degraded;
    if (result.error.isNotEmpty) {
      degraded = {for (final rule in wanted) rule.owner};
    } else {
      degraded = {
        for (final change in result.changes)
          if (change.action == 'failed') ?parseRuleName(change.name)?.owner,
      };
    }
    final changed = {
      ..._degraded.difference(degraded),
      ...degraded.difference(_degraded),
    };
    _degraded = degraded;
    _last = result;
    if (changed.isEmpty) return;
    try {
      onStatusChanged?.call(changed);
    } on Object {
      // A listener that fails does not fail the run.
    }
  }
}
