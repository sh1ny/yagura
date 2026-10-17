/// What to do about a crash (`instance-lifecycle`, crash detection).
enum RestartAction {
  /// Start the instance again.
  restart,

  /// Too many crashes in the window: `error: crash_loop`.
  crashLoop,

  /// Policy `never`: stay stopped.
  stay,
}

/// At most this many restarts within [crashWindow].
const maxRestarts = 3;
const crashWindow = Duration(minutes: 10);

/// Decides the reaction to a crash. [recentCrashes] holds the crash
/// timestamps within [crashWindow] of [now], the current crash included.
RestartAction decideRestart({
  required String policy,
  required List<DateTime> recentCrashes,
  required DateTime now,
}) {
  if (policy == 'never') return RestartAction.stay;
  final since = now.subtract(crashWindow);
  final recent = recentCrashes.where((at) => !at.isBefore(since)).length;
  return recent > maxRestarts ? RestartAction.crashLoop : RestartAction.restart;
}
