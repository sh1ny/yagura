import 'package:yagura_js/yagura_js.dart';

/// Limits that bound hook execution (spec "Hook deadline", "Hook memory cap"
/// and "Hook host calls are bounded"; design D4).
abstract final class HookLimits {
  /// Deadline of a hook call unless the manifest asks for another.
  static const defaultDeadline = Duration(seconds: 5);

  /// Largest deadline a manifest may request.
  static const maxDeadline = Duration(seconds: 60);

  /// Heap of one hook runtime.
  static const memoryBytes = 64 * 1024 * 1024;

  /// Script stack of one hook runtime (see [defaultMaxStackBytes]).
  static const stackBytes = defaultMaxStackBytes;

  /// Serialised hook result.
  static const resultBytes = 1024 * 1024;

  /// Data handled by one host read or parse call.
  static const hostCallBytes = 16 * 1024 * 1024;

  /// Entries returned by one host list call.
  static const listEntries = 10000;

  /// Hook workers alive at once per host, counting timed-out ones whose
  /// isolate has not exited.
  static const workerSlots = 4;

  /// Time after the deadline at which the watchdog gives up on the worker.
  static const watchdogGrace = Duration(seconds: 2);

  /// Time after the watchdog during which an isolate may still exit before it
  /// counts as leaked.
  static const leakGrace = Duration(seconds: 5);

  /// Leaked workers at which hooks are refused until the daemon restarts.
  static const degradedAtLeaked = 2;

  /// Log entries and characters per entry a hook may produce.
  static const logEntries = 500;
  static const logEntryChars = 4096;
}
