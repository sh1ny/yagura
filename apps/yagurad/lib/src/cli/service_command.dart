import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../admin/admin_client.dart';
import '../admin/admin_transport.dart';
import '../admin/named_pipe.dart';
import '../errors.dart';
import '../host/data_directory.dart';
import '../platform/win32_security.dart';
import '../service/account_purger.dart';
import '../service/bundle.dart';
import '../service/install_layout.dart';
import '../service/service_control.dart';
import '../service/service_installer.dart';
import '../service/winsw_config.dart';

const _usage = '''
usage: yagurad service install [--bind <address:port>] [--data-dir <path>]
       yagurad service configure --bind <address:port>
       yagurad service uninstall [--purge-accounts]
       yagurad service status
options for every subcommand (to run a second service beside the first):
       [--service-name <name>] [--install-dir <path>]''';

const _exitFailure = 1;
const _exitUsage = 64;

/// What the `service` commands need from the machine; tests replace the
/// parts that would touch the service control manager, the accounts or
/// `%ProgramFiles%`. A null part is the real one.
class ServiceEnvironment {
  const ServiceEnvironment({
    this.control,
    this.isElevated,
    this.bundle,
    this.admin,
    this.servers,
    this.purger,
    this.environment,
    this.readyTimeout,
    this.pollInterval,
    this.delay,
    this.now,
  });

  final ServiceControl? control;
  final bool Function()? isElevated;
  final Bundle? bundle;
  final AdminCall? admin;
  final ServerProbe? servers;
  final AccountPurger? purger;

  /// The process environment (`ProgramFiles`).
  final Map<String, String>? environment;
  final Duration? readyTimeout;
  final Duration? pollInterval;
  final Future<void> Function(Duration)? delay;
  final DateTime Function()? now;
}

/// `yagurad service install|configure|uninstall|status`. Returns the process
/// exit code.
Future<int> runServiceCommand(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
  AdminConnector? adminConnector,
  ServiceEnvironment service = const ServiceEnvironment(),
}) async {
  int usage([String? problem]) {
    if (problem != null) err.writeln('yagurad: $problem');
    err.writeln(_usage);
    return _exitUsage;
  }

  if (arguments.isEmpty) return usage();
  final command = arguments.first;
  final parser = ArgParser()
    ..addOption('service-name', defaultsTo: defaultServiceName)
    ..addOption('install-dir');
  switch (command) {
    case 'install':
      parser
        ..addOption('bind')
        ..addOption('data-dir');
    case 'configure':
      parser.addOption('bind');
    case 'uninstall':
      parser.addFlag('purge-accounts', negatable: false);
    case 'status':
      break;
    default:
      return usage('unknown service command "$command"');
  }
  final ArgResults args;
  try {
    args = parser.parse(arguments.skip(1));
  } on FormatException catch (e) {
    return usage(e.message);
  }
  if (args.rest.isNotEmpty) {
    return usage('unexpected argument "${args.rest.first}"');
  }
  final serviceName = args['service-name'] as String;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(serviceName)) {
    return usage('the service name "$serviceName" is not a plain name');
  }
  if (command == 'configure' && args['bind'] == null) {
    return usage('service configure needs --bind <address:port>');
  }

  try {
    final layout = (args['install-dir'] as String?) != null
        ? InstallLayout(
            root: p.normalize(p.absolute(args['install-dir'] as String)),
            serviceName: serviceName,
          )
        : InstallLayout.standard(
            serviceName: serviceName,
            environment: service.environment ?? Platform.environment,
          );
    final connector = adminConnector ?? NamedPipeConnector();
    final admin =
        service.admin ??
        (String name, [Map<String, Object?> arguments = const {}]) =>
            AdminClient(connector).call(name, arguments);
    // Where the data directory is, for the checks that read it: what the
    // installed configuration says, else the default.
    String dataDirectory() {
      final file = File(layout.configFile);
      final config = file.existsSync()
          ? ServiceConfig.parse(file.readAsStringSync(), layout)
          : null;
      return config?.dataDirectory ?? defaultDataDirectory();
    }

    final installer = ServiceInstaller(
      layout: layout,
      control: service.control ?? const WinswServiceControl(),
      bundle: service.bundle,
      loadBundle: Bundle.running,
      admin: admin,
      out: out,
      isElevated: service.isElevated ?? isElevated,
      servers:
          service.servers ??
          HostServerProbe(
            status: () => admin('status'),
            dataDirectory: dataDirectory,
          ),
      purger: service.purger ?? HostAccountPurger(dataDirectory: dataDirectory),
      readyTimeout: service.readyTimeout ?? const Duration(seconds: 60),
      pollInterval: service.pollInterval ?? const Duration(seconds: 1),
      delay: service.delay ?? (d) => Future<void>.delayed(d),
      now: service.now ?? DateTime.now,
    );
    switch (command) {
      case 'install':
        await installer.install(
          bind: args['bind'] as String?,
          dataDirectory: args['data-dir'] as String?,
        );
      case 'configure':
        await installer.configure(bind: args['bind'] as String);
      case 'uninstall':
        await installer.uninstall(
          purgeAccounts: args['purge-accounts'] as bool,
        );
      case 'status':
        await installer.status();
    }
    return 0;
  } on YaguraException catch (e) {
    err.writeln('yagurad: ${e.reason}: ${e.message}');
    return _exitFailure;
  }
}
