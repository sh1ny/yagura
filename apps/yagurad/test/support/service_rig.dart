import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_security.dart';
import 'package:yagurad/src/platform/win32_service.dart';
import 'package:yagurad/src/steam/steamcmd_service.dart';

import 'account_support.dart'
    show accountSid, queryDatabase, removeServiceAccounts, sddlOf;
import 'daemon_support.dart';
import 'elevated_support.dart';
import 'firewall_elevated_support.dart';
import 'process_support.dart';
import 'service_support.dart';
import 'temp_support.dart';

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

  /// Where the install folder goes. Not under the temp folder, which a user
  /// owns: the install refuses a folder below one (ADR 0015), so the rig uses
  /// `%ProgramData%`, whose folders an elevated session owns as
  /// Administrators.
  late final String installRoot = p.join(_installBase.path, 'install');
  late final Directory _installBase = Directory(
    p.join(Platform.environment['ProgramData']!, 'yagurad-test', name),
  )..createSync(recursive: true);
  String get data => process.env.data;
  String get bundleExecutable => p.join(bundleDirectory, 'bin', 'yagurad.exe');

  /// Fails unless the session is elevated; builds the tools and the bundle;
  /// seeds [instances] instances; registers the clean-up.
  ///
  /// A dev daemon makes and installs the instances but does not start them:
  /// they are marked as requested running, so that the service starts them
  /// itself (as `yagura-srv`) when it comes up. Servers a dev daemon started
  /// would run as the runner's account and the service would reject them
  /// (design D9: only a relay's child running as `yagura-srv` is verified), so
  /// the rows wait for the servers with [whenServersAttached] after
  /// [install].
  static Future<ServiceRig> create({
    int instances = 2,
    List<String> serverArgs = const [],
    bool gslt = false,
  }) async {
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
    final process = await ProcessRig.create(
      parent: programDataBase(),
      serverArgs: serverArgs,
    );
    if (gslt) process.addGsltSetting();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final suffix = _random.nextInt(1 << 30).toRadixString(16);
    final rig = ServiceRig._(
      process,
      'yagurad-t$suffix',
      createCanonicalTempSync('yagurad_service_'),
      port,
    );
    addTearDown(rig._cleanup);
    expect(Directory(rig.installRoot).parent.existsSync(), isTrue);
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

  /// Makes and installs [count] instances with a dev daemon, marks them as
  /// requested running and ends that daemon; the service starts them.
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
    }
    await process.env.kill(daemon);
    final db = sqlite3.open(p.join(data, 'yagura.db'));
    try {
      db.execute("UPDATE instances SET last_requested_state = 'running'");
    } finally {
      db.close();
    }
  }

  /// Puts the fake SteamCMD (compiled) and the ready mark into the data
  /// directory's `steamcmd/anonymous`, so the service's Install runs it
  /// without the network. Call it before the service is installed: the first
  /// service start then gives the folder to `yagura-steam`.
  Future<void> seedFakeSteamCmd() async {
    final steam = p.join(data, 'steamcmd', 'anonymous');
    Directory(steam).createSync(recursive: true);
    final compiled = await runCommand(Platform.resolvedExecutable, [
      'compile',
      'exe',
      p.absolute('test', 'fixtures', 'fake_steamcmd', 'fake_steamcmd.dart'),
      '-o',
      p.join(steam, 'steamcmd.exe'),
    ], timeout: const Duration(minutes: 5));
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    final output = Directory(p.join(steam, 'output'))
      ..createSync(recursive: true);
    for (final file in Directory(
      p.absolute('test', 'fixtures', 'fake_steamcmd', 'output'),
    ).listSync().whereType<File>()) {
      file.copySync(p.join(output.path, p.basename(file.path)));
    }
    // The daemon remembers that SteamCMD is ready in its database
    // (`steamcmd_installations`), not in a marker file: without the row it
    // would unpack Valheim's real SteamCMD over the fake and install the real
    // game.
    final db = sqlite3.open(p.join(data, 'yagura.db'));
    try {
      db.execute(
        'INSERT OR REPLACE INTO steamcmd_installations (installation, '
        'ready_at) VALUES (?, ?)',
        [
          SteamCmdService.anonymousInstallation,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    } finally {
      db.close();
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

  /// Waits until [condition] holds, up to [timeout]. When [abortWhen] returns
  /// text, the wait ends at once with that text: a condition that can no
  /// longer come true (a server that already ended `launch_failed`) fails the
  /// test now, not after the timeout.
  Future<void> eventuallyHolds(
    bool Function() condition, {
    required String reason,
    Duration timeout = const Duration(seconds: 90),
    String? Function()? abortWhen,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      final abort = abortWhen?.call();
      if (abort != null) fail('gave up waiting for $reason: $abort');
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $reason');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Why a wait for running servers is hopeless, or null: a run that ended
  /// with a reason (with the message of the operation that failed), or a
  /// service that is not running.
  String? serverWaitIsHopeless() {
    try {
      for (final run in runs()) {
        final reason = '${run['end_reason']}';
        if (run['state'] == 'ended' && reason.isNotEmpty) {
          final failed = queryDatabase(
            data,
            "SELECT kind, result_reason, result_message FROM operations "
            "WHERE status != 'succeeded' AND result_message != '' "
            "ORDER BY created_at DESC LIMIT 3",
          );
          return 'the run of ${run['name']} ended $reason '
              '(operations: $failed)';
        }
      }
    } on Object {
      // The database is not readable at this moment: keep waiting.
    }
    final state = serviceState;
    if (state != null && state != serviceRunning) {
      return 'the service is in state $state';
    }
    return null;
  }

  /// Waits until the daemon of the service has re-attached to [count]
  /// servers and they run. Fails at once when a run ended or the service
  /// stopped.
  Future<void> whenServersAttached(
    int count, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await eventuallyHolds(
      () => runningServers().length == count,
      reason: 'the daemon to re-attach to $count servers',
      timeout: timeout,
      abortWhen: serverWaitIsHopeless,
    );
    // The clean-up ends them, and the rows look servers up by name.
    servers
      ..clear()
      ..addAll(runningServers());
  }

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
    try {
      text
        ..writeln('operations:')
        ..writeln(
          queryDatabase(
            data,
            'SELECT kind, status, result_reason, result_message FROM '
            'operations ORDER BY created_at',
          ).join(', '),
        )
        ..writeln('instances:')
        ..writeln(
          queryDatabase(
            data,
            'SELECT name, state, last_requested_state, acl_layout, directory '
            'FROM instances',
          ).join(', '),
        );
    } on Object catch (e) {
      text.writeln('  (cannot read the database: $e)');
    }
    final srv = await accountSid('yagura-srv');
    final steam = await accountSid('yagura-steam');
    text.writeln('accounts: yagura-srv=$srv yagura-steam=$steam');
    for (final path in [
      data,
      p.join(data, 'yagura.db'),
      p.join(data, 'instances'),
      p.join(data, 'steamcmd'),
      p.join(data, 'content'),
      p.join(data, 'acl-layout'),
      if (Directory(p.join(data, 'instances')).existsSync())
        ...Directory(p.join(data, 'instances')).listSync().map((e) => e.path),
    ]) {
      try {
        if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
          text.writeln('acl $path: (missing)');
        } else {
          text.writeln('acl $path: ${await sddlOf(path)}');
        }
      } on Object catch (e) {
        text.writeln('acl $path: ($e)');
      }
    }
    text
      ..writeln(
        (await runCommand('net', [
          'user',
          'yagura-srv',
        ], failOnTimeout: false)).stdout,
      )
      ..writeln('install folder $installRoot:');
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
      text.writeln('data directory, three levels deep:');
      _listing(dataRoot, data, 3, text);
      text.writeln('the instances, five levels deep:');
      _listing(Directory(p.join(data, 'instances')), data, 4, text);
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

  /// [directory] and what is below it, [depth] levels deep, with sizes.
  static void _listing(
    Directory directory,
    String base,
    int depth,
    StringBuffer text,
  ) {
    if (depth == 0) return;
    List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } on FileSystemException catch (e) {
      text.writeln('  ${p.relative(directory.path, from: base)}: $e');
      return;
    }
    for (final child in children) {
      final relative = p.relative(child.path, from: base);
      if (child is File) {
        text.writeln('  $relative (${child.lengthSync()} bytes)');
      } else if (child is Directory) {
        text.writeln('  $relative/');
        _listing(child, base, depth - 1, text);
      } else {
        text.writeln('  $relative (link)');
      }
    }
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
    // The daemon of the service owned firewall rules (instance ports, its API
    // port); a row ends without them. This empties the whole group `Yagura`:
    // the rig runs only on the elevated workflow's runner.
    try {
      await removeYaguraGroup();
    } on Object catch (e) {
      printOnFailure('cannot remove the Yagura firewall rules: $e');
    }
    try {
      servers.addAll(runningServers());
    } on Object {
      // The database is gone or unreadable: the servers known so far are ended.
    }
    for (final pid in {...process.recordedPids(), ...servers.values}) {
      if (processAlive(pid)) Process.killPid(pid);
    }
    await removeServiceAccounts();
    for (var i = 0; i < 50; i++) {
      if (!process.recordedPids().any(processAlive)) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 20; i++) {
      try {
        if (work.existsSync()) work.deleteSync(recursive: true);
        if (_installBase.existsSync()) _installBase.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}
