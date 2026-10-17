// AOT bundle smoke (task 9.4): builds `yagurad` with `dart build cli`, copies
// the bundle outside the repository and drives the copy end to end.
//
// What it proves, from a directory unrelated to the source tree and the pub
// cache: the quickjs-ng native asset loads from the bundle (a `hooks.js`
// `onPreStart` runs), and the bundle's own `launch`, `relay` and `signal`
// modes (resolved through `Platform.resolvedExecutable`) start, re-attach and
// gracefully stop the `fake_server` fixture.
//
// Usage, from the repository root:
//   dart run tool/bundle_smoke.dart [--bundle <dir>] [--work <dir>]
//
// --bundle  an already built bundle directory (the one holding bin/ and lib/)
// --work    the directory the bundle is copied to (default: a new temp dir)
//
// On Windows runners whose step job forbids breakaway, run it through
// `tool/ci/outside-job.ps1` (docs/spikes/m1-process-model.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:yagura_proto/yagura_proto.dart' as pb;

const _hookArgument = '--bundle-smoke-hook-ran';
const _pluginId = 'smoke';
const _serverName = 'smoke_server.exe';

var _failures = 0;

void _check(String name, bool ok, [String detail = '']) {
  if (!ok) _failures++;
  stdout.writeln(
    '${ok ? 'PASS' : 'FAIL'}: $name${detail.isEmpty ? '' : ' ($detail)'}',
  );
}

Never _abort(String message) => throw _SmokeAbort(message);

class _SmokeAbort implements Exception {
  _SmokeAbort(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('bundle', help: 'An already built bundle directory.')
    ..addOption('work', help: 'Directory to copy the bundle to.');
  final args = parser.parse(arguments);
  if (!Platform.isWindows) {
    stderr.writeln('bundle_smoke: needs Windows (the Linux path is M5)');
    exitCode = 64;
    return;
  }

  final repo = _repoRoot();
  final ownWork = args['work'] == null;
  final given = ownWork
      ? Directory.systemTemp.createTempSync('yagura_bundle_smoke_').path
      : p.absolute(args['work'] as String);
  Directory(given).createSync(recursive: true);
  // The final path, as the relay reports its own: the CI runner's temp
  // directory is spelled with an 8.3 short name (`C:\Users\RUNNER~1\...`).
  final work = Directory(given).resolveSymbolicLinksSync();
  if (p.isWithin(repo, work) || p.equals(repo, work)) {
    stderr.writeln('bundle_smoke: the work directory must be outside $repo');
    exitCode = 64;
    return;
  }
  stdout.writeln('work directory: $work');

  final smoke = _Smoke(repo, work);
  try {
    await smoke.run(args['bundle'] as String?);
  } on _SmokeAbort catch (e) {
    _check('smoke run', false, e.message);
  } on Object catch (e, st) {
    _check('smoke run', false, '$e\n$st');
  } finally {
    await smoke.cleanUp();
  }
  if (_failures == 0 && ownWork) {
    try {
      Directory(work).deleteSync(recursive: true);
    } on FileSystemException {
      stdout.writeln('note: could not delete $work');
    }
  } else if (_failures != 0) {
    stdout.writeln('kept $work for inspection');
  }
  stdout.writeln(_failures == 0 ? 'RESULT: PASS' : 'RESULT: FAIL ($_failures)');
  exitCode = _failures == 0 ? 0 : 1;
}

String _repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (File(p.join(dir.path, 'apps', 'yagurad', 'pubspec.yaml'))
        .existsSync()) {
      return dir.path;
    }
    if (dir.parent.path == dir.path) {
      stderr.writeln('bundle_smoke: run it from the repository root');
      exit(64);
    }
    dir = dir.parent;
  }
}

/// A daemon child process and the channel to it.
class _Daemon {
  _Daemon(this.process, this.port, this.log);

  final Process process;
  final int port;
  final StringBuffer log;
  ClientChannel? channel;
}

class _Smoke {
  _Smoke(this.repo, this.work)
    : data = p.join(work, 'data'),
      bundleCopy = p.join(work, 'bundle');

  final String repo;
  final String work;
  final String data;
  final String bundleCopy;
  _Daemon? _daemon;
  final _pids = <int>{};

  String get yagurad => p.join(bundleCopy, 'bin', 'yagurad.exe');

  Future<void> run(String? bundleArg) async {
    final String built = bundleArg != null
        ? p.absolute(bundleArg)
        : await _build();
    if (!File(p.join(built, 'bin', 'yagurad.exe')).existsSync()) {
      _abort('no bin/yagurad.exe in bundle $built');
    }
    _copyDirectory(built, bundleCopy);
    _check('bundle copied outside the repository', File(yagurad).existsSync());

    final fakeServer = p.join(work, 'fake_server.exe');
    await _compile(
      p.join(
        'apps',
        'yagurad',
        'test',
        'fixtures',
        'fake_server',
        'fake_server.dart',
      ),
      fakeServer,
    );
    _prepareData();
    await _compile(
      p.join(
        'apps',
        'yagurad',
        'test',
        'fixtures',
        'fake_steamcmd',
        'fake_steamcmd.dart',
      ),
      p.join(data, 'steamcmd', 'anonymous', 'steamcmd.exe'),
    );
    _copyDirectory(
      p.join(
        repo,
        'apps',
        'yagurad',
        'test',
        'fixtures',
        'fake_steamcmd',
        'output',
      ),
      p.join(data, 'steamcmd', 'anonymous', 'output'),
    );

    // ---- first daemon: install, start -----------------------------------
    var daemon = await _startDaemon('first');
    var instances = pb.InstancesClient(daemon.channel!);
    final operations = pb.OperationsClient(daemon.channel!);

    final plugins = await pb.PluginsClient(daemon.channel!)
        .listPlugins(pb.ListPluginsRequest());
    _check(
      'daemon from the bundle loads the test plugin',
      plugins.plugins.any((x) => x.id == _pluginId),
      plugins.plugins.map((x) => x.id).join(','),
    );

    var instance = await instances.createInstance(
      pb.CreateInstanceRequest(
        pluginId: _pluginId,
        name: 'Smoke',
        settings: pb.JsonDocument(json: '{"serverName":"Smoke"}'),
      ),
    );
    final id = instance.id;
    await _expectOperation(
      operations,
      await instances.install(pb.LifecycleRequest(instanceId: id)),
      'install through the bundle (fake SteamCMD)',
    );
    instance = await instances.getInstance(
      pb.GetInstanceRequest(instanceId: id),
    );
    final serverDir = Directory(p.join(instance.directory, 'server'))
      ..createSync(recursive: true);
    File(fakeServer).copySync(p.join(serverDir.path, _serverName));
    final stateDir = p.join(instance.directory, 'state');

    await _expectOperation(
      operations,
      await instances.start(pb.LifecycleRequest(instanceId: id)),
      'start: onPreStart hook runs (quickjs-ng from the bundle), launch and relay start the server',
    );
    instance = await _waitState(
      instances,
      id,
      pb.InstanceState.INSTANCE_STATE_RUNNING,
    );
    _check(
      'instance is running',
      instance.state == pb.InstanceState.INSTANCE_STATE_RUNNING,
    );
    final serverPid = instance.pid;
    _pids.add(serverPid);

    final argsFile = File(p.join(stateDir, 'args.txt'));
    await _waitFor(() => argsFile.existsSync(), 'fake_server args.txt');
    final serverArgs = argsFile.readAsStringSync().split('\n');
    _check(
      'hook argument reached the fake server',
      serverArgs.contains(_hookArgument),
      serverArgs.join(' '),
    );
    final recordedPid = int.tryParse(
      File(p.join(stateDir, 'pid.txt')).readAsStringSync(),
    );
    _check(
      'API pid is the fake server pid',
      recordedPid == serverPid,
      '$recordedPid vs $serverPid',
    );
    _check('server process is alive', _alive(serverPid));

    final relayJson = _relayJson(instance.directory);
    final relayExe = relayJson?['relay_executable'] as String?;
    final relayPid = relayJson?['relay_pid'] as int?;
    if (relayPid != null) _pids.add(relayPid);
    _check(
      'relay is the copied bundle executable',
      relayExe != null &&
          p.equals(relayExe, yagurad) &&
          p.isWithin(work, relayExe),
      '$relayExe',
    );
    _check(
      'relay.json names this server',
      relayJson?['server_pid'] == serverPid,
      '${relayJson?['server_pid']}',
    );
    _check('relay process is alive', relayPid != null && _alive(relayPid));
    _check(
      'relay is neither in the repository nor in the pub cache',
      relayExe != null &&
          !p.isWithin(repo, relayExe) &&
          !relayExe.contains('.pub-cache'),
    );

    // ---- hard kill and re-attach ----------------------------------------
    await _killDaemon(daemon);
    _check(
      'server and relay survive the daemon kill',
      _alive(serverPid) && (relayPid != null && _alive(relayPid)),
    );

    daemon = await _startDaemon('second');
    instances = pb.InstancesClient(daemon.channel!);
    final opsAgain = pb.OperationsClient(daemon.channel!);
    instance = await _waitState(
      instances,
      id,
      pb.InstanceState.INSTANCE_STATE_RUNNING,
    );
    _check(
      'restarted bundle daemon re-attaches the running instance',
      instance.state == pb.InstanceState.INSTANCE_STATE_RUNNING &&
          instance.pid == serverPid,
      'state=${instance.state.name} pid=${instance.pid} expected $serverPid',
    );

    // ---- stop through the signal mode ------------------------------------
    final stop = await instances.stop(pb.LifecycleRequest(instanceId: id));
    final stopped = await _expectOperation(
      opsAgain,
      stop,
      'stop through the API',
    );
    _check(
      'stop was graceful (bundle signal mode delivered Ctrl+C)',
      stopped.resultReason == 'stopped_by:graceful',
      stopped.resultReason,
    );
    _check(
      'fake server saw Ctrl+C',
      File(p.join(stateDir, 'ctrlc.txt')).existsSync(),
    );
    _check(
      'fake server saved before exiting',
      File(p.join(stateDir, 'saved.txt')).existsSync(),
    );
    await _waitFor(
      () => !_alive(serverPid),
      'server exit',
      const Duration(seconds: 10),
    );
    _check('server process exited', !_alive(serverPid));
    instance = await instances.getInstance(
      pb.GetInstanceRequest(instanceId: id),
    );
    _check(
      'instance is stopped',
      instance.state == pb.InstanceState.INSTANCE_STATE_STOPPED,
      instance.state.name,
    );
  }

  // ---- building and preparing ---------------------------------------------

  Future<String> _build() async {
    final out = p.join(repo, '.dart_tool', 'bundle_smoke', 'build');
    final outDir = Directory(out);
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    stdout.writeln('building yagurad with `dart build cli` ...');
    final result = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '-t',
      p.join('bin', 'yagurad.dart'),
      '-o',
      out,
    ], workingDirectory: p.join(repo, 'apps', 'yagurad'));
    if (result.exitCode != 0) {
      _abort('dart build cli failed:\n${result.stdout}\n${result.stderr}');
    }
    return p.join(out, 'bundle');
  }

  Future<void> _compile(String source, String output) async {
    Directory(p.dirname(output)).createSync(recursive: true);
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      source,
      '-o',
      output,
    ], workingDirectory: repo);
    if (result.exitCode != 0) {
      _abort('compiling $source failed:\n${result.stdout}\n${result.stderr}');
    }
  }

  void _prepareData() {
    final plugin = Directory(p.join(data, 'plugins', _pluginId))
      ..createSync(recursive: true);
    File(p.join(plugin.path, 'plugin.yaml')).writeAsStringSync('''
manifest_version: 1
id: $_pluginId
name: Bundle smoke server
version: 0.1.0
description: The fake_server fixture, for the AOT bundle smoke.

steam:
  app_id: 896660
  login: anonymous
  size_hint_bytes: 1000

executable:
  windows: $_serverName
  linux: smoke_server

ports:
  - name: game
    default: 2456
    protocol: tcp
    purpose: game

settings:
  serverName:
    type: string
    label: Server name
    default: Smoke
    min: 1
    max: 64

launch:
  args:
    - --state-dir
    - "{{instance}}/state"

stop:
  strategy: signal
  grace_seconds: 10

health:
  type: process
  start_timeout_seconds: 30

logs:
  - name: server
    stdout: true
    encoding: utf-8

data_paths:
  - "state/"
''');
    File(p.join(plugin.path, 'hooks.js')).writeAsStringSync(
      'exports.onPreStart = () => ({args: ["$_hookArgument"]});\n',
    );
    // SteamCMD is pre-seeded (a fake) so Install makes no network call.
    final steam = Directory(p.join(data, 'steamcmd', 'anonymous'))
      ..createSync(recursive: true);
    File(p.join(steam.path, '.yagura-ready')).writeAsStringSync('');
  }

  // ---- the daemon ------------------------------------------------------------

  Future<_Daemon> _startDaemon(String label) async {
    final port = await _freePort();
    final log = StringBuffer();
    final process = await Process.start(yagurad, [
      'run',
      '--dev',
      '--data-dir',
      data,
      '--bind',
      '127.0.0.1:$port',
    ], workingDirectory: work);
    final listening = Completer<void>();
    process.stdout.transform(utf8.decoder).listen((text) {
      log.write(text);
      if (text.contains('listening on') && !listening.isCompleted) {
        listening.complete();
      }
    });
    process.stderr.transform(utf8.decoder).listen(log.write);
    unawaited(
      process.exitCode.then((code) {
        if (!listening.isCompleted) {
          listening.completeError(
            _SmokeAbort('daemon exited with $code:\n$log'),
          );
        }
      }),
    );
    final daemon = _Daemon(process, port, log);
    _daemon = daemon;
    _pids.add(process.pid);
    try {
      await listening.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _abort('daemon ($label) did not listen within 30 s:\n$log');
    }
    daemon.channel = ClientChannel(
      '127.0.0.1',
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _check(
      'daemon ($label) started from the copied bundle',
      true,
      'pid ${process.pid}, port $port',
    );
    return daemon;
  }

  Future<void> _killDaemon(_Daemon daemon) async {
    await daemon.channel?.terminate();
    daemon.process.kill(ProcessSignal.sigkill);
    await daemon.process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => -1,
    );
    _check('daemon killed', !_alive(daemon.process.pid));
  }

  Future<void> cleanUp() async {
    final daemon = _daemon;
    if (daemon != null) {
      await daemon.channel?.terminate();
      daemon.process.kill(ProcessSignal.sigkill);
      if (_failures != 0) {
        stdout.writeln('--- daemon output ---\n${daemon.log}');
      }
    }
    final dataDir = Directory(data);
    if (dataDir.existsSync()) {
      for (final file in dataDir.listSync(recursive: true).whereType<File>()) {
        if (p.basename(file.path) != 'relay.json') continue;
        final json = _readJson(file.path);
        for (final key in ['relay_pid', 'server_pid']) {
          if (json?[key] case final int pid) _pids.add(pid);
        }
      }
    }
    for (final pid in _pids) {
      if (_alive(pid)) Process.killPid(pid);
    }
    for (var i = 0; i < 50 && _pids.any(_alive); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  // ---- API helpers -----------------------------------------------------------

  Future<pb.Operation> _expectOperation(
    pb.OperationsClient operations,
    pb.Operation started,
    String name,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    var op = started;
    while (true) {
      switch (op.status) {
        case pb.OperationStatus.OPERATION_STATUS_SUCCEEDED:
          _check(name, true, op.resultReason);
          return op;
        case pb.OperationStatus.OPERATION_STATUS_FAILED ||
            pb.OperationStatus.OPERATION_STATUS_CANCELLED ||
            pb.OperationStatus.OPERATION_STATUS_INTERRUPTED:
          _check(
            name,
            false,
            '${op.status.name}: ${op.resultReason} ${op.resultMessage}',
          );
          _abort('operation "$name" did not succeed');
        default:
      }
      if (DateTime.now().isAfter(deadline)) {
        _abort('operation "$name" timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      op = await operations.getOperation(
        pb.GetOperationRequest(operationId: op.id),
      );
    }
  }

  Future<pb.Instance> _waitState(
    pb.InstancesClient instances,
    String id,
    pb.InstanceState want,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      final instance = await instances.getInstance(
        pb.GetInstanceRequest(instanceId: id),
      );
      if (instance.state == want) return instance;
      if (DateTime.now().isAfter(deadline)) {
        _check(
          'wait for ${want.name}',
          false,
          'stuck in ${instance.state.name} ${instance.stateReason}',
        );
        _abort('instance did not reach ${want.name}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  // ---- small helpers ---------------------------------------------------------

  Map<String, Object?>? _relayJson(String instanceDirectory) {
    final runs = Directory(p.join(instanceDirectory, '.yagura', 'run'));
    if (!runs.existsSync()) return null;
    final dirs = runs.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final dir in dirs.reversed) {
      final json = _readJson(p.join(dir.path, 'relay.json'));
      if (json != null && json['server_pid'] != null) return json;
    }
    return null;
  }
}

Map<String, Object?>? _readJson(String path) {
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    return decoded is Map<String, Object?> ? decoded : null;
  } on Object {
    return null;
  }
}

Future<void> _waitFor(
  bool Function() condition,
  String what, [
  Duration timeout = const Duration(seconds: 30),
]) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) _abort('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

bool _alive(int pid) {
  final result = Process.runSync('tasklist', [
    '/FI',
    'PID eq $pid',
    '/NH',
    '/FO',
    'CSV',
  ]);
  return (result.stdout as String).contains('"$pid"');
}

void _copyDirectory(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final entity in Directory(
    from,
  ).listSync(recursive: true, followLinks: false)) {
    final target = p.join(to, p.relative(entity.path, from: from));
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(target)).createSync(recursive: true);
      entity.copySync(target);
    }
  }
}
