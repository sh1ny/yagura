import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../logs/capture_writer.dart';
import '../logs/log_models.dart';
import '../platform/job_restrictions.dart';
import '../platform/win32.dart';
import '../platform/win32_logon.dart';
import '../platform/win32_process.dart';
import 'relay_run_files.dart';
import 'run_files.dart';

/// Exit codes of the helper modes.
const helperOk = 0;
const helperFailed = 2;
const helperUsage = 64;

/// The launcher could not log the game-server account on, load its profile or
/// start the relay as it; stderr names the call and its Win32 error
/// (`logon_failed: <call> <error>`).
const helperLogonFailed = 3;

/// The account the launcher starts the relay as, read from its standard input
/// (never from the command line or the environment, which other processes can
/// read).
class AccountCredentials {
  const AccountCredentials(this.account, this.password);

  final String account;
  final String password;

  /// `{"account": ..., "password": ...}` on one line.
  String encode() => jsonEncode({'account': account, 'password': password});

  static AccountCredentials? decode(String? line) {
    if (line == null) return null;
    try {
      final json = jsonDecode(line);
      if (json is Map &&
          json['account'] is String &&
          json['password'] is String) {
        return AccountCredentials(
          json['account'] as String,
          json['password'] as String,
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

/// The line of standard input every launch carries (design D4): the daemon
/// writes it to the launcher, and the launcher writes the `secrets` of it to
/// the relay. Arguments and the environment are readable by other processes,
/// standard input is not, and no file holds it.
class LaunchInput {
  const LaunchInput({this.credentials, this.secrets = const {}});

  /// The account to start the relay as; only the launcher sees it.
  final AccountCredentials? credentials;

  /// The secret setting values behind the secret launch arguments, by name.
  final Map<String, String> secrets;

  /// One line of JSON; the credentials are left out when there are none.
  String encode() => jsonEncode({
    if (credentials != null) 'account': credentials!.account,
    if (credentials != null) 'password': credentials!.password,
    'secrets': secrets,
  });

  /// What the relay is sent: the secrets alone, never the password.
  String encodeForRelay() => jsonEncode({'secrets': secrets});

  /// The decoded line, or null when it is missing or malformed.
  static LaunchInput? decode(String? line) {
    if (line == null) return null;
    try {
      final json = jsonDecode(line);
      if (json is! Map) return null;
      final secrets = json['secrets'];
      if (secrets is! Map ||
          secrets.values.any((v) => v is! String) ||
          secrets.keys.any((k) => k is! String)) {
        return null;
      }
      final account = json['account'];
      final password = json['password'];
      return LaunchInput(
        credentials: account is String && password is String
            ? AccountCredentials(account, password)
            : null,
        secrets: {
          for (final MapEntry(:key, :value) in secrets.entries)
            key as String: value as String,
        },
      );
    } on FormatException {
      return null;
    }
  }
}

/// The relay's standard input in the launcher: an anonymous pipe the launcher
/// fills with the [LaunchInput.secrets] line and closes, and a NUL device for
/// the relay's other standard handles (the relay owns its own console).
class _RelayInputPipe {
  _RelayInputPipe._(this.read, this.write, this.nul);

  /// The pipe holds a whole line without the writer waiting for the relay.
  static const _capacity = 64 * 1024;

  final int read;
  int write;
  final int nul;

  /// The inheritable handles the relay is started with, and no others.
  List<int> get handles => [read, nul];

  static _RelayInputPipe create(String line) {
    final win32 = Win32.instance;
    final bytes = utf8.encode('$line\n');
    if (bytes.length >= _capacity) {
      throw StateError('the launch input is larger than the relay pipe');
    }
    final readEnd = calloc<IntPtr>();
    final writeEnd = calloc<IntPtr>();
    final security = calloc<Uint8>(Win32.securityAttributesSize);
    final name = 'NUL'.toNativeUtf16();
    try {
      (security).cast<Uint32>().value = Win32.securityAttributesSize;
      (security + 16).cast<Int32>().value = 1;
      if (win32.createPipe(readEnd, writeEnd, security.cast(), _capacity) ==
          0) {
        throw StateError('CreatePipe failed');
      }
      // The write end stays with the launcher.
      win32.setHandleInformation(writeEnd.value, Win32.handleFlagInherit, 0);
      final nul = win32.createFile(
        name,
        Win32.genericRead | Win32.genericWrite,
        Win32.fileShareReadWrite,
        security.cast(),
        Win32.openExisting,
        0,
        0,
      );
      if (nul == Win32.invalidHandle) {
        win32
          ..closeHandle(readEnd.value)
          ..closeHandle(writeEnd.value);
        throw StateError('the NUL device could not be opened');
      }
      final pipe = _RelayInputPipe._(readEnd.value, writeEnd.value, nul);
      final buffer = calloc<Uint8>(bytes.length);
      final written = calloc<Uint32>();
      try {
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        if (win32.writeFile(
                  pipe.write,
                  buffer,
                  bytes.length,
                  written,
                  nullptr,
                ) ==
                0 ||
            written.value != bytes.length) {
          pipe.close();
          throw StateError('the launch input could not be written');
        }
      } finally {
        calloc
          ..free(buffer)
          ..free(written);
      }
      // End of input for the relay once it has read the line.
      win32.closeHandle(pipe.write);
      pipe.write = 0;
      return pipe;
    } finally {
      calloc
        ..free(readEnd)
        ..free(writeEnd)
        ..free(security)
        ..free(name);
    }
  }

  void close() {
    final win32 = Win32.instance;
    if (write != 0) win32.closeHandle(write);
    win32
      ..closeHandle(read)
      ..closeHandle(nul);
  }
}

/// Reads the launch input line of standard input, or null when it is missing
/// or unreadable.
LaunchInput? readLaunchInput() {
  try {
    return LaunchInput.decode(stdin.readLineSync(encoding: utf8));
  } on IOException {
    return null;
  }
}

/// `yagurad launch --run-dir <dir>` (design D2, ADR 0009): starts the relay in
/// its own hidden console, outside the daemon's job, prints
/// `{relay_pid, relay_created}` as one JSON line and exits. The relay is
/// not a child of anything that will go away.
///
/// Windows only.
Future<int> runLaunchMode(
  String runDirectory,
  StringSink out,
  StringSink err, {
  required LaunchInput input,
}) async {
  final self = Platform.resolvedExecutable;
  final credentials = input.credentials;
  _RelayInputPipe pipe;
  try {
    pipe = _RelayInputPipe.create(input.encodeForRelay());
  } on StateError catch (e) {
    err.writeln('launch failed: ${e.message}');
    return helperFailed;
  }
  try {
    if (credentials != null) {
      return await _launchAsAccount(
        self,
        runDirectory,
        credentials,
        pipe,
        out,
        err,
      );
    }
    return _launchConsole(self, runDirectory, pipe, out, err);
  } finally {
    pipe.close();
  }
}

int _launchConsole(
  String self,
  String runDirectory,
  _RelayInputPipe pipe,
  StringSink out,
  StringSink err,
) {
  try {
    final relay = spawnProcess(
      executable: self,
      args: ['relay', '--run-dir', runDirectory],
      flags:
          Win32.createNewConsole |
          Win32.createBreakawayFromJob |
          Win32.createUnicodeEnvironment,
      hidden: true,
      inheritHandles: true,
      stdin: pipe.read,
      stdout: pipe.nul,
      stderr: pipe.nul,
      handles: pipe.handles,
    );
    final identity = identityOfHandle(relay.handle, relay.pid);
    Win32.instance.closeHandle(relay.handle);
    out.writeln(
      jsonEncode({'relay_pid': relay.pid, 'relay_created': identity?.created}),
    );
    return helperOk;
  } on SpawnFailure catch (e) {
    // `GetLastError` is not reliable through plain dart:ffi (spike 1.3), so a
    // refused breakaway is named from the job's limits.
    final why = breakawayRestriction();
    err.writeln(
      why == null
          ? '${e.message} (the relay could not be started)'
          : 'the relay could not be started outside the job: $why',
    );
    return helperFailed;
  }
}

/// The launcher's exit code for [failure]: only the logon steps are a logon
/// failure (`launch_logon_failed`); a failure to create the process once the
/// logon succeeded is a failed launch (design D7).
int launcherExitFor(LogonFailure failure) =>
    failure.stage == LogonStage.account ? helperLogonFailed : helperFailed;

/// What the launcher tells the daemon on standard error about [failure].
String launcherFailureText(LogonFailure failure) =>
    failure.stage == LogonStage.account
    ? 'logon_failed: ${failure.call} ${failure.error}'
    : 'launch failed: ${failure.call} failed with error ${failure.error}';

/// Starts the relay as the game-server account through the logon module
/// (design D7): logon, profile, environment, `CreateProcessAsUserW` on
/// `YaguraSrv\Default`. The profile load is balanced by `UnloadUserProfile`
/// once the relay is started, before this process exits.
Future<int> _launchAsAccount(
  String self,
  String runDirectory,
  AccountCredentials credentials,
  _RelayInputPipe pipe,
  StringSink out,
  StringSink err,
) async {
  AccountSession? session;
  try {
    session = AccountSession.open(credentials.account, credentials.password);
    final commandLine = windowsCommandLine(self, [
      'relay',
      '--run-dir',
      runDirectory,
    ]);
    StartedProcess started;
    const flags = Win32.createNewConsole | Win32.createUnicodeEnvironment;
    // A directory every account can enter: the process takes its current
    // directory from here, and one the account cannot reach fails its start.
    final directory = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    try {
      started = session.start(
        commandLine: commandLine,
        workingDirectory: directory,
        flags: flags | Win32.createBreakawayFromJob,
        stdin: pipe.read,
        stdout: pipe.nul,
        stderr: pipe.nul,
        handles: pipe.handles,
      );
    } on LogonFailure catch (e) {
      // A job that does not allow breakaway refuses it with access denied;
      // the relay then stays in the launcher's job, which ends with it.
      if (e.call != 'CreateProcessAsUserW' || e.error != 5) rethrow;
      started = session.start(
        commandLine: commandLine,
        workingDirectory: directory,
        flags: flags,
        stdin: pipe.read,
        stdout: pipe.nul,
        stderr: pipe.nul,
        handles: pipe.handles,
      );
    }
    final win32 = Win32.instance;
    final identity = identityOfHandle(started.process, started.pid);
    // The profile stays loaded until the relay has started and recorded
    // itself: unloading the hive under a process that is still initialising
    // fails it (spike S2 waited for the child too).
    final settled = await _relaySettled(
      started.process,
      // Read through the instance's confinement: this process is LocalSystem,
      // and the run directory is the game-server account's to rearrange.
      RunFiles.forRun(runDirectory),
      const Duration(seconds: 30),
    );
    win32
      ..closeHandle(started.thread)
      ..closeHandle(started.process);
    if (settled != null) {
      err.writeln(
        'the relay (pid ${started.pid}) ended with exit code $settled '
        '(0x${settled.toUnsigned(32).toRadixString(16).toUpperCase()}) before '
        'it recorded itself in relay.json',
      );
      return helperFailed;
    }
    out.writeln(
      jsonEncode({
        'relay_pid': started.pid,
        'relay_created': identity?.created,
      }),
    );
    return helperOk;
  } on LogonFailure catch (e) {
    err.writeln(launcherFailureText(e));
    return launcherExitFor(e);
  } on Object catch (e, stack) {
    err.writeln('launch failed: $e\n$stack');
    return helperFailed;
  } finally {
    session?.close();
  }
}

/// Waits until the relay has written `relay.json` (null), or has ended (its
/// exit code), or [limit] has passed (null: it is running, only slowly).
Future<int?> _relaySettled(int process, RunFiles files, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    if (files.readRelay() != null) return null;
    if (processEnded(process)) {
      // It may have recorded itself just before it ended.
      if (files.readRelay() != null) return null;
      return exitCodeOfHandle(process);
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return null;
}

/// `yagurad relay --run-dir <dir>`: starts the server on the relay's own
/// console, copies its output to the instance's rotating capture, records its
/// identity and exit, and outlives the daemon.
///
/// Windows only.
Future<int> runRelayMode(String runDirectory, StringSink err) async {
  try {
    return await _runRelay(runDirectory, err);
  } on Object catch (e, stack) {
    // The relay's console is hidden: the run's exit file is the only place
    // the daemon can learn why it ended.
    err.writeln('relay failed: $e\n$stack');
    try {
      RunFiles(runDirectory)
          .writeExit(-1, DateTime.now(), error: 'the relay failed: $e');
    } on Object {
      // Nothing more can be said.
    }
    return helperFailed;
  }
}

Future<int> _runRelay(String runDirectory, StringSink err) async {
  final win32 = Win32.instance;
  final files = RunFiles(runDirectory);
  final launch = files.readLaunch();
  if (launch == null) {
    err.writeln('relay: $runDirectory has no readable launch.json');
    return helperFailed;
  }
  // The launcher always sends the line; without it the secret arguments have
  // no value, and a server started without them would run unprotected or
  // half-configured.
  final input = readLaunchInput();
  if (input == null) {
    files.writeExit(
      -1,
      DateTime.now(),
      error: 'the relay did not receive its secrets (launch_input_missing)',
    );
    err.writeln('relay: launch_input_missing');
    return helperFailed;
  }
  final missing = [
    for (final s in launch.secretArguments)
      if (!input.secrets.containsKey(s.setting)) s.setting,
  ];
  if (missing.isNotEmpty) {
    files.writeExit(
      -1,
      DateTime.now(),
      error: 'the relay did not receive the secret ${missing.first}',
    );
    return helperFailed;
  }

  // Ctrl+C sent to this console is for the server: the relay stays up.
  win32.setConsoleCtrlHandler(nullptr, 0);
  final sigint = ProcessSignal.sigint.watch().listen((_) {});

  final self = identityOfPid(pid);
  if (self == null) {
    await sigint.cancel();
    return helperFailed;
  }
  files.writeRelay(self);
  // The supervisor gave up on this launch before the server was started.
  if (files.isCancelled) {
    files.writeExit(
      -1,
      DateTime.now(),
      error: 'the launch was cancelled before the server was started',
    );
    await sigint.cancel();
    return helperFailed;
  }

  final pipeRead = calloc<IntPtr>();
  final pipeWrite = calloc<IntPtr>();
  final security = calloc<Uint8>(Win32.securityAttributesSize);
  (security).cast<Uint32>().value = Win32.securityAttributesSize;
  (security + 16).cast<Int32>().value = 1;
  final namePointer = 'NUL'.toNativeUtf16();
  var nul = 0;
  SpawnedProcess? server;
  try {
    if (win32.createPipe(pipeRead, pipeWrite, security.cast(), 0) == 0) {
      files.writeExit(-1, DateTime.now(), error: 'CreatePipe failed');
      return helperFailed;
    }
    // The relay's read end must not leak into the server.
    win32.setHandleInformation(pipeRead.value, Win32.handleFlagInherit, 0);
    nul = win32.createFile(
      namePointer,
      Win32.genericRead,
      Win32.fileShareReadWrite,
      security.cast(),
      Win32.openExisting,
      0,
      0,
    );

    try {
      // No console or group flags: the server shares the relay's console, so
      // a Ctrl+C sent to it reaches the server (spike 1.3).
      server = spawnProcess(
        executable: launch.executable,
        args: launch.resolvedArgs(input.secrets),
        workingDirectory: launch.workingDirectory,
        inheritHandles: true,
        // Only the server's own standard handles: not the relay's input pipe.
        handles: [if (nul != Win32.invalidHandle) nul, pipeWrite.value],
        stdin: nul == Win32.invalidHandle ? null : nul,
        stdout: pipeWrite.value,
        stderr: pipeWrite.value,
      );
    } on SpawnFailure catch (e) {
      files.writeExit(-1, DateTime.now(), error: e.message);
      return helperFailed;
    } finally {
      win32.closeHandle(pipeWrite.value);
      if (nul != 0 && nul != Win32.invalidHandle) win32.closeHandle(nul);
    }

    final serverIdentity = identityOfHandle(server.handle, server.pid);
    if (serverIdentity == null) {
      files.writeExit(-1, DateTime.now(), error: 'the server vanished');
      return helperFailed;
    }
    files.writeRelayAndServer(self, serverIdentity);
    // The record comes first, then the check: a supervisor that cancels after
    // this check has already seen the server in `relay.json` (or sees it
    // when it looks next) and ends it.
    if (files.isCancelled) {
      win32.terminateProcess(server.handle, 1);
      files.writeExit(
        -1,
        DateTime.now(),
        error: 'the launch was cancelled; the server was ended',
      );
      return helperFailed;
    }

    final capture = CaptureWriter.open(
      CaptureWriter.directoryFor(launch.instanceDirectory),
      encoding: LogEncoding.parse(launch.stdoutEncoding) ?? LogEncoding.utf8,
    );
    try {
      final buffer = calloc<Uint8>(_chunk);
      final available = calloc<Uint32>();
      final read = calloc<Uint32>();
      try {
        void drain() {
          while (true) {
            if (win32.peekNamedPipe(
                  pipeRead.value,
                  nullptr,
                  0,
                  nullptr,
                  available,
                  nullptr,
                ) ==
                0) {
              return;
            }
            if (available.value == 0) return;
            final want = available.value < _chunk ? available.value : _chunk;
            if (win32.readFile(pipeRead.value, buffer, want, read, nullptr) ==
                0) {
              return;
            }
            if (read.value == 0) return;
            capture.write(Uint8List.fromList(buffer.asTypedList(read.value)));
          }
        }

        while (!processEnded(server.handle)) {
          drain();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        // What the server wrote last, and what its children still hold open,
        // is read without waiting for the pipe to close.
        drain();
        files.writeExit(exitCodeOfHandle(server.handle), DateTime.now());
      } finally {
        calloc.free(buffer);
        calloc.free(available);
        calloc.free(read);
      }
    } finally {
      capture.close();
    }
    return helperOk;
  } finally {
    if (server != null) win32.closeHandle(server.handle);
    win32.closeHandle(pipeRead.value);
    calloc.free(pipeRead);
    calloc.free(pipeWrite);
    calloc.free(security);
    calloc.free(namePointer);
    await sigint.cancel();
  }
}

const _chunk = 64 * 1024;

/// `yagurad signal --console-of <pid>`: attaches to the console of [target]
/// and sends it Ctrl+C. Exits non-zero when the console cannot be attached.
/// With [created], the process must have started at that time: a PID that was
/// reused is not signalled. The handle stays open until the signal is sent, so
/// the PID cannot be reused in between.
///
/// Windows only.
Future<int> runSignalMode(int target, {int? created}) async {
  final win32 = Win32.instance;
  var guard = 0;
  if (created != null) {
    guard = win32.openProcess(Win32.processQueryLimitedInformation, 0, target);
    if (guard == 0) return helperFailed;
    if (identityOfHandle(guard, target)?.created != created) {
      win32.closeHandle(guard);
      return helperFailed;
    }
  }
  try {
    win32.freeConsole();
    if (win32.attachConsole(target) == 0) return helperFailed;
    // The helper shares the console it signals, so it ignores the Ctrl+C
    // itself.
    win32.setConsoleCtrlHandler(nullptr, 1);
    final sent = win32.generateConsoleCtrlEvent(0, 0);
    win32.freeConsole();
    return sent == 0 ? helperFailed : helperOk;
  } finally {
    if (guard != 0) win32.closeHandle(guard);
  }
}
