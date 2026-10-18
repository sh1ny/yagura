import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/admin/admin_wire.dart';

import 'process_support.dart';

// Helpers of the `elevated` rows. They need an elevated Windows session and
// change the machine (a scheduled task running as LocalSystem, a local
// account), so they run only in the manual `elevated` workflow
// (.github/workflows/elevated.yml), never on a developer's desktop.

final _random = Random.secure();

String _suffix() => _random.nextInt(1 << 30).toRadixString(16);

/// Runs [script] in Windows PowerShell and returns the result.
ProcessResult powershell(String script) => Process.runSync('powershell.exe', [
  '-NoProfile',
  '-NonInteractive',
  '-ExecutionPolicy',
  'Bypass',
  '-Command',
  script,
]);

/// What `yagurad <arguments>` printed, run by the current (elevated) user.
Future<ProcessResult> runYaguradExe(
  ProcessTools tools,
  List<String> arguments,
) => Process.run(tools.yagurad, arguments);

/// A service-mode daemon running as LocalSystem on the real admin pipe.
///
/// It is started through a scheduled task that runs as SYSTEM, since the
/// admin channel works only when its server is LocalSystem. The Windows
/// service itself comes with the installer (task group 8).
class SystemDaemon {
  SystemDaemon._(this.tools, this.task, this.dataDir);

  final ProcessTools tools;
  final String task;
  final Directory dataDir;

  /// Starts the daemon and waits until the admin pipe answers `status`.
  static Future<SystemDaemon> start(ProcessTools tools) async {
    final task = 'yagura-test-${_suffix()}';
    final dataDir = Directory.systemTemp.createTempSync('yagurad_system_');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final daemon = SystemDaemon._(tools, task, dataDir);
    addTearDown(daemon.stop);

    final command =
        '"${tools.yagurad}" run --service --bind 127.0.0.1:$port '
        '--data-dir "${p.join(dataDir.path, 'data')}"';
    final create = Process.runSync('schtasks', [
      '/Create',
      '/TN',
      task,
      '/TR',
      command,
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
    final run = Process.runSync('schtasks', ['/Run', '/TN', task]);
    if (run.exitCode != 0) {
      fail('schtasks /Run failed: ${run.stdout}${run.stderr}');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final status = await runYaguradExe(tools, ['status']);
      if (status.exitCode == 0) return daemon;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    fail('the daemon did not serve $adminPipeName within 60 s');
  }

  /// Ends the task and removes what it left.
  Future<void> stop() async {
    Process.runSync('schtasks', ['/End', '/TN', task]);
    Process.runSync('schtasks', ['/Delete', '/TN', task, '/F']);
    // The daemon releases its files when its process ends.
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

/// A standard local user, made for one test and deleted with it.
class StandardUser {
  StandardUser._(this.name, this.password);

  final String name;
  final String password;

  static StandardUser create() {
    // 24 characters meet the complexity policy.
    final user = StandardUser._(
      'ytest${_suffix()}'.substring(0, 12),
      'Aa1!${_suffix()}${_suffix()}zZ',
    );
    final made = Process.runSync('net', [
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

  void delete() {
    Process.runSync('net', ['user', name, '/delete']);
  }

  /// Runs [executable] with [arguments] as this user and returns what it
  /// printed and its exit code. The files it is given must be readable by
  /// the user; the output goes to a folder made for it.
  Future<({int exitCode, String out, String err})> run(
    String executable,
    List<String> arguments,
  ) async {
    final folder = Directory.systemTemp.createTempSync('yagurad_user_');
    addTearDown(() => folder.deleteSync(recursive: true));
    // Anyone may write into the folder, so the user's process can write its
    // output files.
    Process.runSync('icacls', [folder.path, '/grant', '*S-1-1-0:(OI)(CI)F']);
    final out = p.join(folder.path, 'out.txt');
    final err = p.join(folder.path, 'err.txt');
    final script =
        '''
\$secure = ConvertTo-SecureString '$password' -AsPlainText -Force
\$credential = New-Object System.Management.Automation.PSCredential('.\\$name', \$secure)
\$process = Start-Process -FilePath '$executable' -ArgumentList '${arguments.join(' ')}' -Credential \$credential -WorkingDirectory '${folder.path}' -RedirectStandardOutput '$out' -RedirectStandardError '$err' -Wait -PassThru
exit \$process.ExitCode
''';
    final result = powershell(script);
    return (
      exitCode: result.exitCode,
      out: File(out).existsSync() ? File(out).readAsStringSync() : '',
      err: File(err).existsSync() ? File(err).readAsStringSync() : '',
    );
  }
}
