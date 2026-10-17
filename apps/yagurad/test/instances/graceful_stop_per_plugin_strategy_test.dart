import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/process/process.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';

/// The `stop_requested_at` of the instance's newest run, read from SQLite.
int? stopRequestedAt(TestEnv env, String instanceId) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    final rows = db.sqlite.select(
      'SELECT stop_requested_at FROM runs WHERE instance_id = ? '
      'ORDER BY created_at DESC, rowid DESC',
      [instanceId],
    );
    return rows.isEmpty ? null : rows.first['stop_requested_at'] as int?;
  } finally {
    db.close();
  }
}

void main() {
  group('the stop sequence', () {
    const grace = Duration(milliseconds: 300);
    StopPlan plan({
      StopStrategy strategy = StopStrategy.signal,
      bool force = false,
      bool sendSignal = true,
    }) => StopPlan(
      strategy: strategy,
      grace: grace,
      force: force,
      sendSignal: sendSignal,
    );

    test('a process that exits after the signal ended gracefully', () async {
      final exited = Completer<void>();
      var killed = false;

      final by = await performStop(
        plan(),
        sendSignal: () async {
          Timer(const Duration(milliseconds: 50), exited.complete);
          return true;
        },
        kill: () async => killed = true,
        exited: exited.future,
      );

      expect(by, StoppedBy.graceful);
      expect(killed, isFalse);
    });

    test('a process alive after the grace period is killed', () async {
      final exited = Completer<void>();
      final watch = Stopwatch()..start();

      final by = await performStop(
        plan(),
        sendSignal: () async => true,
        kill: () async => exited.complete(),
        exited: exited.future,
      );

      expect(by, StoppedBy.kill);
      expect(watch.elapsed, greaterThanOrEqualTo(grace));
    });

    test('a failed signal is a failed graceful step', () async {
      for (final failure in <Future<bool> Function()>[
        () async => false,
        () async => throw StateError('attach failed'),
      ]) {
        final exited = Completer<void>();
        final watch = Stopwatch()..start();

        final by = await performStop(
          plan(),
          sendSignal: failure,
          kill: () async => exited.complete(),
          exited: exited.future,
        );

        // The grace period still runs, then the kill (design D2).
        expect(by, StoppedBy.kill);
        expect(watch.elapsed, greaterThanOrEqualTo(grace));
      }
    });

    test('strategy kill and a forced stop skip the signal', () async {
      for (final p in [plan(strategy: StopStrategy.kill), plan(force: true)]) {
        final exited = Completer<void>();
        var signalled = false;

        final by = await performStop(
          p,
          sendSignal: () async => signalled = true,
          kill: () async => exited.complete(),
          exited: exited.future,
        );

        expect(by, StoppedBy.kill);
        expect(signalled, isFalse);
      }
    });

    test('a resumed stop sends no second signal', () async {
      final exited = Completer<void>();
      var signalled = false;

      final by = await performStop(
        plan(sendSignal: false),
        sendSignal: () async => signalled = true,
        kill: () async => exited.complete(),
        exited: exited.future,
      );

      expect(by, StoppedBy.kill);
      expect(signalled, isFalse);
    });
  });

  test('stop_requested_at_is_written_before_the_strategy', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    int? writtenWhenSent;
    env.process.onStop = (server, plan) {
      writtenWhenSent = stopRequestedAt(env, instance.id);
    };

    final done = await runStop(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded);
    expect(writtenWhenSent, isNotNull);
    expect(stopRequestedAt(env, instance.id), writtenWhenSent);
  });

  test('a_stop_that_needed_the_kill_reports_stopped_by_kill', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    env.process.stopFailsGracefully = true;

    final done = await runStop(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded);
    expect(done.resultReason, 'stopped_by:kill');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test(
    'grace_period_exceeded',
    () async {
      // A server that ignores Ctrl+C, with a 1 s grace period.
      final rig = await ProcessRig.create(
        serverArgs: ['--ignore-ctrl-c'],
        graceSeconds: 1,
      );
      final daemon = await rig.start();
      final instance = await rig.createRunning(daemon);
      final pid = instance.pid;
      expect(processAlive(pid), isTrue);
      final watch = Stopwatch()..start();

      final done = await runStop(daemon, instance.id);

      expect(done.status, OperationStatus.succeeded);
      expect(done.resultReason, 'stopped_by:kill');
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
      await eventually(() => !processAlive(pid), reason: 'the process to end');
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  test(
    'signal_stop_saves_before_the_process_exits',
    () async {
      final rig = await ProcessRig.create(graceSeconds: 20);
      final daemon = await rig.start();
      final instance = await rig.createRunning(daemon);
      expect(File(rig.stateFile(instance, 'saved.txt')).existsSync(), isFalse);

      final done = await runStop(daemon, instance.id);

      // Ctrl+C reached the server through the relay's console: it saved.
      expect(done.status, OperationStatus.succeeded);
      expect(done.resultReason, 'stopped_by:graceful');
      expect(File(rig.stateFile(instance, 'saved.txt')).existsSync(), isTrue);
      expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  test(
    'the_signal_helper_fails_for_a_missing_process',
    () async {
      final rig = await ProcessRig.create();

      // No console to attach to: the helper exits non-zero (spike 1.3).
      final exitCode = await rig.newHost().runSignalHelper(0x7ffffff0);

      expect(exitCode, isNot(0));
    },
    tags: ['windows'],
    skip: windowsOnly,
  );
}
