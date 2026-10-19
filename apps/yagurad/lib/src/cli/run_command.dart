import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../admin/admin_transport.dart';
import '../admin/named_pipe.dart';
import '../api/api_server.dart';
import '../api/bind_address.dart';
import '../errors.dart';
import 'admin_commands.dart';
import 'service_command.dart';
import '../host/daemon.dart';
import '../host/data_dir_protector.dart';
import '../host/data_directory.dart';
import '../instances/instance_acls.dart';
import '../host/secret_store.dart';
import '../platform/win32_security.dart';
import '../process/launcher_modes.dart';
import '../platform/acl_writer.dart';
import '../process/process.dart';
import '../process/process_verifier.dart';
import '../service/install_layout.dart';
import '../service/service_accounts.dart';
import '../service/version_sweeper.dart';
import '../steam/steam_process.dart';
import '../steam/steamcmd_service.dart';

/// The warning dev mode prints (`daemon-security` spec).
const devModeWarning = 'DEV MODE: unauthenticated, localhost only';

/// The SID of the LocalSystem account, whose token service mode requires.
const localSystemSid = 'S-1-5-18';

/// Exit code of a failed start.
const exitFailure = 1;

/// Exit code of a command line the daemon cannot read, or a mode this
/// version does not have.
const exitUsage = 64;

/// What the daemon needs from its surroundings; tests replace it.
class CliEnvironment {
  const CliEnvironment({
    required this.out,
    required this.err,
    this.stop,
    this.onListening,
    this.processHost,
    this.lookup = InternetAddress.lookup,
    this.isLocalSystem,
    this.secretProtector,
    this.adminConnector,
    this.adminListener,
    this.service = const ServiceEnvironment(),
  });

  final StringSink out;
  final StringSink err;

  /// Completes when the daemon should stop; defaults to SIGINT / SIGTERM.
  final Future<void>? stop;

  /// Called with the bound address once the listener is open.
  final void Function(InternetAddress address, int port)? onListening;

  /// Defaults to the Windows process host on Windows and to a host that
  /// cannot launch servers elsewhere (the Linux path is M5).
  final ProcessHost? processHost;

  final Future<List<InternetAddress>> Function(String host) lookup;

  /// Whether the process runs as LocalSystem; a seam for tests.
  final bool Function()? isLocalSystem;

  /// Defaults to DPAPI on Windows; a seam for tests.
  final SecretProtector? secretProtector;

  /// How the host commands reach the daemon; defaults to the admin pipe.
  final AdminConnector? adminConnector;

  /// Opens the admin channel of a service-mode daemon; defaults to the admin
  /// pipe on Windows. A seam for tests.
  final AdminListener Function()? adminListener;

  /// The machine parts of `service install|...`; a seam for tests.
  final ServiceEnvironment service;
}

/// Runs the `yagurad` command line. Returns the process exit code.
Future<int> runCli(List<String> arguments, CliEnvironment env) async {
  if (arguments.isEmpty || arguments.first.startsWith('-')) {
    env.err.writeln(
      'usage: yagurad run [--console] [--dev | --service] [--bind host:port] '
      '[--data-dir path]\n'
      '       yagurad service install|configure|uninstall|status',
    );
    return exitUsage;
  }
  final mode = arguments.first;
  switch (mode) {
    case 'run':
      return _run(arguments.skip(1).toList(), env);
    case 'launch' || 'relay' || 'signal':
      return _helper(mode, arguments.skip(1).toList(), env);
    case 'service':
      return _service(arguments.skip(1).toList(), env);
    case 'pair' || 'devices' || 'status' || 'roots':
      return _host(mode, arguments.skip(1).toList(), env);
    default:
      env.err.writeln('yagurad: unknown mode "$mode"');
      return exitUsage;
  }
}

Future<int> _service(List<String> arguments, CliEnvironment env) {
  if (env.service.control == null && !Platform.isWindows) {
    env.err.writeln(
      'yagurad: the "service" command needs Windows (the Linux path is M5)',
    );
    return Future.value(exitUsage);
  }
  return runServiceCommand(
    arguments,
    out: env.out,
    err: env.err,
    adminConnector: env.adminConnector,
    service: env.service,
  );
}

/// The version sweeper of a daemon that runs from an installed version
/// directory; null for a dev build.
VersionSweeper? _versionSweeper(String? serviceName) {
  final installed = InstallLayout.containing(Platform.resolvedExecutable);
  if (installed == null) return null;
  // The service passes its name when it is not the default one.
  final layout = serviceName == null
      ? installed.$1
      : InstallLayout(root: installed.$1.root, serviceName: serviceName);
  return VersionSweeper(layout: layout, currentVersion: installed.$2);
}

/// The host commands (design D5): they reach the running service over the
/// admin channel.
Future<int> _host(String command, List<String> arguments, CliEnvironment env) {
  final connector = env.adminConnector;
  if (connector == null && !Platform.isWindows) {
    env.err.writeln(
      'yagurad: the "$command" command needs the Windows admin channel '
      '(the Linux path is M5)',
    );
    return Future.value(exitUsage);
  }
  return runAdminCommand(
    command,
    arguments,
    connector: connector ?? NamedPipeConnector(),
    out: env.out,
    err: env.err,
  );
}

/// The `launch`, `relay` and `signal` modes of the process model (design D2).
Future<int> _helper(
  String mode,
  List<String> arguments,
  CliEnvironment env,
) async {
  if (!Platform.isWindows) {
    env.err.writeln(
      'yagurad: the "$mode" mode needs the Windows process host '
      '(the Linux path is M5)',
    );
    return exitUsage;
  }
  final parser = ArgParser()
    ..addOption('run-dir')
    ..addOption('console-of')
    ..addOption('created')
    // The account credentials come on standard input, one JSON line.
    ..addFlag('as-account', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    env.err.writeln('yagurad: ${e.message}');
    return exitUsage;
  }
  final runDirectory = args['run-dir'] as String?;
  switch (mode) {
    case 'launch' when runDirectory != null:
      AccountCredentials? credentials;
      if (args['as-account'] as bool) {
        // Without credentials the relay would start as this process's own
        // account (LocalSystem under the service): never fall back to that.
        credentials = AccountCredentials.decode(stdin.readLineSync());
        if (credentials == null) {
          env.err.writeln('yagurad: --as-account needs credentials on stdin');
          return exitUsage;
        }
      }
      return runLaunchMode(
        runDirectory,
        env.out,
        env.err,
        credentials: credentials,
      );
    case 'relay' when runDirectory != null:
      return runRelayMode(runDirectory, env.err);
    case 'signal'
        when int.tryParse(args['console-of'] as String? ?? '') != null:
      return runSignalMode(
        int.parse(args['console-of'] as String),
        created: int.tryParse(args['created'] as String? ?? ''),
      );
  }
  env.err.writeln(
    'usage: yagurad $mode '
    '${mode == 'signal' ? '--console-of <pid> [--created <filetime>]' : '--run-dir <dir>'}',
  );
  return exitUsage;
}

Future<int> _run(List<String> arguments, CliEnvironment env) async {
  final parser = ArgParser()
    // Runs in this console as the current user (design D2).
    ..addFlag('console', negatable: false)
    ..addFlag('dev', negatable: false, help: 'Serve plaintext on loopback.')
    // What the Windows service passes (design D6); with the LocalSystem token
    // it serves mutual TLS.
    ..addFlag(
      'service',
      negatable: false,
      help: 'Serve mutual TLS; needs the LocalSystem account.',
    )
    ..addOption('bind')
    ..addOption('data-dir')
    // What a service other than the default one passes (design D6).
    ..addOption('service-name');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    env.err.writeln('yagurad: ${e.message}');
    return exitUsage;
  }
  final dev = args['dev'] as bool;
  if (dev && (args['service'] as bool)) {
    env.err.writeln('yagurad: --dev and --service exclude each other');
    return exitUsage;
  }

  // Service mode is `--service` as LocalSystem (design D5, D6): the flag
  // turns on the service-only paths, and the admin channel that the CLI
  // trusts is served by that account only. Neither alone is enough.
  if (!dev &&
      !((args['service'] as bool) &&
          (env.isLocalSystem ?? _runsAsLocalSystem)())) {
    return _fail(
      env,
      YaguraException(
        'service_mode_required',
        'without --dev the daemon runs as the Windows service (`run --service` as '
            'LocalSystem); start it with `yagurad service install`, or use --dev for the '
            'unauthenticated loopback listener',
      ),
    );
  }

  final BindAddress bind;
  try {
    bind = dev
        ? await parseDevBind(
            (args['bind'] as String?) ?? defaultDevBind,
            lookup: env.lookup,
          )
        : await parseServiceBind(
            (args['bind'] as String?) ?? defaultServiceBind,
            lookup: env.lookup,
          );
  } on YaguraException catch (e) {
    return _fail(env, e);
  }

  final dataDirectory = (args['data-dir'] as String?) ?? defaultDataDirectory();
  // The service accounts, the data-directory protection and the ACLs are the
  // real machine's: a test that fakes the LocalSystem check does not run as
  // LocalSystem and cannot use them.
  final managed = !dev && Platform.isWindows && env.isLocalSystem == null;
  ServiceAccounts? accounts;
  final Daemon daemon;
  try {
    daemon = await Daemon.start(
      DaemonConfig(
        dataDirectory: dataDirectory,
        apiPort: bind.port,
        processHost:
            env.processHost ??
            (managed
                ? WindowsProcessHost(
                    helperExecutable: Platform.resolvedExecutable,
                    account: ServerAccount(
                      name: gameServerAccount,
                      password: () => accounts?.passwordOf(gameServerAccount),
                    ),
                    verifier: ProcessVerifier(
                      accountSid: () =>
                          const WindowsAccountSids().sidOf(gameServerAccount),
                    ),
                  )
                : null),
        steam: SteamCmdService(
          steamcmdRoot: p.join(dataDirectory, 'steamcmd'),
          launcher: managed
              ? JobObjectLauncher(
                  account: SteamAccount(
                    name: steamAccount,
                    password: () => accounts?.passwordOf(steamAccount),
                  ),
                )
              : null,
          unpackThroughLauncher: managed,
        ),
        dataDirProtector: managed
            ? AclDataDirProtector(writer: const WindowsAclWriter())
            : null,
        serviceAccounts: managed
            ? (secrets) => accounts = HostServiceAccounts(
                backend: const WindowsAccountBackend(),
                secrets: secrets,
              )
            : null,
        instanceAcls: managed
            ? HostInstanceAcls(const WindowsAccountSids())
            : null,
        serviceMode: !dev,
        versionSweeper: dev
            ? null
            : _versionSweeper(args['service-name'] as String?),
        secretProtector: env.secretProtector,
        adminListener: dev
            ? null
            : env.adminListener ??
                  (Platform.isWindows ? NamedPipeListener.new : null),
        aclWriter: dev || !Platform.isWindows ? null : const WindowsAclWriter(),
        accountSids: dev || !Platform.isWindows
            ? null
            : const WindowsAccountSids(),
      ),
    );
  } on YaguraException catch (e) {
    return _fail(env, e);
  }

  final ApiServer server;
  try {
    void log(String line) => env.err.writeln('yagurad: $line');
    server = dev
        ? await ApiServer.serveDev(
            daemon,
            address: bind.address,
            port: bind.port,
            logSink: log,
          )
        : await ApiServer.serveSecure(
            daemon,
            address: bind.address,
            port: bind.port,
            logSink: log,
          );
  } on SocketException catch (e) {
    await daemon.close();
    env.err.writeln('yagurad: cannot listen on $bind: ${e.message}');
    return exitFailure;
  }

  if (dev) {
    env.err.writeln(devModeWarning);
  } else {
    // The administrator compares it with the pairing string.
    env.err.writeln('yagurad: ${daemon.security!.identity.fingerprintLine}');
  }
  env.out.writeln(
    'yagurad: listening on ${bind.address.address}:${server.port}',
  );
  env.onListening?.call(bind.address, server.port);

  var code = 0;
  await Future.any<void>([
    env.stop ?? _signal(),
    // The certificate rotation lost its listener: exit, so the service
    // manager restarts the daemon (design D4).
    server.failed.catchError((Object e) {
      env.err.writeln('yagurad: $e');
      code = exitFailure;
    }),
  ]);
  await server.close();
  await daemon.close();
  return code;
}

bool _runsAsLocalSystem() {
  if (!Platform.isWindows) return false;
  try {
    return currentUserSid() == localSystemSid;
  } on Object {
    return false;
  }
}

int _fail(CliEnvironment env, YaguraException error) {
  env.err.writeln('yagurad: ${error.reason}: ${error.message}');
  return exitFailure;
}

Future<void> _signal() {
  final done = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  void finish(ProcessSignal _) {
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    if (!done.isCompleted) done.complete();
  }

  subscriptions.add(ProcessSignal.sigint.watch().listen(finish));
  if (!Platform.isWindows) {
    subscriptions.add(ProcessSignal.sigterm.watch().listen(finish));
  }
  return done.future;
}
