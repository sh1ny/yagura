import 'package:yagura_plugin/yagura_plugin.dart';

/// What to launch for one Start (design D2). The real host (group 5) turns it
/// into `launch` -> `relay` -> server.
class LaunchRequest {
  const LaunchRequest({
    required this.instanceId,
    required this.runId,
    required this.executable,
    required this.args,
    required this.env,
    required this.workingDirectory,
    required this.instanceDirectory,
  });

  final String instanceId;
  final String runId;

  /// Absolute path of the server executable.
  final String executable;

  /// Rendered manifest arguments followed by the `onPreStart` hook's.
  final List<String> args;
  final Map<String, String> env;
  final String workingDirectory;
  final String instanceDirectory;
}

/// A launched server process.
abstract interface class RunningServer {
  int get pid;
  String get executable;
  DateTime get startedAt;

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
  });

  final StopStrategy strategy;
  final Duration grace;

  /// Skip the graceful step.
  final bool force;
}

/// The process host (design D2). Win32 and systemd calls sit behind it;
/// group 5 implements it, tests use a fake.
abstract interface class ProcessHost {
  /// Starts the server. Throws `YaguraException('launch_failed', ...)`.
  Future<RunningServer> launch(LaunchRequest request);

  /// Stops [server] following [plan] and reports which step ended it.
  Future<StoppedBy> stop(RunningServer server, StopPlan plan);
}
