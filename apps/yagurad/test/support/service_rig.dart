import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_security.dart';
import 'package:yagurad/src/platform/win32_service.dart';

import 'daemon_support.dart';
import 'elevated_support.dart';
import 'process_support.dart';
import 'service_support.dart';

// The rig of the `elevated` rows of the service install and upgrade (task
// group 8). It installs a REAL Windows service, so it fails at once unless the
// session is elevated, and it names everything it makes after a random
// suffix: the service `yagurad-t<suffix>`, an install directory and a data
// directory in the temp folder. It runs only in the manual `elevated`
// workflow, never on a developer's desktop.

final _random = Random.secure();

/// A throwaway service installed from a bundle assembled out of the process
/// tools build, with two game servers (the `fake_server` fixture) that were
/// started by a dev daemon on its data directory and are re-attached by the
/// service when it starts.
class ServiceRig {
  ServiceRig._(this.process, this.name, this.work, this.port);

  final ProcessRig process;

  /// The throwaway service name.
  final String name;
  final Directory work;

  /// The API port of the service.
  final int port;

  late final String bundleDirectory;
  final servers = <String, int>{};

  ProcessTools get tools => process.tools;
  String get installRoot => p.join(work.path, 'install');
  String get data => process.env.data;
  String get bundleExecutable => p.join(bundleDirectory, 'bin', 'yagurad.exe');

  /// Fails unless the session is elevated; builds the tools and the bundle;
  /// seeds [instances] running servers; registers the clean-up.
  static Future<ServiceRig> create({int instances = 2}) async {
    if (!Platform.isWindows || !isElevated()) {
      fail(
        'the service rows install a Windows service and need an elevated '
        'Windows session: they run only in the elevated workflow',
      );
    }
    // The admin pipe has a fixed name: a daemon left over from an earlier
    // test would answer in place of the service and fake every result.
    final squatter = await runCommand((await processTools()).yagurad, [
      'status',
    ], timeout: const Duration(seconds: 30));
    if (squatter.exitCode == 0) {
      fail(
        'another daemon already serves the admin pipe:\n'
        '${squatter.stdout}${squatter.stderr}\n${await processListing()}',
      );
    }
    final process = await ProcessRig.create();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final suffix = _random.nextInt(1 << 30).toRadixString(16);
    final rig = ServiceRig._(
      process,
      'yagurad-t$suffix',
      Directory.systemTemp.createTempSync('yagurad_service_'),
      port,
    );
    addTearDown(rig._cleanup);
    rig.bundleDirectory = rig.assembleBundle(p.join(rig.work.path, 'bundle'));
    await rig._seed(instances);
    return rig;
  }

  /// Copies the built bundle to [destination] and adds what the release
  /// packaging adds: `winsw/` (WinSW and the template) and, when [version] is
  /// given, a `VERSION` file naming the release the bundle is.
  String assembleBundle(String destination, {String? version}) {
    _copyDirectory(Directory(p.dirname(p.dirname(tools.yagurad))), destination);
    for (final file in ['WinSW.NET461.exe', 'yagurad.xml.template']) {
      File(p.join(winswSourceDirectory, file)).copySync(
        (File(
          p.join(destination, 'winsw', file),
        )..createSync(recursive: true)).path,
      );
    }
    if (version != null) {
      File(p.join(destination, 'VERSION')).writeAsStringSync(version);
    }
    return destination;
  }

  static void _copyDirectory(Directory from, String to) {
    Directory(to).createSync(recursive: true);
    for (final entity in from.listSync(recursive: true)) {
      final relative = p.relative(entity.path, from: from.path);
      if (entity is Directory) {
        Directory(p.join(to, relative)).createSync(recursive: true);
      } else if (entity is File) {
        entity.copySync(p.join(to, relative));
      }
    }
  }

  /// Starts [count] servers with a dev daemon on the data directory, then
  /// ends that daemon the way a crash does: the servers keep running.
  Future<void> _seed(int count) async {
    final daemon = await process.start();
    for (var i = 0; i < count; i++) {
      final instance = await createInstalled(
        daemon,
        name: 'Server ${i + 1}',
        ports: {'game': 2456 + 100 * i},
      );
      final directory = Directory(p.join(instance.directory, 'server'))
        ..createSync(recursive: true);
      File(tools.fakeServer)
          .copySync(p.join(directory.path, 'valheim_server.exe'));
      final done = await runStart(daemon, instance.id);
      expect(
        done.resultReason,
        isEmpty,
        reason: 'start failed: ${done.resultMessage}',
      );
    }
    await process.env.kill(daemon);
    servers
      ..clear()
      ..addAll(runningServers());
    expect(servers, hasLength(count));
    for (final pid in servers.values) {
      expect(processAlive(pid), isTrue, reason: 'server $pid after the seed');
    }
  }

  /// `yagurad service <arguments>` from [bundle] (the first one by default),
  /// aimed at this rig's service name and install directory.
  Future<ProcessResult> service(
    List<String> arguments, {
    String? bundle,
    bool failOnTimeout = true,
  }) {
    final exe = bundle == null
        ? bundleExecutable
        : p.join(bundle, 'bin', 'yagurad.exe');
    return runCommand(
      exe,
      [
        'service',
        ...arguments,
        '--service-name',
        name,
        '--install-dir',
        installRoot,
      ],
      timeout: const Duration(minutes: 3),
      failOnTimeout: failOnTimeout,
    );
  }

  /// Installs the service on the seeded data directory; fails the test with
  /// the command's output unless it succeeds.
  Future<ProcessResult> install({String? bundle}) async {
    final result = await service([
      'install',
      '--bind',
      '127.0.0.1:$port',
      '--data-dir',
      data,
    ], bundle: bundle);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    return result;
  }

  /// The state of the service in the service control manager; null when it
  /// is not registered.
  int? get serviceState => queryServiceState(name);

  /// `Restart-Service` (the way an administrator restarts it), and the wait
  /// until it runs again.
  Future<void> restart() async {
    final result = await powershell('Restart-Service -Name $name -Force');
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }

  Future<void> stopService() async {
    final result = await powershell('Stop-Service -Name $name -Force');
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }

  Future<void> startService() async {
    final result = await powershell('Start-Service -Name $name');
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }

  /// `yagurad status` over the admin pipe, as text.
  Future<String> daemonStatus() async {
    final result = await runCommand(
      bundleExecutable,
      ['status'],
      timeout: const Duration(seconds: 30),
      failOnTimeout: false,
    );
    return '${result.stdout}${result.stderr}';
  }

  /// Rows of the runs table, read without taking the database from the
  /// daemon: instance name, state, server pid, exit code, end reason.
  List<Map<String, Object?>> runs() {
    final path = p.join(data, 'yagura.db');
    if (!File(path).existsSync()) return [];
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return [
        for (final row in db.select(
          'SELECT i.name AS name, r.run_id AS run_id, r.state AS state, '
          'r.server_pid AS server_pid, r.relay_executable AS relay, '
          'r.exit_code AS exit_code, r.end_reason AS end_reason '
          'FROM runs r JOIN instances i ON i.id = r.instance_id '
          'ORDER BY r.created_at, r.rowid',
        ))
          {for (final key in row.keys) key: row[key]},
      ];
    } finally {
      db.close();
    }
  }

  /// Instance name to server PID of the runs recorded as running.
  Map<String, int> runningServers() => {
    for (final run in runs())
      if (run['state'] == 'running')
        run['name']! as String: run['server_pid']! as int,
  };

  /// Waits until [condition] holds, up to [timeout].
  Future<void> eventuallyHolds(
    bool Function() condition, {
    required String reason,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $reason');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Waits until the daemon of the service has re-attached to [count]
  /// servers and they run.
  Future<void> whenServersAttached(int count) => eventuallyHolds(
    () => runningServers().length == count,
    reason: 'the daemon to re-attach to $count servers',
  );

  /// Everything that helps to read a failure: the service, the daemon behind
  /// the pipe, the runs, the install folder and the logs.
  Future<String> diagnostics() async {
    final text = StringBuffer()
      ..writeln('service $name: state $serviceState')
      ..writeln(
        (await powershell('sc.exe qc $name', failOnTimeout: false)).stdout,
      )
      ..writeln('daemon status over the pipe:')
      ..writeln(await daemonStatus())
      ..writeln(await processListing())
      ..writeln('runs:');
    try {
      for (final run in runs()) {
        text.writeln('  $run');
      }
    } on Object catch (e) {
      text.writeln('  (cannot read the database: $e)');
    }
    text.writeln('install folder $installRoot:');
    final root = Directory(installRoot);
    if (root.existsSync()) {
      for (final entity in root.listSync(recursive: true)) {
        text.writeln('  ${p.relative(entity.path, from: installRoot)}');
      }
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        final extension = p.extension(file.path);
        if (extension == '.xml' || extension == '.log') {
          final content = file.readAsStringSync();
          final tail = content.length > 4000
              ? content.substring(content.length - 4000)
              : content;
          text.writeln('--- ${p.basename(file.path)}\n$tail');
        }
      }
    }
    final dataRoot = Directory(data);
    if (dataRoot.existsSync()) {
      for (final file in dataRoot.listSync(recursive: true).whereType<File>()) {
        final name = p.basename(file.path);
        if (name == 'exit.json' || name == 'relay.json') {
          text.writeln(
            '--- ${p.relative(file.path, from: data)}\n'
            '${file.readAsStringSync()}',
          );
        }
      }
      final daemonLogs = Directory(p.join(data, 'logs'));
      if (daemonLogs.existsSync()) {
        for (final file in daemonLogs.listSync().whereType<File>()) {
          final content = file.readAsStringSync();
          final tail = content.length > 4000
              ? content.substring(content.length - 4000)
              : content;
          text.writeln('--- logs/${p.basename(file.path)}\n$tail');
        }
      }
    }
    return '$text';
  }

  Future<void> _cleanup() async {
    try {
      printOnFailure(await diagnostics());
    } on Object catch (e) {
      printOnFailure('cannot collect diagnostics: $e');
    }
    // Remove the service first, so it does not start a killed server again.
    if (serviceState != null) {
      await service(['uninstall'], failOnTimeout: false);
    }
    if (serviceState != null) {
      await powershell('sc.exe delete $name', failOnTimeout: false);
    }
    await process.env.closeDaemons();
    for (final pid in {...process.recordedPids(), ...servers.values}) {
      if (processAlive(pid)) Process.killPid(pid);
    }
    for (var i = 0; i < 50; i++) {
      if (!process.recordedPids().any(processAlive)) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 20; i++) {
      try {
        if (work.existsSync()) work.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}
