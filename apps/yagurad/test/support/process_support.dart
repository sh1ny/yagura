import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/secret_store.dart' show SecretProtector;
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/platform/job_restrictions.dart';
import 'package:yagurad/src/platform/win32.dart';
import 'package:yagurad/src/process/process.dart';

import 'daemon_support.dart';

/// Skip reason for tests that need the Windows process host (the Linux path
/// is M5). Tests that start real processes also carry `tags: ['windows']`.
final String? windowsOnly = Platform.isWindows
    ? null
    : 'needs the Windows process host (the Linux path is M5)';

/// Fails the running test at once, naming the restriction, when this process
/// cannot start a relay outside its job (spike 1.3: GitHub's Windows runner
/// puts every step in a job without breakaway). The CI job starts the process
/// tests through WMI, outside that job.
void requireBreakaway() {
  if (!Platform.isWindows) return;
  final why = breakawayRestriction();
  if (why != null) {
    fail(
      'The windows-tagged process tests cannot run here: $why. Run '
      '`dart test` outside the job (CI starts it through WMI, see '
      'docs/spikes/m1-process-model.md).',
    );
  }
}

/// Whether a process with [pid] is running (Windows).
bool processAlive(int pid) {
  final win32 = Win32.instance;
  final handle = win32.openProcess(
    Win32.processQueryLimitedInformation | Win32.synchronize,
    0,
    pid,
  );
  if (handle == 0) return false;
  try {
    return win32.waitForSingleObject(handle, 0) == Win32.waitTimeout;
  } finally {
    win32.closeHandle(handle);
  }
}

/// The executables the process tests run: `yagurad` (built with
/// `dart build cli`, because `dart compile exe` refuses packages with build
/// hooks) and the `fake_server` fixture.
class ProcessTools {
  const ProcessTools({required this.yagurad, required this.fakeServer});

  final String yagurad;
  final String fakeServer;
}

Future<ProcessTools>? _tools;

/// Builds the tools once per run and caches them in
/// `.dart_tool/yagurad_process_tools/<hash of the sources>/`; a later run
/// with unchanged sources reuses them. Test files run in parallel, so the
/// build holds a file lock.
Future<ProcessTools> processTools() => _tools ??= _buildTools();

Directory _packageRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          RegExp(r'^name: yagurad$', multiLine: true),
        )) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('the yagurad package root was not found');
    }
    dir = parent;
  }
}

String _sourceHash(Directory root) {
  // The daemon is compiled from the workspace: the resolved versions
  // (`pubspec.lock`), the workspace packages it depends on and the Dart SDK
  // that compiles it all end up in the executable, so all are key inputs.
  final workspace = root.parent.parent;
  final files = <File>[
    File(p.join(root.path, 'pubspec.yaml')),
    File(p.join(workspace.path, 'pubspec.lock')),
    for (final sub in ['lib', 'bin', p.join('test', 'fixtures', 'fake_server')])
      ...Directory(p.join(root.path, sub))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    for (final package in Directory(
      p.join(workspace.path, 'packages'),
    ).listSync().whereType<Directory>()) ...[
      File(p.join(package.path, 'pubspec.yaml')),
      for (final sub in ['lib', 'bin', 'hook', 'third_party'])
        if (Directory(p.join(package.path, sub)).existsSync())
          ...Directory(p.join(package.path, sub))
              .listSync(recursive: true)
              .whereType<File>(),
    ],
  ]..sort((a, b) => a.path.compareTo(b.path));
  final bytes = BytesBuilder(copy: false)..add(utf8.encode(Platform.version));
  for (final file in files) {
    bytes
      ..add(utf8.encode(p.relative(file.path, from: workspace.path)))
      ..add(file.readAsBytesSync());
  }
  return sha256.convert(bytes.takeBytes()).toString().substring(0, 16);
}

Future<ProcessTools> _buildTools() async {
  final root = _packageRoot();
  final cache = Directory(
    p.join(root.path, '.dart_tool', 'yagurad_process_tools'),
  )..createSync(recursive: true);
  final hash = _sourceHash(root);
  final out = p.join(cache.path, hash);
  final tools = ProcessTools(
    yagurad: p.join(out, 'yagurad', 'bundle', 'bin', 'yagurad.exe'),
    fakeServer: p.join(out, 'fake_server.exe'),
  );
  final done = File(p.join(out, 'complete'));

  final lock = File(p.join(cache.path, 'build.lock'))
      .openSync(mode: FileMode.write);
  lock.lockSync(FileLock.blockingExclusive);
  try {
    if (done.existsSync()) return tools;
    // Sources changed: drop the older builds.
    for (final old in cache.listSync().whereType<Directory>()) {
      if (p.basename(old.path) != hash) old.deleteSync(recursive: true);
    }
    Directory(out).createSync(recursive: true);
    final dart = Platform.resolvedExecutable;
    final fake = await Process.run(dart, [
      'compile',
      'exe',
      p.join('test', 'fixtures', 'fake_server', 'fake_server.dart'),
      '-o',
      tools.fakeServer,
    ], workingDirectory: root.path);
    if (fake.exitCode != 0) {
      fail('compiling fake_server failed:\n${fake.stdout}\n${fake.stderr}');
    }
    final helper = await Process.run(dart, [
      'build',
      'cli',
      '-t',
      p.join('bin', 'yagurad.dart'),
      '-o',
      p.join(out, 'yagurad'),
    ], workingDirectory: root.path);
    if (helper.exitCode != 0) {
      fail('building yagurad failed:\n${helper.stdout}\n${helper.stderr}');
    }
    // Run each new executable once, so an antivirus scan on its first
    // execution happens here and not inside a launch's 30 s wait (on the CI
    // runner the relay's first CreateProcess of fake_server took longer).
    await Process.run(tools.fakeServer, ['--exit-after-ms', '0']);
    await Process.run(tools.yagurad, const []);
    done.writeAsStringSync('ok');
    return tools;
  } finally {
    lock.unlockSync();
    lock.closeSync();
  }
}

/// A daemon wired to the real Windows process host and the `fake_server`
/// fixture, with every process it starts ended when the test ends.
class ProcessRig {
  ProcessRig._(this.env, this.tools);

  final TestEnv env;
  final ProcessTools tools;

  /// The host of the daemon started last.
  WindowsProcessHost? host;

  /// Fails at once when this process is in a job that forbids breakaway,
  /// builds (or reuses) the tools and installs the `valheim` plugin id with
  /// the `fake_server` as its server.
  ///
  /// [serverArgs] follow `--state-dir <instance>/state`; [health] is the body
  /// of the manifest's `health:` block.
  static Future<ProcessRig> create({
    List<String> serverArgs = const [],
    int graceSeconds = 5,
    String health = 'type: process\n  start_timeout_seconds: 30',
    Directory? parent,
  }) async {
    requireBreakaway();
    final tools = await processTools();
    final env = TestEnv(parent: parent);
    final rig = ProcessRig._(env, tools);
    addTearDown(rig._cleanup);
    rig._installPlugin(serverArgs, graceSeconds, health);
    return rig;
  }

  void _installPlugin(
    List<String> serverArgs,
    int graceSeconds,
    String health,
  ) {
    final dir = Directory(p.join(env.pluginsDir, 'valheim'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'plugin.yaml')).writeAsStringSync('''
manifest_version: 1
id: valheim
name: Fake server
version: 0.1.0
description: The fake_server test fixture.

steam:
  app_id: 896660
  login: anonymous
  size_hint_bytes: 1000

executable:
  windows: valheim_server.exe
  linux: valheim_server.x86_64

ports:
  - name: game
    default: 2456
    protocol: tcp
    purpose: game

settings:
  serverName:
    type: string
    label: Server name
    default: Fake
    min: 1
    max: 64

launch:
  args:
    - --state-dir
    - "{{instance}}/state"
${[for (final a in serverArgs) '    - "$a"'].join('\n')}

stop:
  strategy: signal
  grace_seconds: $graceSeconds

health:
  $health

logs:
  - name: server
    stdout: true
    encoding: utf-8

data_paths:
  - "state/"
''');
  }

  /// Gives the installed plugin a `gslt` secret setting named in
  /// `steam.gslt` (design D4); a launch argument `{{secrets.gslt}}` in
  /// `serverArgs` then hands its value to the server.
  void addGsltSetting({bool required = false}) {
    final file = File(p.join(env.pluginsDir, 'valheim', 'plugin.yaml'));
    final text = file.readAsStringSync();
    const login = '  login: anonymous\n';
    const max = '    max: 64\n';
    for (final anchor in [login, max]) {
      expect(text, contains(anchor), reason: 'plugin edit target');
    }
    file.writeAsStringSync(
      text
          .replaceFirst(
            login,
            '$login  gslt: { setting: gslt, required: $required }\n',
          )
          .replaceFirst(max, '$max  gslt:\n    type: secret\n'),
    );
  }

  /// A new Windows host running the compiled `yagurad`.
  WindowsProcessHost newHost() =>
      WindowsProcessHost(helperExecutable: tools.yagurad);

  /// Starts a daemon on the rig's data directory with the real host (or
  /// [wrap] around it).
  Future<Daemon> start({
    ProcessHost Function(WindowsProcessHost host)? wrap,
    Duration processHealthSettle = const Duration(milliseconds: 300),
    Duration pendingRunWait = const Duration(seconds: 3),
    SecretProtector? secretProtector,
  }) {
    final real = host = newHost();
    return env.start(
      secretProtector: secretProtector,
      processHost: wrap == null ? real : wrap(real),
      helperExecutable: tools.yagurad,
      processHealthSettle: processHealthSettle,
      pendingRunWait: pendingRunWait,
    );
  }

  /// Creates an instance, "installs" it (the fake Steam does nothing) and
  /// puts the `fake_server` in place of the game's executable.
  Future<Instance> createInstalledFake(Daemon daemon) async {
    final instance = await createInstalled(daemon);
    final server = Directory(p.join(instance.directory, 'server'))
      ..createSync(recursive: true);
    File(tools.fakeServer).copySync(p.join(server.path, 'valheim_server.exe'));
    return instance;
  }

  /// Creates, "installs" and starts an instance; returns it `running`.
  Future<Instance> createRunning(Daemon daemon) async {
    final instance = await createInstalledFake(daemon);
    final done = await runStart(daemon, instance.id);
    expect(
      done.resultReason,
      isEmpty,
      reason: 'start failed: ${done.resultMessage}',
    );
    return daemon.instances.get(instance.id);
  }

  /// A file the `fake_server` writes in its state directory.
  String stateFile(Instance instance, String name) =>
      p.join(instance.directory, 'state', name);

  /// Every PID recorded under the rig's data directory.
  Set<int> recordedPids() {
    final pids = <int>{};
    final root = Directory(env.root.path);
    if (!root.existsSync()) return pids;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      try {
        if (name == 'relay.json') {
          final json = jsonDecode(entity.readAsStringSync()) as Map;
          for (final key in ['relay_pid', 'server_pid']) {
            if (json[key] case final int pid) pids.add(pid);
          }
        } else if (name == 'pid.txt') {
          if (int.tryParse(entity.readAsStringSync()) case final pid?) {
            pids.add(pid);
          }
        }
      } on Object {
        // A half-written file names nobody.
      }
    }
    return pids;
  }

  Future<void> _cleanup() async {
    // Daemons first, so a killed server is not restarted under the test.
    await env.closeDaemons();
    for (final pid in recordedPids()) {
      if (Platform.isWindows && processAlive(pid)) Process.killPid(pid);
    }
    // Let the processes release their files before the directory goes.
    for (var i = 0; i < 50; i++) {
      if (!recordedPids().any(processAlive)) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
