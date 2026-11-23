import 'dart:math';

/// When the daemon checks the workshop for newer mod versions (design D14):
/// every [interval] plus or minus up to [jitter], the first one [first] after
/// the start, and after a failed check again after [backoffStart], doubling up
/// to [backoffMax].
class ModCheckSchedule {
  const ModCheckSchedule({
    this.first = const Duration(minutes: 10),
    this.interval = const Duration(hours: 6),
    this.jitter = const Duration(minutes: 30),
    this.backoffStart = const Duration(minutes: 5),
    this.backoffMax = const Duration(hours: 6),
    this.enabled = true,
  });

  /// A schedule that never runs; `CheckModUpdates` still works.
  const ModCheckSchedule.off()
    : first = Duration.zero,
      interval = Duration.zero,
      jitter = Duration.zero,
      backoffStart = Duration.zero,
      backoffMax = Duration.zero,
      enabled = false;

  /// Delay from the daemon's start to the first check.
  final Duration first;

  /// Gap between two successful checks, before the jitter.
  final Duration interval;

  /// The most the gap after a successful check differs from [interval].
  final Duration jitter;

  /// Gap after the first failed check; each further failure doubles it.
  final Duration backoffStart;

  /// The longest gap after failures.
  final Duration backoffMax;

  /// Whether the timer runs at all.
  final bool enabled;

  /// The gap after a successful check.
  Duration next(Random random) {
    if (jitter == Duration.zero) return interval;
    final spread = jitter.inMicroseconds;
    final offset = random.nextInt(2 * spread + 1) - spread;
    return interval + Duration(microseconds: offset);
  }

  /// The gap after [failures] failed checks in a row (1 or more).
  Duration backoff(int failures) {
    var gap = backoffStart;
    for (var i = 1; i < failures && gap < backoffMax; i++) {
      gap *= 2;
    }
    return gap > backoffMax ? backoffMax : gap;
  }
}
