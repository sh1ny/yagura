import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/instance_fs.dart';
import '../platform/win32.dart';
import '../platform/win32_logon.dart';
import '../platform/win32_process.dart';
import 'launcher_modes.dart';
import 'process_host.dart';
import 'profile_hold.dart';
import 'process_verifier.dart';
import 'run_files.dart';
import 'stop_engine.dart';

/// The game-server account servers run as (design D7).
class ServerAccount {
  const ServerAccount({required this.name, required this.password});

  final String name;

  /// The account's stored password, or null when there is none yet.
  final String? Function() password;

  /// What the launcher gets on its standard input; null without a password.
  AccountCredentials? credentials() {
    final secret = password();
    return secret == null ? null : AccountCredentials(name, secret);
  }
}

/// The Windows process host (design D2, ADR 0009): `launch`, `relay` and
/// `signal` run as modes of the helper executable, which is `yagurad` itself.
///
/// `launch` starts a relay outside the daemon's job; the relay starts the
/// server on its own console and outlives the daemon. A later daemon
/// re-attaches by PID, executable and start time, after the process
/// verification of design D9: the token user, the parentage and the start
/// order, because the run files are written by the account the server runs as.
class WindowsProcessHost implements ProcessHost {
  WindowsProcessHost({
    required this.helperExecutable,
    this.launchTimeout = const Duration(seconds: 30),
    this.signalTimeout = const Duration(seconds: 10),
    this.abandonTimeout = const Duration(seconds: 30),
    this.launcherTimeout = const Duration(minutes: 2),
    this.account,
    ProcessVerifier? verifier,
    ProfileHold? profileHold,
  }) : verifier = verifier ?? ProcessVerifier(),
       profileHold = profileHold ?? _holdFor(account);

  /// The `yagurad` executable the `launch` and `signal` modes run from.
  final String helperExecutable;

  /// How long `launch` waits for the relay to record the server.
  final Duration launchTimeout;

  /// How long a launch that timed out waits for its relay to end it.
  final Duration abandonTimeout;

  /// How long the `signal` helper may take.
  final Duration signalTimeout;

  /// How long the launcher may take, the first profile load of a new account
  /// included (about 24 s, spike S2).
  final Duration launcherTimeout;

  /// The game-server account servers run as; null runs them as the current
  /// user (development mode).
  final ServerAccount? account;

  /// Checks a process against its run record before the daemon signals,
  /// terminates or re-attaches it (design D9).
  final ProcessVerifier verifier;

  /// Keeps the game-server account's profile loaded from before a launch
  /// starts the launcher until the last server of the account has ended
  /// (design D7); null in development mode.
  final ProfileHold? profileHold;

  final _servers = <_WindowsServer>{};

  static ProfileHold? _holdFor(ServerAccount? account) => account == null
      ? null
      : ProfileHold(() {
          final secret = account.password();
          if (secret == null) {
            throw StateError('the account ${account.name} has no password');
          }
          return loadAccountProfile(account.name, secret);
        });

  @override
  Future<RunningServer> launch(LaunchRequest request) async {
    try {
      return await _launch(request);
    } on YaguraException catch (e) {
      // The service's error log is where an operator (and a failed CI row)
      // looks first; the operation carries the same text to the client.
      stderr.writeln(
        'yagurad: launch of ${request.executable} (instance '
        '${request.instanceId}, run ${request.runId}) failed: '
        '${e.reason}: ${e.message}',
      );
      rethrow;
    }
  }

  Future<RunningServer> _launch(LaunchRequest request) async {
    if (request.runDirectory.isEmpty) {
      throw YaguraException(
        'launch_failed',
        'the launch of ${request.executable} has no run directory',
      );
    }
    // `launch`, `relay` and `signal` are modes of the compiled yagurad; under
    // `dart run` the executable is the Dart VM, which has no such commands.
    if (const {
      'dart',
      'dartvm',
    }.contains(p.basenameWithoutExtension(helperExecutable).toLowerCase())) {
      throw YaguraException(
        'launch_failed',
        'servers can only be started by the compiled yagurad (build it with '
            '`dart build cli`); this daemon runs on the Dart VM '
            '($helperExecutable)',
        details: {'instanceId': request.instanceId},
      );
    }
    final files = RunFiles(
      request.runDirectory,
      fs: InstanceFs(request.instanceDirectory),
    );
    files.writeLaunch(request);

    final credentials = account?.credentials();
    if (account != null && credentials == null) {
      throw YaguraException(
        'launch_logon_failed',
        'the account ${account!.name} has no stored password yet',
        details: {'instanceId': request.instanceId},
      );
    }
    final hold = profileHold;
    if (hold == null) return _launchWith(request, files, credentials);
    // The launcher's own profile load ends before the relay starts the server.
    try {
      hold.retain();
    } on LogonFailure catch (e) {
      throw YaguraException(
        'launch_logon_failed',
        'the account ${account?.name ?? e.account} could not be logged on: '
            '${launcherFailureText(e)}',
        details: {'instanceId': request.instanceId},
      );
    }
    try {
      return await _launchWith(request, files, credentials);
    } finally {
      hold.release();
    }
  }

  Future<RunningServer> _launchWith(
    LaunchRequest request,
    RunFiles files,
    AccountCredentials? credentials,
  ) async {
    final helper = await Process.start(helperExecutable, [
      'launch',
      '--run-dir',
      request.runDirectory,
      if (credentials != null) '--as-account',
    ], environment: request.env);
    final launcher = identityOfPid(helper.pid);
    // The password and the secret launch arguments go by standard input:
    // arguments and the environment are readable by other processes. The line
    // is written on every launch, so the launcher can tell a missing one.
    helper.stdin.writeln(
      LaunchInput(credentials: credentials, secrets: request.secrets).encode(),
    );
    unawaited(helper.stdin.done.then<void>((_) {}, onError: (Object _) {}));
    // The launcher may end before it reads the line (a refused logon): the
    // broken pipe is its exit code's business, not an error of this write.
    unawaited(
      helper.stdin
          .flush()
          .then<void>((_) {}, onError: (Object _) {})
          .then(
            (_) =>
                helper.stdin.close().then<void>((_) {}, onError: (Object _) {}),
          ),
    );
    final stderrText = helper.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final stdoutText = helper.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final int code;
    try {
      code = await helper.exitCode.timeout(launcherTimeout);
    } on TimeoutException {
      helper.kill();
      // The launcher may have started the relay before it was killed. The
      // operating system says which process that is (its child), and the
      // launch is abandoned like any other: the relay is told to end, ends a
      // server it started, and is terminated if it does not settle. Without
      // an answer the cancel file alone keeps a relay that has not passed its
      // last check from keeping a server.
      try {
        final relay = launcher == null
            ? null
            : verifier.relayStartedBy(launcher, executable: helperExecutable);
        if (relay == null) {
          files.writeCancel();
        } else {
          await abandonLaunch(files, relay);
        }
      } on Object {
        // The launch fails either way.
      }
      throw YaguraException(
        'launch_failed',
        'the launcher did not finish within ${launcherTimeout.inSeconds} s',
        details: {'instanceId': request.instanceId},
      );
    }
    if (code == helperLogonFailed) {
      final detail = (await stderrText).trim();
      throw YaguraException(
        'launch_logon_failed',
        'the account ${account?.name ?? ''} could not be logged on: '
            '${detail.ifEmpty('the launcher exited with code $code')}',
        details: {'instanceId': request.instanceId},
      );
    }
    if (code != 0) {
      throw YaguraException(
        'launch_failed',
        'could not start ${request.executable}: '
            '${(await stderrText).trim().ifEmpty('the launch helper exited with code $code')}',
        details: {'instanceId': request.instanceId},
      );
    }
    // The launcher is the daemon's own child, so what it reports is the
    // daemon's record of the relay (design D9); relay.json is not.
    final launched = _relayReported(await stdoutText);
    if (launched != null) request.onRelayStarted?.call(launched);
    final relayHandle = launched == null ? 0 : _openForExit(launched);

    // The relay records its server before it starts reading its output.
    final deadline = DateTime.now().add(launchTimeout);
    try {
      while (true) {
        final relay = files.readRelay();
        if (relay?.server case final claimed?) {
          final server = _attachVerified(claimed, launched ?? relay!.relay);
          if (server != null) return server;
        }
        if (files.readError() case final error?) {
          throw YaguraException(
            'launch_failed',
            'could not start ${request.executable}: $error',
            details: {'instanceId': request.instanceId},
          );
        }
        // The server ended before it could be opened: the relay has its code.
        if (files.readExitCode() case final code?) {
          throw YaguraException(
            'launch_failed',
            '${request.executable} exited with exit code $code as it started',
            details: {'instanceId': request.instanceId},
          );
        }
        // A relay that ended without a word (it exits `helperFailed` when it
        // cannot read launch.json, and its stderr is on a hidden console):
        // its exit code is all there is (spike S2).
        if (relayHandle != 0 &&
            processEnded(relayHandle) &&
            files.readRelay()?.server == null) {
          throw YaguraException(
            'launch_failed',
            'the relay of ${request.executable} exited with code '
                '${exitCodeOfHandle(relayHandle)} before it started the server',
            details: {'instanceId': request.instanceId},
          );
        }
        if (DateTime.now().isAfter(deadline)) {
          // The relay may still start the server: end the launch first, so a
          // failed Start leaves no server behind.
          await abandonLaunch(files, launched);
          throw YaguraException(
            'launch_failed',
            'the relay did not report the server of ${request.executable} '
                'within ${launchTimeout.inSeconds} s '
                '(${relay == null ? 'no relay.json' : 'relay.json names server '
                          '${relay.server?.pid}, which could not be verified'})',
            details: {'instanceId': request.instanceId},
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      if (relayHandle != 0) Win32.instance.closeHandle(relayHandle);
    }
  }

  /// The relay the launcher reported on its standard output, with its
  /// executable looked up; null when it printed no usable line.
  ProcessIdentity? _relayReported(String output) {
    for (final line in const LineSplitter().convert(output)) {
      try {
        final json = jsonDecode(line);
        if (json is Map && json['relay_pid'] is int) {
          final identity = identityOfPid(json['relay_pid'] as int);
          final created = json['relay_created'];
          if (identity != null &&
              (created == null || created == identity.created)) {
            return identity;
          }
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// A handle that tells whether the relay [identity] has ended, or 0.
  int _openForExit(ProcessIdentity identity) {
    final win32 = Win32.instance;
    final handle = win32.openProcess(
      Win32.processQueryLimitedInformation | Win32.synchronize,
      0,
      identity.pid,
    );
    if (handle == 0) return 0;
    final actual = identityOfHandle(handle, identity.pid);
    if (actual == null || !_same(actual, identity)) {
      win32.closeHandle(handle);
      return 0;
    }
    return handle;
  }

  /// Ends a launch nobody waits for. The relay is told not to start a server
  /// (or to end one it starts), and a server it already recorded is
  /// terminated here; returns once the relay has settled, or after
  /// [abandonTimeout].
  Future<void> abandonLaunch(RunFiles files, ProcessIdentity? launched) async {
    files.writeCancel();
    final deadline = DateTime.now().add(abandonTimeout);
    ProcessIdentity? ended;
    while (true) {
      final relay = files.readRelay();
      final relayId = launched ?? relay?.relay;
      if (relay?.server case final claimed? when claimed.pid != ended?.pid) {
        ended = claimed;
        // relay.json is the account's to write: only a server the launched
        // relay really started (or that relay's own child) is ended, never
        // whatever the file names (design D9).
        final verified = switch (verifier.verify(claimed, launched)) {
          ServerVerified(:final server) => server,
          ServerFoundByFallback(:final server) => server,
          ServerGone() || RecordRejected() => null,
        };
        if (verified != null) await terminate(verified);
      }
      if (files.readExitCode() != null || files.readError() != null) return;
      if (relayId != null && !await isAlive(relayId)) return;
      if (DateTime.now().isAfter(deadline)) {
        if (relayId != null) await terminate(relayId);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// A server object for the process the run record names, when it is a
  /// verified server of [relay]; or, when the record names something else,
  /// the relay's own child running as the account (design D9). Null when no
  /// server can be vouched for.
  _WindowsServer? _attachVerified(
    ProcessIdentity claimed,
    ProcessIdentity? relay,
  ) => switch (verifier.verify(claimed, relay)) {
    ServerVerified(:final server) => _attach(server, relay, rejected: false),
    ServerFoundByFallback(:final server) => _attach(
      server,
      relay,
      rejected: true,
    ),
    ServerGone() || RecordRejected() => null,
  };

  /// A server object for the live process with exactly [identity], or null.
  _WindowsServer? _attach(
    ProcessIdentity identity,
    ProcessIdentity? relay, {
    required bool rejected,
  }) {
    final win32 = Win32.instance;
    // Terminate access is for the kill step of a stop.
    final handle = win32.openProcess(
      Win32.processQueryLimitedInformation |
          Win32.synchronize |
          Win32.processTerminate,
      0,
      identity.pid,
    );
    if (handle == 0) return null;
    final actual = identityOfHandle(handle, identity.pid);
    if (actual == null || !_same(actual, identity) || processEnded(handle)) {
      win32.closeHandle(handle);
      return null;
    }
    // The server holds its account's profile until it ends, not while the
    // daemon only lets go of it: a running server keeps needing its hive.
    final hold = profileHold;
    var held = false;
    if (hold != null) {
      try {
        hold.retain();
        held = true;
      } on Object catch (e) {
        stderr.writeln(
          'yagurad: the profile of ${account?.name ?? 'the server account'} '
          'could not be loaded for server ${identity.pid}: $e',
        );
      }
    }
    final server = _WindowsServer(
      identity,
      relay,
      handle,
      DateTime.now(),
      _servers.remove,
      recordRejected: rejected,
      onEnded: held ? hold!.release : null,
    );
    _servers.add(server);
    return server;
  }

  static bool _same(ProcessIdentity a, ProcessIdentity b) =>
      a.pid == b.pid &&
      a.created == b.created &&
      sameExecutable(a.executable, b.executable);

  @override
  Future<StoppedBy> stop(RunningServer server, StopPlan plan) async {
    final windows = server as _WindowsServer;
    return performStop(
      plan,
      sendSignal: () async {
        // Relay and server share one console; the relay is certain to be the
        // console's owner and to outlive Ctrl+C. A recorded relay that is not
        // a live process of the account (its PID was reused, or the record
        // was forged) is not that console: the server's own is used then.
        final recorded = windows.relay;
        final target = recorded != null && verifier.isOurs(recorded)
            ? recorded
            : windows.identity;
        // Nothing is signalled that does not run as the account.
        if (!verifier.isOurs(target)) return false;
        return await runSignalHelper(target.pid, created: target.created) == 0;
      },
      kill: () async {
        Win32.instance.terminateProcess(windows.handle, 1);
      },
      exited: windows.exitCode,
    );
  }

  /// Runs `yagurad signal --console-of <pid>` detached from any console and
  /// returns its exit code; -1 when it did not finish in [signalTimeout].
  /// With [created] (the process's start time) the helper refuses a process
  /// that is not the one meant, also when the PID was reused after the caller
  /// looked.
  Future<int> runSignalHelper(int pid, {int? created}) async {
    final win32 = Win32.instance;
    final SpawnedProcess helper;
    try {
      helper = spawnProcess(
        executable: helperExecutable,
        args: [
          'signal',
          '--console-of',
          '$pid',
          if (created != null) ...['--created', '$created'],
        ],
        flags: Win32.detachedProcess,
      );
    } on SpawnFailure {
      return -1;
    }
    try {
      final deadline = DateTime.now().add(signalTimeout);
      while (!processEnded(helper.handle)) {
        if (DateTime.now().isAfter(deadline)) {
          win32.terminateProcess(helper.handle, 1);
          return -1;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return exitCodeOfHandle(helper.handle);
    } finally {
      win32.closeHandle(helper.handle);
    }
  }

  @override
  Future<RunningServer?> reattach(
    ProcessIdentity? identity, {
    ProcessIdentity? relay,
    String runDirectory = '',
  }) async {
    switch (verifier.verify(identity, relay)) {
      case ServerVerified(:final server):
        return _attach(server, relay, rejected: false);
      case ServerFoundByFallback(:final server):
        return _attach(server, relay, rejected: true);
      case ServerGone():
        return null;
      case RecordRejected(:final why):
        throw YaguraException(
          'run_record_rejected',
          'the run record names no verified server ($why); nothing was '
              'terminated; relay ${relay?.pid ?? 0}',
          details: {'relayPid': relay?.pid ?? 0},
        );
    }
  }

  @override
  Future<bool> isAlive(ProcessIdentity identity) async {
    final win32 = Win32.instance;
    final handle = win32.openProcess(
      Win32.processQueryLimitedInformation | Win32.synchronize,
      0,
      identity.pid,
    );
    if (handle == 0) return false;
    try {
      final actual = identityOfHandle(handle, identity.pid);
      return actual != null && _same(actual, identity) && !processEnded(handle);
    } finally {
      win32.closeHandle(handle);
    }
  }

  @override
  Future<void> terminate(ProcessIdentity identity) async {
    final win32 = Win32.instance;
    final handle = win32.openProcess(
      Win32.processQueryLimitedInformation |
          Win32.synchronize |
          Win32.processTerminate,
      0,
      identity.pid,
    );
    if (handle == 0) return;
    try {
      final actual = identityOfHandle(handle, identity.pid);
      // Only a process of the game-server account is ended, whatever a run
      // file claims (design D9).
      if (actual != null &&
          _same(actual, identity) &&
          verifier.runsAsAccount(identity.pid)) {
        win32.terminateProcess(handle, 1);
      }
    } finally {
      win32.closeHandle(handle);
    }
  }

  @override
  void release(RunningServer server) {
    if (server is _WindowsServer) server.release();
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A server the host supervises through a process handle. Its exit is polled:
/// the process is usually not a child of this daemon.
class _WindowsServer implements RunningServer {
  _WindowsServer(
    this.identity,
    this.relay,
    int rawHandle,
    this.startedAt,
    void Function(_WindowsServer) onClosed, {
    this.recordRejected = false,
    this.onEnded,
  }) : _handle = rawHandle,
       _onClosed = onClosed {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_handle != 0 && processEnded(_handle)) _ended();
    });
  }

  @override
  final ProcessIdentity identity;

  @override
  final ProcessIdentity? relay;

  @override
  final DateTime startedAt;

  @override
  final bool recordRejected;

  final void Function(_WindowsServer) _onClosed;

  /// Called once, when the process has ended (not when it is released).
  final void Function()? onEnded;
  final _exit = Completer<int>();
  late final Timer _timer;
  int _handle;

  int get handle => _handle;

  @override
  int get pid => identity.pid;

  @override
  String get executable => identity.executable;

  @override
  Future<int> get exitCode => _exit.future;

  void _ended() {
    if (_exit.isCompleted) return;
    _exit.complete(exitCodeOfHandle(_handle));
    release();
    onEnded?.call();
  }

  /// Stops polling and closes the handle; the process keeps running.
  void release() {
    _timer.cancel();
    if (_handle != 0) {
      Win32.instance.closeHandle(_handle);
      _handle = 0;
    }
    _onClosed(this);
  }
}
