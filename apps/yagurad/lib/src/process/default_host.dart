import 'dart:io';

import '../errors.dart';
import 'process_host.dart';
import 'windows_process_host.dart';

/// The host a daemon uses when none is configured: the Windows host on
/// Windows, else one that cannot launch (the Linux path is M5).
ProcessHost defaultProcessHost({String? helperExecutable}) => Platform.isWindows
    ? WindowsProcessHost(
        helperExecutable: helperExecutable ?? Platform.resolvedExecutable,
      )
    : const UnsupportedProcessHost();

/// A process host for platforms whose process model is not built yet.
class UnsupportedProcessHost implements ProcessHost {
  const UnsupportedProcessHost();

  @override
  Future<RunningServer> launch(LaunchRequest request) => throw YaguraException(
    'launch_failed',
    'this build of yagurad has no process host for '
        '${Platform.operatingSystem}; servers cannot be started',
  );

  @override
  Future<StoppedBy> stop(RunningServer server, StopPlan plan) async =>
      StoppedBy.graceful;

  @override
  Future<RunningServer?> reattach(
    ProcessIdentity identity, {
    ProcessIdentity? relay,
    String runDirectory = '',
  }) async => null;

  @override
  Future<bool> isAlive(ProcessIdentity identity) async => false;

  @override
  Future<void> terminate(ProcessIdentity identity) async {}

  @override
  void release(RunningServer server) {}
}
