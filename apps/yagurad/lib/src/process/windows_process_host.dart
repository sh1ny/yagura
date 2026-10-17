import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../platform/win32.dart';
import '../platform/win32_process.dart';
import 'process_host.dart';
import 'run_files.dart';
import 'stop_engine.dart';

/// The Windows process host (design D2, ADR 0009): `launch`, `relay` and
/// `signal` run as modes of the helper executable, which is `yagurad` itself.
///
/// `launch` starts a relay outside the daemon's job; the relay starts the
/// server on its own console and outlives the daemon. A later daemon
/// re-attaches by PID, executable and start time.
class WindowsProcessHost implements ProcessHost {
  WindowsProcessHost({
    required this.helperExecutable,
    this.launchTimeout = const Duration(seconds: 30),
    this.signalTimeout = const Duration(seconds: 10),
    this.abandonTimeout = const Duration(seconds: 30),
  });

  /// The `yagurad` executable the `launch` and `signal` modes run from.
  final String helperExecutable;

  /// How long `launch` waits for the relay to record the server.
  final Duration launchTimeout;

  /// How long a launch that timed out waits for its relay to end it.
  final Duration abandonTimeout;

  /// How long the `signal` helper may take.
  final Duration signalTimeout;

  final _servers = <_WindowsServer>{};

  @override
  Future<RunningServer> launch(LaunchRequest request) async {
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
    final files = RunFiles(request.runDirectory);
    files.writeLaunch(request);

    final helper = await Process.start(helperExecutable, [
      'launch',
      '--run-dir',
      request.runDirectory,
    ], environment: request.env);
    final stderrText = helper.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    unawaited(helper.stdout.drain<void>());
    final code = await helper.exitCode;
    if (code != 0) {
      throw YaguraException(
        'launch_failed',
        'could not start ${request.executable}: '
            '${(await stderrText).trim().ifEmpty('the launch helper exited with code $code')}',
        details: {'instanceId': request.instanceId},
      );
    }

    // The relay records its server before it starts reading its output.
    final deadline = DateTime.now().add(launchTimeout);
    while (true) {
      final relay = files.readRelay();
      if (relay?.server case final identity?) {
        final server = _attach(identity, relay!.relay, request.runDirectory);
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
      if (DateTime.now().isAfter(deadline)) {
        // The relay may still start the server: end the launch first, so a
        // failed Start leaves no server behind.
        await _abandon(files);
        throw YaguraException(
          'launch_failed',
          'the relay did not report the server of ${request.executable} '
              'within ${launchTimeout.inSeconds} s '
              '(${relay == null ? 'no relay.json' : 'relay.json names server '
                        '${relay.server?.pid}, which could not be opened'})',
          details: {'instanceId': request.instanceId},
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Ends a launch nobody waits for. The relay is told not to start a server
  /// (or to end one it starts), and a server it already recorded is
  /// terminated here; returns once the relay has settled, or after
  /// [abandonTimeout].
  Future<void> _abandon(RunFiles files) async {
    files.writeCancel();
    final deadline = DateTime.now().add(abandonTimeout);
    ProcessIdentity? ended;
    while (true) {
      final relay = files.readRelay();
      if (relay?.server case final server? when server.pid != ended?.pid) {
        ended = server;
        await terminate(server);
      }
      if (files.readExitCode() != null || files.readError() != null) return;
      if (relay != null && !await isAlive(relay.relay)) return;
      if (DateTime.now().isAfter(deadline)) {
        if (relay != null) await terminate(relay.relay);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// A server object for the live process with exactly [identity], or null.
  _WindowsServer? _attach(
    ProcessIdentity identity,
    ProcessIdentity? relay,
    String runDirectory,
  ) {
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
    final server = _WindowsServer(identity, relay, handle, DateTime.now(), (
      server,
    ) {
      _servers.remove(server);
    });
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
        // console's owner and to outlive Ctrl+C. A recorded relay whose PID
        // was reused is not that console: the server's own is used then.
        final recorded = windows.relay;
        final target = recorded != null && await isAlive(recorded)
            ? recorded
            : windows.identity;
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
    ProcessIdentity identity, {
    ProcessIdentity? relay,
    String runDirectory = '',
  }) async => _attach(identity, relay, runDirectory);

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
      if (actual != null && _same(actual, identity)) {
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
    void Function(_WindowsServer) onClosed,
  ) : _handle = rawHandle,
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

  final void Function(_WindowsServer) _onClosed;
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
