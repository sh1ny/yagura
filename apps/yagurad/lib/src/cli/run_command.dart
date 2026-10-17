import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../api/api_server.dart';
import '../api/bind_address.dart';
import '../errors.dart';
import '../host/daemon.dart';
import '../process/launcher_modes.dart';
import '../process/process.dart';
import '../steam/steamcmd_service.dart';

/// The warning dev mode prints (`daemon-security` spec).
const devModeWarning = 'DEV MODE: unauthenticated, localhost only';

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
}

/// Runs the `yagurad` command line. Returns the process exit code.
Future<int> runCli(List<String> arguments, CliEnvironment env) async {
  if (arguments.isEmpty || arguments.first.startsWith('-')) {
    env.err.writeln(
      'usage: yagurad run [--console] --dev [--bind host:port] '
      '[--data-dir path]',
    );
    return exitUsage;
  }
  final mode = arguments.first;
  switch (mode) {
    case 'run':
      return _run(arguments.skip(1).toList(), env);
    case 'launch' || 'relay' || 'signal':
      return _helper(mode, arguments.skip(1).toList(), env);
    default:
      env.err.writeln('yagurad: unknown mode "$mode"');
      return exitUsage;
  }
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
    ..addOption('console-of');
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
      return runLaunchMode(runDirectory, env.out, env.err);
    case 'relay' when runDirectory != null:
      return runRelayMode(runDirectory, env.err);
    case 'signal'
        when int.tryParse(args['console-of'] as String? ?? '') != null:
      return runSignalMode(int.parse(args['console-of'] as String));
  }
  env.err.writeln(
    'usage: yagurad $mode '
    '${mode == 'signal' ? '--console-of <pid>' : '--run-dir <dir>'}',
  );
  return exitUsage;
}

Future<int> _run(List<String> arguments, CliEnvironment env) async {
  final parser = ArgParser()
    // Runs in this console as the current user (design D2): the only mode
    // until the Windows service arrives in M2, so the flag changes nothing.
    ..addFlag('console', negatable: false)
    ..addFlag('dev', negatable: false, help: 'Serve plaintext on loopback.')
    ..addOption('bind', defaultsTo: defaultDevBind)
    ..addOption('data-dir');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    env.err.writeln('yagurad: ${e.message}');
    return exitUsage;
  }

  if (!(args['dev'] as bool)) {
    return _fail(
      env,
      YaguraException(
        'secure_mode_unavailable',
        'this version has no authenticated listener; start with --dev for the '
            'unauthenticated loopback listener',
      ),
    );
  }

  final BindAddress bind;
  try {
    bind = await parseDevBind(args['bind'] as String, lookup: env.lookup);
  } on YaguraException catch (e) {
    return _fail(env, e);
  }

  final dataDirectory = (args['data-dir'] as String?) ?? _defaultDataDir();
  final Daemon daemon;
  try {
    daemon = await Daemon.start(
      DaemonConfig(
        dataDirectory: dataDirectory,
        apiPort: bind.port,
        processHost: env.processHost,
        steam: SteamCmdService(steamcmdRoot: p.join(dataDirectory, 'steamcmd')),
      ),
    );
  } on YaguraException catch (e) {
    return _fail(env, e);
  }

  final ApiServer server;
  try {
    server = await ApiServer.serveDev(
      daemon,
      address: bind.address,
      port: bind.port,
      logSink: (line) => env.err.writeln('yagurad: $line'),
    );
  } on SocketException catch (e) {
    await daemon.close();
    env.err.writeln('yagurad: cannot listen on $bind: ${e.message}');
    return exitFailure;
  }

  env.err.writeln(devModeWarning);
  env.out.writeln(
    'yagurad: listening on ${bind.address.address}:${server.port}',
  );
  env.onListening?.call(bind.address, server.port);

  await (env.stop ?? _signal());
  await server.close();
  await daemon.close();
  return 0;
}

int _fail(CliEnvironment env, YaguraException error) {
  env.err.writeln('yagurad: ${error.reason}: ${error.message}');
  return exitFailure;
}

/// The data directory from host-service "Data directory layout".
String _defaultDataDir() {
  if (Platform.isWindows) {
    final base = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    return p.join(base, 'Yagura');
  }
  return '/var/lib/yagura';
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
