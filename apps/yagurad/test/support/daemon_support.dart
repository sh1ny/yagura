import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/logs/log_hub.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/process/process.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';
import 'package:yagurad/src/steam/steam.dart';

/// The Valheim reference manifest of `packages/yagura_plugin`.
const valheimFixture = '../../packages/yagura_plugin/test/fixtures/valheim';

/// The daemon API port the tests configure.
const apiPort = 50051;

/// A server process under the test's control.
class FakeServer implements RunningServer {
  FakeServer(this.pid, this.executable) : startedAt = DateTime.now();

  @override
  final int pid;
  @override
  final String executable;
  @override
  final DateTime startedAt;

  final _exit = Completer<int>();

  @override
  Future<int> get exitCode => _exit.future;

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

/// A process host that records launches and stops. [launchGate], when set,
/// holds every launch until it completes.
class FakeProcessHost implements ProcessHost {
  final launches = <LaunchRequest>[];
  final stops = <StopPlan>[];
  final servers = <FakeServer>[];
  Future<void>? launchGate;
  YaguraException? launchError;
  var _nextPid = 4000;

  @override
  Future<RunningServer> launch(LaunchRequest request) async {
    launches.add(request);
    if (launchGate case final gate?) await gate;
    if (launchError case final error?) throw error;
    final server = FakeServer(_nextPid++, request.executable);
    servers.add(server);
    return server;
  }

  @override
  Future<StoppedBy> stop(RunningServer server, StopPlan plan) async {
    stops.add(plan);
    (server as FakeServer).exit(0);
    return plan.force ? StoppedBy.kill : StoppedBy.graceful;
  }
}

/// A Steam service that plays a script. By default a run reports
/// `steam_login`, then `download` with three progress steps, and succeeds.
class FakeSteamService implements SteamService {
  final runs = <SteamAppRequest>[];
  var sweeps = 0;
  Object? sweepError;

  /// When set, a run reports its first progress and then waits for this to
  /// complete (or for cancellation) before going on.
  Completer<void>? hold;

  /// When set, a run fails with this after its first progress.
  YaguraException? failure;

  /// Completes when a run has reported its first progress.
  final reachedDownload = Completer<void>();

  @override
  Future<void> installApp(
    SteamAppRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    runs.add(request);
    reporter.step('steam_login');
    reporter.step('download');
    reporter.progress(percent: 10, bytesDone: 500, bytesTotal: 5000);
    if (!reachedDownload.isCompleted) reachedDownload.complete();
    if (hold case final gate?) {
      await Future.any([gate.future, cancel.whenCancelled]);
      if (cancel.isCancelled) throw const OperationCancelled();
    }
    if (failure case final error?) throw error;
    reporter.progress(percent: 60, bytesDone: 3000, bytesTotal: 5000);
    reporter.progress(percent: 100, bytesDone: 5000, bytesTotal: 5000);
  }

  @override
  Future<void> sweepStrays() async {
    sweeps++;
    if (sweepError case final error?) throw error;
  }

  @override
  Future<void> close() async {}
}

/// Records the snapshots it was asked for.
class FakeSnapshotter implements Snapshotter {
  final taken = <SnapshotRequest>[];
  final restored = <RestoreRequest>[];

  /// Throws from `ensureSpace` when set.
  YaguraException? spaceError;

  @override
  Future<void> ensureSpace(SnapshotRequest request) async {
    if (spaceError case final error?) throw error;
  }

  @override
  Future<String> take(SnapshotRequest request) async {
    taken.add(request);
    return 'snap-${taken.length}';
  }

  @override
  List<SnapshotInfo> list(String instanceId) => const [];

  @override
  List<SnapshotInfo> listOrphans(Set<String> knownInstanceIds) => const [];

  @override
  Future<void> restore(
    RestoreRequest request, {
    required void Function(String step) onStep,
    required void Function() checkCancelled,
  }) async {
    restored.add(request);
  }

  @override
  List<String> interruptedRestores() => const [];

  @override
  void clearInterruptedRestore(String instanceId) {}

  @override
  Future<void> purgeExpired(Set<String> knownInstanceIds) async {}
}

/// A fresh data directory for one test, with helpers to prepare plugins and
/// start daemons on it.
class TestEnv {
  TestEnv() : root = Directory.systemTemp.createTempSync('yagurad_test_') {
    addTearDown(() async {
      for (final daemon in List.of(_daemons)) {
        await daemon.close();
      }
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  }

  final Directory root;
  final _daemons = <Daemon>[];
  final process = FakeProcessHost();
  final steam = FakeSteamService();
  final snapshotter = FakeSnapshotter();

  String get data => p.join(root.path, 'data');
  String get pluginsDir => p.join(data, 'plugins');

  /// Copies the Valheim fixture into `<data>/plugins/valheim`, replacing
  /// [from] with [to] in its manifest when given, and optionally adding a
  /// `hooks.js`.
  String installValheim({String? from, String? to, String? hooks}) {
    final dir = Directory(p.join(pluginsDir, 'valheim'))
      ..createSync(recursive: true);
    var manifest = File(p.join(valheimFixture, 'plugin.yaml'))
        .readAsStringSync();
    if (from != null) {
      expect(manifest, contains(from), reason: 'fixture edit target');
      manifest = manifest.replaceFirst(from, to!);
    }
    File(p.join(dir.path, 'plugin.yaml')).writeAsStringSync(manifest);
    if (hooks != null) {
      File(p.join(dir.path, 'hooks.js')).writeAsStringSync(hooks);
    }
    return dir.path;
  }

  /// Starts a daemon on [data] and closes it at tear-down.
  Future<Daemon> start({
    String os = 'windows',
    int port = apiPort,
    // Kept for older tests: the fake snapshotter is always wired in.
    bool withSnapshotter = false,
    // Lets the daemon create its own snapshotter in `<data>/snapshots`.
    bool realSnapshots = false,
    Future<void> Function(String directory)? removeDirectory,
    HookHost? hookHost,
    List<Migration>? migrations,
    String? dataPath,
    SteamService? steamService,
    Snapshotter? snapshots,
    DateTime Function()? clock,
    // Nothing polls by itself unless a test says so: tests call `pollNow`.
    LogHubOptions logOptions = const LogHubOptions.manual(),
  }) async {
    final daemon = await Daemon.start(
      DaemonConfig(
        dataDirectory: dataPath ?? data,
        apiPort: port,
        processHost: process,
        steam: steamService ?? steam,
        snapshotter: realSnapshots ? null : snapshots ?? snapshotter,
        removeDirectory: removeDirectory,
        clock: clock,
        logOptions: logOptions,
        hookHost: hookHost,
        os: os,
        migrations: migrations,
      ),
    );
    _daemons.add(daemon);
    return daemon;
  }

  /// Closes [daemon] the way a killed process ends: nothing is finished or
  /// recorded, the lock and the database are released.
  Future<void> kill(Daemon daemon) async {
    _daemons.remove(daemon);
    await daemon.close();
  }
}

/// Settings of a plain Valheim instance.
Map<String, Object?> valheimSettings({String name = 'Friends'}) => {
  'serverName': name,
};

/// Creates a Valheim instance named [name].
Future<Instance> createValheim(
  Daemon daemon, {
  String name = 'Friends',
  Map<String, int> ports = const {},
  String? directory,
  Map<String, Object?>? settings,
}) => daemon.instances.create(
  CreateInstanceRequest(
    pluginId: 'valheim',
    name: name,
    settings: settings ?? valheimSettings(name: name),
    ports: ports,
    directory: directory,
  ),
);

/// Runs an install to completion and returns the instance as `stopped`.
Future<Instance> createInstalled(
  Daemon daemon, {
  String name = 'Friends',
  Map<String, int> ports = const {},
}) async {
  final instance = await createValheim(daemon, name: name, ports: ports);
  final op = daemon.instances.install(instance.id);
  await daemon.operations.whenDone(op.id);
  return daemon.instances.get(instance.id);
}

/// Creates, installs and starts an instance; returns it `running`.
Future<Instance> createRunning(Daemon daemon, {String name = 'Friends'}) async {
  final instance = await createInstalled(daemon, name: name);
  final op = daemon.instances.start(instance.id);
  await daemon.operations.whenDone(op.id);
  return daemon.instances.get(instance.id);
}

Matcher failsWith(
  String reason, {
  List<String> messageHas = const [],
  Map<String, Object?> details = const {},
}) => throwsA(
  isA<YaguraException>()
      .having((e) => e.reason, 'reason', reason)
      .having(
        (e) => e.message,
        'message',
        allOf([for (final part in messageHas) contains(part)]),
      )
      .having(
        (e) => e.details,
        'details',
        allOf([
          for (final entry in details.entries)
            containsPair(entry.key, entry.value),
        ]),
      ),
);

/// A hook worker that replies when the test says so.
class GatedHookWorker implements HookWorker {
  final _result = Completer<Map<String, Object?>>();
  final _exited = Completer<void>();

  @override
  Future<Map<String, Object?>> get result => _result.future;

  @override
  Future<void> get exited => _exited.future;

  /// Replies that the hook is not exported (nothing to apply).
  void release() {
    if (_result.isCompleted) return;
    _result.complete({'status': 'ok', 'missing': true, 'logs': <Object?>[]});
    _exited.complete();
  }

  @override
  void kill() => release();
}

/// A hook host whose `onPreStart` workers are [GatedHookWorker]s, collected
/// in [workers]; every other call (the load check, `onPostInstall`...) is
/// answered at once as not exported.
class GatedHookHost {
  final workers = <GatedHookWorker>[];

  late final HookHost host = HookHost(
    launcher: (request) async {
      final worker = GatedHookWorker();
      if (request.hookName == 'onPreStart') {
        workers.add(worker);
      } else {
        worker.release();
      }
      return worker;
    },
  );
}

/// Closes [daemon] like a killed process, writes [state] and [reason] on the
/// instance row, and starts a new daemon on the same data directory.
Future<Daemon> reopenWithState(
  TestEnv env,
  Daemon daemon,
  String instanceId,
  InstanceState state,
  String reason,
) async {
  await env.kill(daemon);
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  db.sqlite.execute(
    'UPDATE instances SET state = ?, state_reason = ? WHERE id = ?',
    [state.wireName, reason, instanceId],
  );
  db.close();
  return env.start();
}

/// Waits until [test] holds, polling the event loop.
Future<void> eventually(bool Function() test, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for: ${reason ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
