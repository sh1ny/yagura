import 'dart:async';

import 'package:yagura_plugin/yagura_plugin.dart';

import 'process_host.dart';

/// The stop sequence of design D2, independent of the platform: send the
/// signal (a failed one counts as a failed graceful step), wait up to the
/// grace period, then kill. Strategy `kill` and a forced stop skip the
/// graceful step.
///
/// [sendSignal] reports whether the request was delivered; it may also
/// throw, which counts as not delivered. [exited] completes when the process
/// is gone.
Future<StoppedBy> performStop(
  StopPlan plan, {
  required Future<bool> Function() sendSignal,
  required Future<void> Function() kill,
  required Future<void> exited,
  Duration killWait = const Duration(seconds: 10),
}) async {
  final graceful = !plan.force && plan.strategy == StopStrategy.signal;
  if (graceful) {
    if (plan.sendSignal) {
      try {
        await sendSignal();
      } on Object {
        // A signal that could not be delivered is a failed graceful step; the
        // grace period still runs and then the process is killed.
      }
    }
    if (await _exitsWithin(exited, plan.grace)) return StoppedBy.graceful;
  }
  await kill();
  await _exitsWithin(exited, killWait);
  return StoppedBy.kill;
}

/// Whether [exited] completes within [limit].
Future<bool> _exitsWithin(Future<void> exited, Duration limit) {
  final result = Completer<bool>();
  final timer = Timer(limit, () {
    if (!result.isCompleted) result.complete(false);
  });
  exited.then<void>(
    (_) {
      if (!result.isCompleted) result.complete(true);
    },
    onError: (Object _) {
      if (!result.isCompleted) result.complete(true);
    },
  );
  return result.future.whenComplete(timer.cancel);
}
