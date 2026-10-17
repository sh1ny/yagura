import 'dart:async';

import '../instances/health_check.dart';
import 'log_hub.dart';

/// The `log_match` health check on the log hub (task 7.3): marks the run
/// before the launch and matches only the lines read after that mark, so a
/// line left from the previous run does not count and a `fixed` file
/// rewritten past its old size is read from its start (design D6).
class LogHubMatchWatch implements LogMatchWatch {
  LogHubMatchWatch._(this._hub, this._instanceId);

  final LogHub _hub;
  final String _instanceId;
  StreamSubscription<void>? _lines;
  var _matched = false;

  static Future<LogHubMatchWatch> open(
    LogHub hub,
    String instanceId,
    String source,
    RegExp pattern,
  ) async {
    final watch = LogHubMatchWatch._(hub, instanceId);
    final mark = await hub.markRun(instanceId);
    watch._lines = hub.linesAfter(instanceId, source, mark).listen((entry) {
      if (!watch._matched && pattern.hasMatch(entry.text)) {
        watch._matched = true;
      }
    });
    return watch;
  }

  @override
  Future<bool> check() async {
    if (_matched) return true;
    await _hub.pollNow(_instanceId);
    // Lines read by that poll reach the listener asynchronously.
    await Future<void>.delayed(Duration.zero);
    return _matched;
  }

  @override
  Future<void> close() async {
    await _lines?.cancel();
    _lines = null;
  }
}
