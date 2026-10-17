import 'dart:async';
import 'dart:io';

import 'package:yagura_plugin/yagura_plugin.dart';

import '../process/process_host.dart';
import 'instance.dart';

/// How the start-time health wait ended (design D2/D3, `instance-lifecycle`).
sealed class HealthOutcome {
  const HealthOutcome();
}

/// The check passed.
class HealthPassed extends HealthOutcome {
  const HealthPassed();
}

/// `start_timeout` passed with the process still alive: the instance runs
/// with `health: unknown`.
class HealthTimedOut extends HealthOutcome {
  const HealthTimedOut();
}

/// The process ended inside the window.
class HealthProcessExited extends HealthOutcome {
  const HealthProcessExited(this.exitCode);
  final int exitCode;
}

/// Stop or cancellation interrupted the wait.
class HealthInterrupted extends HealthOutcome {
  const HealthInterrupted();
}

/// A `log_match` watch over one log source, opened before the server is
/// launched so that only lines written by this run count (task 7.3).
abstract interface class LogMatchWatch {
  /// Reads what the source has gained and reports whether a line written
  /// since the watch opened matched.
  Future<bool> check();

  Future<void> close();
}

/// The start-time health evaluator. `process` and `port` are checked here;
/// `log_match` through [evaluate]'s `logMatch` probe, a [LogMatchWatch]
/// opened before the launch. Without a probe (no log hub) a manifest with it
/// is held to the `process` check.
class HealthEvaluator {
  HealthEvaluator({
    this.pollInterval = const Duration(milliseconds: 250),
    this.settle = const Duration(seconds: 2),
  });

  /// How often a port or probe is tried.
  final Duration pollInterval;

  /// How long the process must stay alive for the `process` check to pass,
  /// so a bootstrapper that spawns the real server and exits is caught.
  final Duration settle;

  /// Waits until the check passes, `start_timeout` ends, the process exits
  /// or [cancelled] completes, whichever comes first.
  Future<HealthOutcome> evaluate({
    required HealthSpec spec,
    required List<PortAssignment> ports,
    required RunningServer server,
    required Future<void> cancelled,
    Future<bool> Function()? logMatch,
  }) async {
    final result = Completer<HealthOutcome>();
    var over = false;
    void finish(HealthOutcome outcome) {
      if (!result.isCompleted) result.complete(outcome);
    }

    server.exitCode.then<void>(
      (code) => finish(HealthProcessExited(code)),
      onError: (Object _) => finish(const HealthProcessExited(-1)),
    );
    cancelled.then<void>((_) => finish(const HealthInterrupted()));
    final timeout = Timer(
      Duration(seconds: spec.startTimeoutSeconds),
      () => finish(const HealthTimedOut()),
    );

    Future<void> poll(Future<bool> Function() probe) async {
      while (!over && !result.isCompleted) {
        bool passed;
        try {
          passed = await probe();
        } on Object {
          passed = false;
        }
        if (passed) {
          finish(const HealthPassed());
          return;
        }
        await Future<void>.delayed(pollInterval);
      }
    }

    switch (spec.type) {
      case HealthType.port:
        final port = ports.where((p) => p.name == spec.port).firstOrNull;
        if (port == null) {
          // The loader rejects a manifest that names no port; hold it to the
          // process check rather than waiting for nothing.
          unawaited(_settle(finish, () => over));
        } else {
          unawaited(poll(() => _portOpen(port)));
        }
      case HealthType.logMatch when logMatch != null:
        unawaited(poll(logMatch));
      case HealthType.process || HealthType.logMatch || HealthType.query:
        unawaited(_settle(finish, () => over));
    }

    try {
      return await result.future;
    } finally {
      over = true;
      timeout.cancel();
    }
  }

  Future<void> _settle(
    void Function(HealthOutcome) finish,
    bool Function() over,
  ) async {
    await Future<void>.delayed(settle);
    if (!over()) finish(const HealthPassed());
  }

  Future<bool> _portOpen(PortAssignment port) async {
    final protocol = port.protocol;
    if (protocol != PortProtocol.udp && await _tcpListening(port.number)) {
      return true;
    }
    if (protocol != PortProtocol.tcp) return _udpBound(port.number);
    return false;
  }

  Future<bool> _tcpListening(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  /// A UDP port cannot be connected to: the server holds it when this bind is
  /// refused.
  Future<bool> _udpBound(int port) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
      );
      socket.close();
      return false;
    } on SocketException {
      return true;
    }
  }
}
