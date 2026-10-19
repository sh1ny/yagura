import 'dart:io';

import '../errors.dart';
import '../platform/win32_service.dart';
import 'install_layout.dart';

/// What the service control manager says about a service.
enum ServiceStatus { notInstalled, stopped, startPending, stopPending, running }

/// The service control manager and the WinSW wrapper (ADR 0012). The seam
/// between the install logic and the machine: tests use a fake, and only the
/// `elevated` rows use [WinswServiceControl].
abstract interface class ServiceControl {
  /// The state of the service called [serviceName].
  ServiceStatus status(String serviceName);

  /// Registers the service with the SCM from the configuration beside the
  /// wrapper (`<service>.exe install`).
  Future<void> install(InstallLayout layout);

  /// Removes the registration (the service must be stopped).
  Future<void> uninstall(InstallLayout layout);

  /// Asks the SCM to start or stop the service; the caller waits for the
  /// state to change.
  Future<void> start(InstallLayout layout);
  Future<void> stop(InstallLayout layout);
}

/// [ServiceControl] over `advapi32` for the state and the WinSW wrapper for
/// the changes.
class WinswServiceControl implements ServiceControl {
  const WinswServiceControl();

  @override
  ServiceStatus status(String serviceName) =>
      switch (queryServiceState(serviceName)) {
        null => ServiceStatus.notInstalled,
        serviceStopped => ServiceStatus.stopped,
        serviceStartPending => ServiceStatus.startPending,
        serviceStopPending => ServiceStatus.stopPending,
        // Running, and the states a control request is pending in.
        _ => ServiceStatus.running,
      };

  @override
  Future<void> install(InstallLayout layout) => _run(layout, 'install');

  @override
  Future<void> uninstall(InstallLayout layout) => _run(layout, 'uninstall');

  @override
  Future<void> start(InstallLayout layout) => _run(layout, 'start');

  @override
  Future<void> stop(InstallLayout layout) => _run(layout, 'stop');

  Future<void> _run(InstallLayout layout, String command) async {
    final ProcessResult result;
    try {
      result = await Process.run(layout.winswExecutable, [command]);
    } on ProcessException catch (e) {
      throw YaguraException(
        'service_command_failed',
        'cannot run ${layout.winswExecutable} $command: ${e.message}',
      );
    }
    if (result.exitCode != 0) {
      throw YaguraException(
        'service_command_failed',
        '${layout.winswExecutable} $command exited ${result.exitCode}: '
            '${'${result.stdout}${result.stderr}'.trim()}',
      );
    }
  }
}
