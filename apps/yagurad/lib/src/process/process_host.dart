import 'package:yagura_plugin/yagura_plugin.dart';

/// What to launch for one Start (design D2). The real host turns it into
/// `launch` -> `relay` -> server.
class LaunchRequest {
  const LaunchRequest({
    required this.instanceId,
    required this.runId,
    required this.executable,
    required this.args,
    required this.env,
    required this.workingDirectory,
    required this.instanceDirectory,
    this.runDirectory = '',
    this.stdoutEncoding = 'utf-8',
    this.onRelayStarted,
  });

  final String instanceId;
  final String runId;

  /// Absolute path of the server executable.
  final String executable;

  /// Rendered manifest arguments followed by the `onPreStart` hook's.
  final List<String> args;
  final Map<String, String> env;

  /// The server's install directory (spike 1.3: Valheim finds its Steam app
  /// id in the working directory).
  final String workingDirectory;
  final String instanceDirectory;

  /// `<instance>/.yagura/run/<run-id>/`, created by the supervisor before the
  /// run is recorded `pending`. Holds `launch.json`, `relay.json` and
  /// `exit.json` (empty for hosts that keep no files).
  final String runDirectory;

  /// The encoding of the server's output (the plugin's `stdout: true` log
  /// source): the relay rotates its capture files only on whole line breaks
  /// of it.
  final String stdoutEncoding;

  /// Called with the relay's identity as soon as the launcher reports it,
  /// before the server is known, so the daemon holds its own record of the
  /// relay (design D9).
  final void Function(ProcessIdentity relay)? onRelayStarted;
}

/// The identity a process is re-attached by: PID, executable path and start
/// time. A PID alone is never enough (PIDs are reused).
class ProcessIdentity {
  const ProcessIdentity({
    required this.pid,
    required this.executable,
    required this.created,
  });

  final int pid;
  final String executable;

  /// The platform's start time of the process, opaque to everyone but the
  /// host that produced it (a `FILETIME` on Windows).
  final int created;

  @override
  bool operator ==(Object other) =>
      other is ProcessIdentity &&
      other.pid == pid &&
      other.executable == executable &&
      other.created == created;

  @override
  int get hashCode => Object.hash(pid, executable, created);

  @override
  String toString() => 'ProcessIdentity($pid $executable @$created)';
}

/// A launched server process.
abstract interface class RunningServer {
  int get pid;
  String get executable;
  DateTime get startedAt;

  /// What a later daemon verifies before it re-attaches.
  ProcessIdentity get identity;

  /// The relay that owns the server's pipes, when the host has one.
  ProcessIdentity? get relay;

  /// Whether the run record did not match this process and it was found by
  /// the fallback (the verified relay's child): the manager raises notice
  /// `run_record_rejected` (design D9).
  bool get recordRejected;

  /// Completes with the exit code when the process ends.
  Future<int> get exitCode;
}

/// How a stop ended.
enum StoppedBy {
  graceful,
  kill;

  String get wireName => name;
}

/// How to stop a server: the plugin's strategy and grace period, or a forced
/// kill.
class StopPlan {
  const StopPlan({
    required this.strategy,
    required this.grace,
    this.force = false,
    this.sendSignal = true,
  });

  final StopStrategy strategy;
  final Duration grace;

  /// Skip the graceful step.
  final bool force;

  /// False when the stop request was already sent before a daemon restart:
  /// only the rest of the grace period remains (design D2).
  final bool sendSignal;
}

/// The process host (design D2). Win32 and systemd calls sit behind it; tests
/// use a fake.
abstract interface class ProcessHost {
  /// Starts the server. Throws `YaguraException('launch_failed', ...)`.
  Future<RunningServer> launch(LaunchRequest request);

  /// Stops [server] following [plan] and reports which step ended it.
  Future<StoppedBy> stop(RunningServer server, StopPlan plan);

  /// The running server with [identity], or null when no live process has
  /// exactly that PID, executable and start time. With no [identity] (the run
  /// never recorded its server, or its file is gone) the verified [relay]'s
  /// own child running as the account is the server, returned with
  /// [RunningServer.recordRejected] set; null when there is none. [runDirectory] holds the
  /// run's `exit.json`, which gives the exit code of a process that is not
  /// this daemon's child. Throws `YaguraException('run_record_rejected')`
  /// when the record names a process that is not a verified server and no
  /// verified relay has a server of its own (design D9).
  Future<RunningServer?> reattach(
    ProcessIdentity? identity, {
    ProcessIdentity? relay,
    String runDirectory = '',
  });

  /// Whether a live process has exactly [identity].
  Future<bool> isAlive(ProcessIdentity identity);

  /// Ends the process with [identity] if it is still that process.
  Future<void> terminate(ProcessIdentity identity);

  /// Drops the host's handles and waiters for [server]; it is not supervised
  /// by this host any more (the daemon is closing). The process keeps running.
  void release(RunningServer server);
}
