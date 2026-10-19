import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/admin/admin_wire.dart';

import 'logon_support.dart';
import 'process_support.dart';

// Helpers of the `elevated` rows. They need an elevated Windows session and
// change the machine (a scheduled task running as LocalSystem, a local
// account), so they run only in the manual `elevated` workflow
// (.github/workflows/elevated.yml), never on a developer's desktop.
//
// Every external command goes through [runCommand]: it never blocks the
// isolate (the first elevated run hung inside `Process.runSync`, which stops
// the event loop and with it the test's own timeout), has a hard timeout,
// closes stdin, ends the whole process tree when it runs out of time, and
// logs one line before it starts.

final _random = Random.secure();

/// Always eight hex digits, so names and passwords built from it have a
/// fixed length.
String _suffix() => _random.nextInt(1 << 30).toRadixString(16).padLeft(8, '0');

/// `%ProgramData%\yagurad-test`: where the rows that run the daemon as
/// LocalSystem keep their data, as a real install keeps its own. The temp
/// folder of the runner's profile is not a place the service accounts, or a
/// standard user, can be expected to reach.
Directory programDataBase() =>
    Directory(p.join(Platform.environment['ProgramData']!, 'yagurad-test'))
      ..createSync(recursive: true);

/// The default limit of one external command.
const commandTimeout = Duration(seconds: 90);

void _log(String line) {
  // stderr is the process's own, so the line shows up at once, not when the
  // test ends.
  stderr.writeln('[${DateTime.now().toIso8601String()}] $line');
}

/// Ends [pid] and its children.
Future<void> killProcessTree(int pid) async {
  _log('taskkill /T /F /PID $pid');
  try {
    final kill = await Process.start('taskkill', ['/T', '/F', '/PID', '$pid']);
    unawaited(kill.stdin.close().catchError((Object _) {}));
    unawaited(kill.stdout.drain<void>());
    unawaited(kill.stderr.drain<void>());
    await kill.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        kill.kill();
        return -1;
      },
    );
  } on Object catch (e) {
    _log('taskkill failed: $e');
  }
}

/// A command that did not finish in time.
class CommandTimeout implements Exception {
  CommandTimeout(this.command, this.timeout, this.out, this.err);

  final String command;
  final Duration timeout;
  final String out;
  final String err;

  @override
  String toString() =>
      'the command did not finish within ${timeout.inSeconds} s and was '
      'ended: $command\nstdout so far: $out\nstderr so far: $err';
}

/// Runs [executable] with [arguments]: logs it, closes stdin, collects the
/// output and waits up to [timeout]. A command that runs out of time is ended
/// with its children, and the test fails with the command, the output so far
/// and a listing of the `yagurad` processes (unless [failOnTimeout] is false,
/// which returns exit code -1 instead and is for the diagnosis itself).
Future<ProcessResult> runCommand(
  String executable,
  List<String> arguments, {
  Duration timeout = commandTimeout,
  bool failOnTimeout = true,
}) async {
  final command = '$executable ${arguments.join(' ')}';
  _log('run: $command');
  final process = await Process.start(executable, arguments);
  // Nothing is ever typed to a command: a prompt reads end of input.
  unawaited(process.stdin.close().catchError((Object _) {}));
  final out = StringBuffer();
  final err = StringBuffer();
  final streams = Future.wait([
    process.stdout.transform(systemEncoding.decoder).forEach(out.write),
    process.stderr.transform(systemEncoding.decoder).forEach(err.write),
  ]);
  var finished = false;
  addTearDown(() async {
    // A test that ended or timed out leaves no command behind.
    if (!finished) await killProcessTree(process.pid);
  });
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      await killProcessTree(process.pid);
      return -1;
    },
  );
  finished = true;
  // The output ends with the process (its children may keep the pipes).
  await streams.timeout(const Duration(seconds: 5), onTimeout: () => const []);
  if (timedOut) {
    if (!failOnTimeout) {
      return ProcessResult(process.pid, -1, '$out', '$err');
    }
    final listing = await processListing();
    fail('${CommandTimeout(command, timeout, '$out', '$err')}\n$listing');
  }
  return ProcessResult(process.pid, exitCode, '$out', '$err');
}

/// Runs [script] in Windows PowerShell and returns the result.
Future<ProcessResult> powershell(
  String script, {
  Duration timeout = commandTimeout,
  bool failOnTimeout = true,
}) => runCommand(
  'powershell.exe',
  [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ],
  timeout: timeout,
  failOnTimeout: failOnTimeout,
);

/// What `yagurad <arguments>` printed, run by the current (elevated) user.
Future<ProcessResult> runYaguradExe(
  ProcessTools tools,
  List<String> arguments,
) => runCommand(tools.yagurad, arguments, timeout: const Duration(seconds: 30));

/// A service-mode daemon running as LocalSystem on the real admin pipe.
///
/// It is started through a scheduled task that runs as SYSTEM, since the
/// admin channel works only when its server is LocalSystem. The Windows
/// service itself comes with the installer (task group 8).
///
/// Its output goes to `daemon.log` beside the data directory, and a failed
/// start prints it. The admin pipe has a fixed name, so [stop] makes sure the
/// daemon is really gone: `schtasks /End` alone left it serving the pipe in
/// the first elevated run, and the tests that followed talked to it.
class SystemDaemon {
  SystemDaemon._(this.tools, this.task, this.dataDir);

  final ProcessTools tools;
  final String task;
  final Directory dataDir;

  File get log => File(p.join(dataDir.path, 'daemon.log'));

  /// Starts the daemon and waits until the admin pipe answers `status`.
  ///
  /// [prepare] runs before the daemon starts, with the path of its data
  /// directory (which does not exist yet): a row that needs a data directory
  /// an earlier daemon or a standard user made builds it there.
  static Future<SystemDaemon> start(
    ProcessTools tools, {
    Future<void> Function(String data)? prepare,
  }) async {
    // Nothing else may serve the pipe, or this daemon's status is not
    // the one the test asks.
    final squatter = await runYaguradExe(tools, ['status']);
    if (squatter.exitCode == 0) {
      fail(
        'another daemon already serves $adminPipeName:\n'
        '${squatter.stdout}${squatter.stderr}\n'
        '${await processListing()}',
      );
    }
    final task = 'yagura-test-${_suffix()}';
    final dataDir = programDataBase().createTempSync('yagurad_system_');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final daemon = SystemDaemon._(tools, task, dataDir);
    addTearDown(daemon.stop);
    await prepare?.call(p.join(dataDir.path, 'data'));

    // The task runs a script, so the daemon's output can be kept.
    final script = File(p.join(dataDir.path, 'run.cmd'))
      ..writeAsStringSync(
        '@"${tools.yagurad}" run --service --bind 127.0.0.1:$port '
        '--data-dir "${p.join(dataDir.path, 'data')}" '
        '> "${daemon.log.path}" 2>&1\r\n',
      );
    final create = await runCommand('schtasks', [
      '/Create',
      '/TN',
      task,
      '/TR',
      script.path,
      '/SC',
      'ONCE',
      '/ST',
      '23:59',
      '/RU',
      'SYSTEM',
      '/RL',
      'HIGHEST',
      '/F',
    ]);
    if (create.exitCode != 0) {
      fail('schtasks /Create failed: ${create.stdout}${create.stderr}');
    }
    final run = await runCommand('schtasks', ['/Run', '/TN', task]);
    if (run.exitCode != 0) {
      fail('schtasks /Run failed: ${run.stdout}${run.stderr}');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    var last = '';
    while (DateTime.now().isBefore(deadline)) {
      final status = await runYaguradExe(tools, ['status']);
      if (status.exitCode == 0) return daemon;
      last = '${status.stdout}${status.stderr}';
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final query = await runCommand('schtasks', [
      '/Query',
      '/TN',
      task,
      '/V',
      '/FO',
      'LIST',
    ], failOnTimeout: false);
    fail(
      'the daemon did not serve $adminPipeName within 90 s.\n'
      'last `yagurad status`: $last\n'
      'task: ${query.stdout}\n'
      'daemon.log: ${daemon.log.existsSync() ? daemon.log.readAsStringSync() : '(none)'}\n'
      '${await processListing()}',
    );
  }

  /// Runs the daemon as LocalSystem on [dataArgument] (the data directory by
  /// default; a path that is not a plain directory, such as a junction, when
  /// given) and waits for it to exit by itself: a start that fails exits with
  /// the reason in its output. Returns what it printed; fails when it is still
  /// running after [timeout] (and ends it).
  static Future<({String log, Directory dataDir})> runUntilExit(
    ProcessTools tools, {
    Future<void> Function(String data)? prepare,
    String Function(String data)? dataArgument,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final task = 'yagura-test-${_suffix()}';
    final dataDir = programDataBase().createTempSync('yagurad_system_');
    final daemon = SystemDaemon._(tools, task, dataDir);
    addTearDown(daemon.stop);
    final data = p.join(dataDir.path, 'data');
    await prepare?.call(data);
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final script = File(p.join(dataDir.path, 'run.cmd'))
      ..writeAsStringSync(
        '@"${tools.yagurad}" run --service --bind 127.0.0.1:$port '
        '--data-dir "${dataArgument?.call(data) ?? data}" '
        '> "${daemon.log.path}" 2>&1\r\n'
        '@echo done> "${p.join(dataDir.path, 'exited.txt')}"\r\n',
      );
    final create = await runCommand('schtasks', [
      '/Create', '/TN', task, '/TR', script.path, '/SC', 'ONCE', '/ST', '23:59',
      '/RU', 'SYSTEM', '/RL', 'HIGHEST', '/F', //
    ]);
    if (create.exitCode != 0) {
      fail('schtasks /Create failed: ${create.stdout}${create.stderr}');
    }
    final run = await runCommand('schtasks', ['/Run', '/TN', task]);
    if (run.exitCode != 0) {
      fail('schtasks /Run failed: ${run.stdout}${run.stderr}');
    }
    final exited = File(p.join(dataDir.path, 'exited.txt'));
    final deadline = DateTime.now().add(timeout);
    while (!exited.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'the daemon was still running after ${timeout.inSeconds} s.\n'
          'daemon.log: ${daemon.log.existsSync() ? daemon.log.readAsStringSync() : '(none)'}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return (
      log: daemon.log.existsSync() ? daemon.log.readAsStringSync() : '',
      dataDir: dataDir,
    );
  }

  /// Ends the task and the daemon it started, and removes what they left.
  Future<void> stop() async {
    await runCommand('schtasks', ['/End', '/TN', task], failOnTimeout: false);
    await runCommand('schtasks', [
      '/Delete',
      '/TN',
      task,
      '/F',
    ], failOnTimeout: false);
    // The daemon is found by its data directory: `schtasks /End` leaves it.
    await powershell(
      "Get-CimInstance Win32_Process -Filter \"Name='yagurad.exe'\" | "
      "Where-Object { \$_.CommandLine -like '*${dataDir.path}*' } | "
      "ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }",
      failOnTimeout: false,
    );
    // The daemon releases its files and the pipe when its process ends.
    for (var i = 0; i < 40; i++) {
      final status = await runCommand(
        tools.yagurad,
        ['status'],
        timeout: const Duration(seconds: 30),
        failOnTimeout: false,
      );
      if (status.exitCode != 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    for (var i = 0; i < 20; i++) {
      try {
        if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}

/// The `yagurad` processes of the machine with their command lines, for the
/// diagnosis of a test that finds the admin pipe taken or a command that did
/// not finish.
Future<String> processListing() async {
  final result = await powershell(
    "Get-CimInstance Win32_Process -Filter \"Name='yagurad.exe'\" | "
    "ForEach-Object { '{0} {1}' -f \$_.ProcessId, \$_.CommandLine }",
    timeout: const Duration(seconds: 30),
    failOnTimeout: false,
  );
  return 'yagurad processes:\n${result.stdout}${result.stderr}';
}

/// A standard local user, made for one test and deleted with it.
class StandardUser {
  StandardUser._(this.name, this.password);

  final String name;
  final String password;

  static Future<StandardUser> create() async {
    // At most 14 characters: `net user` asks "Y/N" about a longer password,
    // and there is nobody to answer. Upper and lower case, a digit and a
    // symbol meet the complexity policy.
    final user = StandardUser._(
      'ytest${_suffix()}'.substring(0, 12),
      'Aa1!${_suffix()}zZ',
    );
    final made = await runCommand('net', [
      'user',
      user.name,
      user.password,
      '/add',
    ]);
    if (made.exitCode != 0) {
      fail('net user /add failed: ${made.stdout}${made.stderr}');
    }
    addTearDown(user.delete);
    return user;
  }

  Future<void> delete() async {
    await runCommand('net', ['user', name, '/delete'], failOnTimeout: false);
  }

  /// Runs [executable] with [arguments] as this user and returns what it
  /// printed and its exit code. The files it is given must be readable by
  /// the user; the output goes to a folder made for it.
  ///
  /// The user is logged on by `CreateProcessWithLogonW` (see
  /// `logon_support.dart`): no PowerShell child, no console, no dialog that
  /// can wait for an answer.
  Future<({int exitCode, String out, String err})> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final folder = Directory.systemTemp.createTempSync('yagurad_user_');
    addTearDown(() async {
      try {
        folder.deleteSync(recursive: true);
      } on FileSystemException {
        // Left to the temp cleaner.
      }
    });
    // Anyone may write into the folder, so the user's process can write its
    // output files.
    await runCommand('icacls', [folder.path, '/grant', '*S-1-1-0:(OI)(CI)F']);
    final out = p.join(folder.path, 'out.txt');
    final err = p.join(folder.path, 'err.txt');
    // `cmd /s` strips the outer quotes, so every path may hold spaces.
    final command =
        'cmd.exe /d /s /c ""$executable" ${arguments.join(' ')} '
        '> "$out" 2> "$err""';
    _log('run as $name: $command');
    final result = await runAsUser(
      user: name,
      password: password,
      commandLine: command,
      workingDirectory: folder.path,
      timeout: timeout,
      killTree: killProcessTree,
    );
    final output = File(out).existsSync() ? File(out).readAsStringSync() : '';
    final errors = File(err).existsSync() ? File(err).readAsStringSync() : '';
    if (!result.started) {
      fail(
        'CreateProcessWithLogonW failed for $name: Win32 error ${result.error}',
      );
    }
    if (result.timedOut) {
      fail(
        'the command run as $name did not finish within ${timeout.inSeconds} s '
        'and was ended: $command\nstdout so far: $output\n'
        'stderr so far: $errors\n${await processListing()}',
      );
    }
    return (exitCode: result.exitCode, out: output, err: errors);
  }
}
