import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../platform/win32_security.dart' show Win32Error;
import '../platform/win32_service.dart';
import 'install_layout.dart';
import 'winsw_config.dart';

/// What the service control manager says about a service.
enum ServiceStatus { notInstalled, stopped, startPending, stopPending, running }

/// The service control manager and the WinSW wrapper (ADR 0012). The seam
/// between the install logic and the machine: tests use a fake, and only the
/// `elevated` rows use [WinswServiceControl].
abstract interface class ServiceControl {
  /// The state of the service called [serviceName].
  ServiceStatus status(String serviceName);

  /// The names of the registered services that are a Yagura installation
  /// (a WinSW wrapper whose configuration `yagurad` wrote), under any name.
  /// One Yagura service runs per host, so `service install` refuses a new
  /// name while another is registered.
  Future<List<String>> yaguraServices();

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
  Future<List<String>> yaguraServices() async {
    try {
      return yaguraServiceNames(listServiceImages());
    } on Win32Error catch (e) {
      // Fail closed: without the list a second service cannot be ruled out.
      throw YaguraException(
        'service_command_failed',
        'cannot list the services: $e',
      );
    }
  }

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

/// The names among [services] (as the service manager lists them) that are a
/// Yagura installation: the image is a wrapper `<root>\<name>.exe` beside a
/// `<name>.xml` that `yagurad` wrote.
List<String> yaguraServiceNames(Iterable<ServiceImage> services) {
  final names = <String>[];
  for (final (:name, :imagePath) in services) {
    var image = imagePath.trim();
    if (image.startsWith('"')) {
      final end = image.indexOf('"', 1);
      if (end < 0) continue;
      image = image.substring(1, end);
    } else if (image.toLowerCase().contains('.exe')) {
      image = image.substring(0, image.toLowerCase().indexOf('.exe') + 4);
    }
    if (p.extension(image).toLowerCase() != '.exe') continue;
    final config = File(p.setExtension(image, '.xml'));
    try {
      if (!config.existsSync()) continue;
      final layout = InstallLayout(
        root: p.dirname(image),
        serviceName: p.basenameWithoutExtension(image),
      );
      if (ServiceConfig.parse(config.readAsStringSync(), layout) != null) {
        names.add(name);
      }
    } on FileSystemException {
      continue;
    }
  }
  return names;
}
