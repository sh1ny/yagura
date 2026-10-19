import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/process/process.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';

/// The run directories of an instance.
List<Directory> runDirectories(Instance instance) {
  final root = Directory(RunFiles.rootFor(instance.directory));
  if (!root.existsSync()) return const [];
  return root.listSync().whereType<Directory>().toList();
}

/// Runs [sql] on the daemon's database while no daemon has it open.
void editDatabase(TestEnv env, String sql, List<Object?> parameters) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    db.sqlite.execute(sql, parameters);
  } finally {
    db.close();
  }
}

String runState(TestEnv env, String instanceId) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    return db.sqlite.select(
          'SELECT state FROM runs WHERE instance_id = ? '
          'ORDER BY created_at DESC, rowid DESC',
          [instanceId],
        ).first['state']!
        as String;
  } finally {
    db.close();
  }
}

/// Lets `launch` complete, then never returns: the daemon is "killed" while
/// the start is still unrecorded.
class _LaunchThenHang implements ProcessHost {
  _LaunchThenHang(this.inner);

  final ProcessHost inner;
  final launched = Completer<RunningServer>();

  @override
  Future<RunningServer> launch(LaunchRequest request) async {
    final server = await inner.launch(request);
    launched.complete(server);
    await Completer<void>().future;
    return server;
  }

  @override
  Future<StoppedBy> stop(RunningServer server, StopPlan plan) =>
      inner.stop(server, plan);

  @override
  Future<RunningServer?> reattach(
    ProcessIdentity identity, {
    ProcessIdentity? relay,
    String runDirectory = '',
  }) => inner.reattach(identity, relay: relay, runDirectory: runDirectory);

  @override
  Future<bool> isAlive(ProcessIdentity identity) => inner.isAlive(identity);

  @override
  Future<void> terminate(ProcessIdentity identity) => inner.terminate(identity);

  @override
  void release(RunningServer server) => inner.release(server);
}

void main() {
  test(
    're_attach_after_daemon_restart',
    () async {
      final rig = await ProcessRig.create();
      final first = await rig.start();
      final instance = await rig.createRunning(first);
      final pid = instance.pid;
      expect(runDirectories(instance), hasLength(1));

      // The daemon dies; the relay and the server do not.
      await rig.env.kill(first);
      expect(processAlive(pid), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      final second = await rig.start();

      final after = second.instances.get(instance.id);
      expect(after.state, InstanceState.running);
      expect(after.pid, pid, reason: 'the same server, not a new one');
      expect(runDirectories(instance), hasLength(1));
      // The log stream resumes from the recorded offsets: what the server
      // wrote while the daemon was down is there.
      await second.logs.pollNow(instance.id);
      final lines = second.logs
          .backlog(instance.id, lines: 100)
          .entries
          .map((e) => e.text)
          .toList();
      expect(lines, contains('Game server connected'));
      expect(
        lines,
        contains('tick 20'),
        reason: 'written while the daemon was down',
      );
      // It is supervised again: a stop reaches it through Ctrl+C.
      final done = await runStop(second, instance.id);
      expect(done.resultReason, 'stopped_by:graceful');
      expect(File(rig.stateFile(instance, 'saved.txt')).existsSync(), isTrue);
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  test(
    'server_exit_while_the_daemon_is_down_keeps_its_exit_code',
    () async {
      final rig = await ProcessRig.create();
      final first = await rig.start();
      final instance = await rig.createRunning(first);
      final pid = instance.pid;
      await rig.env.kill(first);
      // The server ends while nobody supervises it; the relay records how.
      Process.killPid(pid);
      final exitFile = File(
        p.join(runDirectories(instance).single.path, 'exit.json'),
      );
      for (var i = 0; i < 100 && !exitFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        exitFile.existsSync(),
        isTrue,
        reason: 'the relay records the exit',
      );
      final recorded =
          (jsonDecode(exitFile.readAsStringSync()) as Map)['exit_code'] as int;

      final second = await rig.start();

      final db = sqlite3.open(
        p.join(rig.env.data, 'yagura.db'),
        mode: OpenMode.readOnly,
      );
      try {
        final run = db
            .select(
              'SELECT exit_code, end_reason FROM runs ORDER BY created_at, rowid',
            )
            .first;
        expect(run['exit_code'], recorded);
        expect(run['end_reason'], 'exited_while_daemon_down');
      } finally {
        db.close();
      }
      final lost = second.instances.recoveryNotices.singleWhere(
        (n) => n.kind == 'lost_while_daemon_down',
      );
      expect(lost.exitCode, recorded);
      expect(lost.message, contains('exited with code $recorded'));
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  test(
    'pid_reused_by_another_process',
    () async {
      final rig = await ProcessRig.create();
      final first = await rig.start();
      final instance = await rig.createInstalledFake(first);
      // `autostart` is off, so the lost server is not started again.
      first.instances.updateSettings(
        UpdateSettingsRequest(
          instanceId: instance.id,
          settings: valheimSettings(),
          autostart: false,
        ),
      );
      await runStart(first, instance.id);
      final pid = first.instances.get(instance.id).pid;
      await rig.env.kill(first);

      // The recorded PID now belongs to a process that started at another
      // time: the record's start time does not match.
      editDatabase(
        rig.env,
        'UPDATE runs SET server_created = server_created + 1 '
        'WHERE instance_id = ?',
        [instance.id],
      );
      final second = await rig.start();
      final lost = second.instances.recoveryNotices.where(
        (n) => n.kind == 'lost_while_daemon_down',
      );

      expect(second.instances.get(instance.id).state, InstanceState.stopped);
      expect(lost, hasLength(1));
      expect(
        processAlive(pid),
        isTrue,
        reason: 'the unrelated process is not touched',
      );

      // The same for a PID whose executable is another one.
      await runStart(second, instance.id);
      final pid2 = second.instances.get(instance.id).pid;
      await rig.env.kill(second);
      editDatabase(rig.env, 'UPDATE runs SET executable = ? WHERE state = ?', [
        r'C:\Windows\System32\notepad.exe',
        'running',
      ]);
      final third = await rig.start();

      expect(third.instances.get(instance.id).state, InstanceState.stopped);
      expect(processAlive(pid2), isTrue);
      expect(runState(rig.env, instance.id), 'ended');
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  test(
    'daemon_killed_during_a_start',
    () async {
      final rig = await ProcessRig.create();
      late _LaunchThenHang wrapper;
      final first = await rig.start(wrap: (h) => wrapper = _LaunchThenHang(h));
      final instance = await rig.createInstalledFake(first);

      // The start runs: the server is up, but the start never gets recorded
      // as running because the daemon dies first.
      first.instances.start(instance.id);
      final launched = await wrapper.launched.future;
      final pid = launched.pid;
      expect(runState(rig.env, instance.id), 'pending');
      await rig.env.kill(first);
      expect(processAlive(pid), isTrue);

      final second = await rig.start();

      // Found from the run directory: running with that process, and no second
      // server for the instance.
      final after = second.instances.get(instance.id);
      expect(after.state, InstanceState.running);
      expect(after.pid, pid);
      expect(runDirectories(instance), hasLength(1));
      expect(runState(rig.env, instance.id), 'running');
      final done = await runStop(second, instance.id);
      expect(done.resultReason, 'stopped_by:graceful');
    },
    tags: ['windows'],
    skip: windowsOnly,
  );

  group('with the fake process host', () {
    test('a_surviving_server_is_re_attached', () async {
      final env = TestEnv();
      env.installValheim();
      final first = await env.start();
      final instance = await createRunning(first);
      final server = env.process.servers.single;
      await env.kill(first);
      env.process.survivors.add(server);

      final second = await env.start();

      final after = second.instances.get(instance.id);
      expect(after.state, InstanceState.running);
      expect(after.pid, server.pid);
      expect(env.process.launches, hasLength(1), reason: 'not started twice');
      expect(second.instances.recoveryNotices, isEmpty);
      // It is supervised: when it exits without a stop request it crashed.
      final crashed = collectNotices(second, 'crashed');
      server.exit(9);
      await eventually(() => crashed.isNotEmpty, reason: 'the crash');
      expect(crashed.single.exitCode, 9);
    });

    test('a_server_that_is_gone_is_reported_lost', () async {
      final env = TestEnv();
      env.installValheim();
      final first = await env.start();
      final instance = await createRunning(first);
      first.instances.updateSettings(
        UpdateSettingsRequest(
          instanceId: instance.id,
          settings: valheimSettings(),
          autostart: false,
        ),
      );
      await env.kill(first);

      final second = await env.start();

      expect(second.instances.get(instance.id).state, InstanceState.stopped);
      expect(
        second.instances.recoveryNotices.map((n) => n.kind),
        contains('lost_while_daemon_down'),
      );
      expect(runState(env, instance.id), 'ended');
    });

    test('a_pending_run_without_a_server_is_lost', () async {
      final env = TestEnv();
      env.installValheim();
      final first = await env.start();
      final instance = await createInstalled(first);
      first.instances.updateSettings(
        UpdateSettingsRequest(
          instanceId: instance.id,
          settings: valheimSettings(),
          autostart: false,
        ),
      );
      await env.kill(first);
      // The daemon died after recording the run and before any relay wrote
      // its identity.
      final runDirectory = RunFiles.directoryFor(instance.directory, 'run-1');
      Directory(runDirectory).createSync(recursive: true);
      editDatabase(
        env,
        'INSERT INTO runs (run_id, instance_id, directory, state, created_at) '
        "VALUES ('run-1', ?, ?, 'pending', 1)",
        [instance.id, runDirectory],
      );
      editDatabase(
        env,
        "UPDATE instances SET state = 'starting' WHERE id = ?",
        [instance.id],
      );

      final second = await env.start(
        pendingRunWait: const Duration(milliseconds: 100),
      );

      expect(second.instances.get(instance.id).state, InstanceState.stopped);
      expect(runState(env, instance.id), 'ended');
    });
  });
}
