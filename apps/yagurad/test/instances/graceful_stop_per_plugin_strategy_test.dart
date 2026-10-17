import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/process/process.dart';

import '../support/daemon_support.dart';
import '../support/process_support.dart';
import '../support/valheim_support.dart';

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

  // The real Valheim dedicated server through a real `yagurad run --dev`
  // process (the M1 "console" mode is `run --dev` in a console window).
  //
  // Install: a full anonymous SteamCMD install of app 896660 is ~2.1 GB. When
  // YAGURA_VALHEIM_SERVER names an existing server install, the test copies
  // it into the instance's `server/` directory and the daemon's Install runs
  // against a pre-seeded fake SteamCMD (the fixture the bundle smoke uses)
  // that only "validates": Install, Start and Stop are the real daemon code,
  // just without the network. Without the variable the daemon downloads the
  // server with the real SteamCMD.
  //
  // Run: `dart test --run-skipped -t valheim <this file>` (the `valheim` tag
  // is skipped by default, see dart_test.yaml).
  test(
    'valheim_saves_on_a_signal_stop',
    () async {
      requireBreakaway();
      final tools = await processTools();
      final work = Directory.systemTemp.createTempSync('yagura_valheim_');
      addTearDown(() => deleteDirectory(work));
      final data = p.join(work.path, 'data');
      final existing = Platform.environment[valheimServerEnvironment];
      if (existing != null) {
        expect(
          File(p.join(existing, 'valheim_server.exe')).existsSync(),
          isTrue,
          reason: '$valheimServerEnvironment has no valheim_server.exe',
        );
      }

      // The shipped plugin, not the test fixture.
      final plugin = Directory(p.join(data, 'plugins', 'valheim'))
        ..createSync(recursive: true);
      File(p.absolute('..', '..', 'plugins', 'valheim', 'plugin.yaml'))
          .copySync(p.join(plugin.path, 'plugin.yaml'));
      if (existing != null) {
        final steam = p.join(data, 'steamcmd', 'anonymous');
        Directory(steam).createSync(recursive: true);
        final compiled = await Process.run(Platform.resolvedExecutable, [
          'compile',
          'exe',
          p.absolute('test', 'fixtures', 'fake_steamcmd', 'fake_steamcmd.dart'),
          '-o',
          p.join(steam, 'steamcmd.exe'),
        ]);
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
        copyDirectory(
          p.absolute('test', 'fixtures', 'fake_steamcmd', 'output'),
          p.join(steam, 'output'),
        );
        File(p.join(steam, '.yagura-ready')).writeAsStringSync('');
      }

      final daemon = await DaemonProcess.start(tools.yagurad, data);
      addTearDown(daemon.close);

      var instance = await daemon.instances.createInstance(
        pb.CreateInstanceRequest(
          pluginId: 'valheim',
          name: 'Signal stop',
          settings: pb.JsonDocument(json: '{"serverName":"Signal stop"}'),
        ),
      );
      final id = instance.id;
      final serverDirectory = p.join(instance.directory, 'server');
      if (existing != null) copyDirectory(existing, serverDirectory);
      await daemon.succeeded(
        await daemon.instances.install(pb.LifecycleRequest(instanceId: id)),
      );
      expect(
        File(p.join(serverDirectory, 'valheim_server.exe')).existsSync(),
        isTrue,
      );

      // Start reaches `running` through the manifest's `log_match` health.
      final started = await daemon.succeeded(
        await daemon.instances.start(pb.LifecycleRequest(instanceId: id)),
        timeout: const Duration(minutes: 6),
      );
      expect(started.resultReason, isEmpty);
      instance = await daemon.instances.getInstance(
        pb.GetInstanceRequest(instanceId: id),
      );
      expect(instance.state, pb.InstanceState.INSTANCE_STATE_RUNNING);
      final serverPid = instance.pid;
      expect(processAlive(serverPid), isTrue);

      final log = File(p.join(instance.directory, 'logs', 'server.log'));
      expect(log.readAsStringSync(), contains('Game server connected'));
      final saveLine = RegExp(r'World save \(5/5\) done');
      final savesBefore = saveLine.allMatches(log.readAsStringSync()).length;
      final world = Directory(
        p.join(instance.directory, 'save', 'worlds_local', 'Dedicated'),
      );
      final generationBefore = _newestDb(world)?.path;

      // Stop through the API. `requestedAt` is taken before the request, so
      // it is no later than the daemon's own stop_requested_at.
      final requestedAt = DateTime.now();
      final stopped = await daemon.succeeded(
        await daemon.instances.stop(pb.LifecycleRequest(instanceId: id)),
        timeout: const Duration(minutes: 2),
      );
      expect(stopped.resultReason, 'stopped_by:graceful');
      await eventually(
        () => !processAlive(serverPid),
        reason: 'the server to exit',
        timeout: const Duration(seconds: 30),
      );
      instance = await daemon.instances.getInstance(
        pb.GetInstanceRequest(instanceId: id),
      );
      expect(instance.state, pb.InstanceState.INSTANCE_STATE_STOPPED);

      // The relay wrote the observed exit time to the run's exit.json (UTC).
      final exitFiles = Directory(p.join(instance.directory, '.yagura', 'run'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.basename(f.path) == 'exit.json')
          .toList();
      expect(exitFiles, hasLength(1));
      final exit = jsonDecode(exitFiles.single.readAsStringSync()) as Map;
      final exitedAt = DateTime.parse(exit['exited_at'] as String);
      expect(exit['exit_code'], 0);

      // The world save was written after the stop was requested and no later
      // than the process exit: compares the modification time of the newest
      // `_main.<N>.db2` with `requestedAt` and the exit time in `exit.json`.
      final db = _newestDb(world);
      expect(db, isNotNull, reason: 'no world save in ${world.path}');
      final savedAt = db!.statSync().modified;
      expect(
        savedAt.isAfter(requestedAt),
        isTrue,
        reason: 'save $savedAt is not after the stop request $requestedAt',
      );
      expect(
        savedAt.isAfter(exitedAt),
        isFalse,
        reason: 'save $savedAt is after the exit $exitedAt',
      );
      if (generationBefore != null) {
        expect(db.path, isNot(generationBefore), reason: 'a new generation');
      }

      // The server log shows the shutdown save that Ctrl+C triggered.
      final text = log.readAsStringSync();
      expect(saveLine.allMatches(text).length, greaterThan(savesBefore));
    },
    tags: ['windows', 'valheim'],
    skip: windowsOnly,
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

/// The newest `_main.<N>.db2` in [world], or null when there is none.
File? _newestDb(Directory world) {
  if (!world.existsSync()) return null;
  final files = world
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'_main\.\d+\.db2$').hasMatch(f.path))
      .toList();
  if (files.isEmpty) return null;
  files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
  return files.last;
}
