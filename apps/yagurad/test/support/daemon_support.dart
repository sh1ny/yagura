import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/admin/admin_transport.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/firewall/firewall_backend.dart';
import 'package:yagurad/src/platform/acl_writer.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/data_dir_protector.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/instances/instance_acls.dart';
import 'package:yagurad/src/logs/log_hub.dart';
import 'package:yagurad/src/logs/log_models.dart';
import 'package:yagurad/src/mods/mod_check_schedule.dart';
import 'package:yagurad/src/mods/stage_link.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/host/secret_store.dart';
import 'package:yagurad/src/process/process.dart';
import 'package:yagurad/src/service/service_accounts.dart';
import 'package:yagurad/src/service/version_sweeper.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';
import 'package:yagurad/src/steam/steam.dart';

import 'temp_support.dart';

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

  @override
  ProcessIdentity get identity => ProcessIdentity(
    pid: pid,
    executable: executable,
    created: startedAt.microsecondsSinceEpoch,
  );

  @override
  ProcessIdentity? get relay => null;

  @override
  bool recordRejected = false;

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

  /// Called with each server right after it was launched.
  void Function(FakeServer server)? onLaunch;

  /// Called at the start of every stop, before the server is told to end.
  void Function(FakeServer server, StopPlan plan)? onStop;

  /// Servers a daemon started after a restart finds alive by their identity.
  final survivors = <FakeServer>[];

  /// When set, a stop waits for this before the server exits.
  Future<void>? stopGate;

  /// How a stop ends: by default the server exits and the stop is `graceful`
  /// unless forced.
  bool stopFailsGracefully = false;

  /// Appended to `<instance>/logs/server.log` on launch, like the Valheim
  /// server's ready line, so the fixture's `log_match` health check passes.
  /// Null writes nothing (the `log_match` tests write the line themselves).
  String? readyLine = 'Game server connected';

  @override
  Future<RunningServer> launch(LaunchRequest request) async {
    launches.add(request);
    if (launchGate case final gate?) await gate;
    if (launchError case final error?) throw error;
    final server = FakeServer(_nextPid++, request.executable);
    servers.add(server);
    if (readyLine case final line?) {
      File(p.join(request.instanceDirectory, 'logs', 'server.log'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$line\n', mode: FileMode.append);
    }
    onLaunch?.call(server);
    return server;
  }

  @override
  Future<StoppedBy> stop(RunningServer server, StopPlan plan) async {
    stops.add(plan);
    final fake = server as FakeServer;
    onStop?.call(fake, plan);
    if (stopGate case final gate?) await gate;
    fake.exit(0);
    return plan.force || stopFailsGracefully
        ? StoppedBy.kill
        : StoppedBy.graceful;
  }

  /// The server of each relay (by relay PID) that a re-attach without a
  /// recorded server finds as the verified relay's child (design D9).
  final relayChildren = <int, FakeServer>{};

  /// When set, a re-attach fails `run_record_rejected` naming this relay
  /// PID: the run record does not match a verified process (design D9).
  int? rejectedRelayPid;

  @override
  Future<RunningServer?> reattach(
    ProcessIdentity? identity, {
    ProcessIdentity? relay,
    String runDirectory = '',
  }) async {
    if (identity == null) {
      final child = relay == null ? null : relayChildren[relay.pid];
      return child?..recordRejected = true;
    }
    if (rejectedRelayPid case final pid?) {
      throw YaguraException(
        'run_record_rejected',
        'the run record names no verified server (relay $pid)',
        details: {'relayPid': pid},
      );
    }
    for (final server in survivors) {
      if (server.identity == identity) return server;
    }
    return null;
  }

  @override
  Future<bool> isAlive(ProcessIdentity identity) async =>
      survivors.any((s) => s.identity == identity);

  @override
  Future<void> terminate(ProcessIdentity identity) async {}

  @override
  void release(RunningServer server) {}
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

  /// The logins run, by account id.
  final logins = <SteamLoginRequest>[];

  /// When set, a login fails with this.
  YaguraException? loginFailure;

  /// The installations removed.
  final removed = <String>[];

  @override
  Future<void> login(
    SteamLoginRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    logins.add(request);
    reporter.step('steam_login');
    if (loginFailure case final error?) throw error;
  }

  /// The workshop runs requested.
  final workshopRuns = <SteamWorkshopRequest>[];

  @override
  Future<List<SteamWorkshopItemResult>> downloadWorkshopItems(
    SteamWorkshopRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    workshopRuns.add(request);
    return [for (final item in request.items) SteamWorkshopItemResult(item)];
  }

  @override
  Future<void> removeInstallation(String account) async => removed.add(account);

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
  /// A fresh directory under [parent] (the temp folder by default). The
  /// service rows pass a folder under `%ProgramData%`, as a real install has
  /// its data, so the service accounts reach it the way they would there.
  TestEnv({Directory? parent})
    : root = (parent ?? canonicalSystemTemp()).createTempSync('yagurad_test_') {
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

  /// Installs Valheim with its `health:` block replaced by [body] (indented
  /// two spaces under `health:`), e.g. `type: port\n  port: game`.
  String installValheimHealth(String body, {String? hooks}) => installValheim(
    from:
        'type: log_match\n  log_match: "Game server connected"\n'
        '  source: server\n  start_timeout_seconds: 180',
    to: body,
    hooks: hooks,
  );

  /// Replaces [from] with [to] in the installed Valheim manifest.
  void editValheim(String from, String to) {
    final file = File(p.join(pluginsDir, 'valheim', 'plugin.yaml'));
    final text = file.readAsStringSync();
    expect(text, contains(from), reason: 'fixture edit target');
    file.writeAsStringSync(text.replaceFirst(from, to));
  }

  /// Starts a daemon on [data] and closes it at tear-down.
  Future<Daemon> start({
    String os = 'windows',
    ProcessHost? processHost,
    String? helperExecutable,
    Duration restartDelay = Duration.zero,
    Duration autostartInterval = const Duration(milliseconds: 20),
    Duration processHealthSettle = Duration.zero,
    Duration pendingRunWait = const Duration(seconds: 1),
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
    bool serviceMode = false,
    SecretProtector? secretProtector,
    AdminListener Function()? adminListener,
    AdminConnector Function()? adminProbe,
    Duration? adminStartupWait,
    AclWriter? aclWriter,
    AccountSids? accountSids,
    DataDirProtector? dataDirProtector,
    ServiceAccounts? serviceAccounts,
    InstanceAcls? instanceAcls,
    Future<List<InternetAddress>> Function()? hostAddresses,
    VersionSweeper? versionSweeper,
    FirewallBackend? firewall,
    Duration firewallTimeout = const Duration(seconds: 30),
    int maxRetainedOperationEvents = 2000,
    Uri? workshopEndpoint,
    Duration workshopMinInterval = const Duration(milliseconds: 5),
    // The update check runs only when a test asks for it.
    ModCheckSchedule modCheckSchedule = const ModCheckSchedule.off(),
    StageLinkCreator stageLink = defaultStageLink,
    // Nothing polls by itself unless a test says so: tests call `pollNow`.
    LogHubOptions logOptions = const LogHubOptions.manual(),
  }) async {
    final daemon = await Daemon.start(
      DaemonConfig(
        dataDirectory: dataPath ?? data,
        apiPort: port,
        processHost: processHost ?? process,
        helperExecutable: helperExecutable,
        restartDelay: restartDelay,
        autostartInterval: autostartInterval,
        healthPollInterval: const Duration(milliseconds: 20),
        processHealthSettle: processHealthSettle,
        pendingRunWait: pendingRunWait,
        steam: steamService ?? steam,
        snapshotter: realSnapshots ? null : snapshots ?? snapshotter,
        removeDirectory: removeDirectory,
        clock: clock,
        serviceMode: serviceMode,
        secretProtector: secretProtector,
        adminListener: adminListener,
        adminProbe: adminProbe,
        adminStartupWait: adminStartupWait ?? const Duration(seconds: 3),
        aclWriter: aclWriter,
        accountSids: accountSids,
        dataDirProtector: dataDirProtector,
        serviceAccounts: serviceAccounts == null
            ? null
            : (_) => serviceAccounts,
        instanceAcls: instanceAcls,
        hostAddresses: hostAddresses,
        versionSweeper: versionSweeper,
        firewall: firewall,
        firewallTimeout: firewallTimeout,
        maxRetainedOperationEvents: maxRetainedOperationEvents,
        logOptions: logOptions,
        workshopEndpoint: workshopEndpoint,
        workshopMinInterval: workshopMinInterval,
        modCheckSchedule: modCheckSchedule,
        stageLink: stageLink,
        hookHost: hookHost,
        os: os,
        migrations: migrations,
      ),
    );
    _daemons.add(daemon);
    return daemon;
  }

  /// Closes every daemon this env started (idempotent).
  Future<void> closeDaemons() async {
    for (final daemon in List.of(_daemons)) {
      _daemons.remove(daemon);
      await daemon.close();
    }
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
Future<void> eventually(
  bool Function() test, {
  String? reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for: ${reason ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// The log sources of [instanceId]; empty until the daemon has attached them.
List<LogSourceStatus> logSourcesOf(Daemon daemon, String instanceId) {
  try {
    return daemon.logs.sources(instanceId);
  } on YaguraException {
    return const [];
  }
}

/// Starts the instance and returns the finished operation.
Future<Operation> runStart(Daemon daemon, String id) async {
  final op = daemon.instances.start(id);
  return daemon.operations.whenDone(op.id);
}

/// Stops the instance and returns the finished operation.
Future<Operation> runStop(
  Daemon daemon,
  String id, {
  bool force = false,
}) async {
  final op = daemon.instances.stop(id, force: force);
  return daemon.operations.whenDone(op.id);
}

/// The notices of [kind] the manager raises from now on.
List<InstanceNotice> collectNotices(Daemon daemon, String kind) {
  final notices = <InstanceNotice>[];
  daemon.instances.events.listen((event) {
    if (event is InstanceNotice && event.kind == kind) notices.add(event);
  });
  return notices;
}

final _ports = Random();

/// A port nothing holds right now over TCP or UDP, with the next one (a
/// derived query port) free too.
///
/// Picked at random below the ephemeral ranges (Windows 49152+, Linux
/// 32768+), so the OS never hands it to a concurrent test: the UDP health
/// probe binds the port it checks, and two tests probing the same port would
/// each see it held by the other.
Future<int> freePort() async {
  while (true) {
    final port = 20000 + _ports.nextInt(12000);
    if (await _free(port) && await _free(port + 1)) return port;
  }
}

Future<bool> _free(int port) async {
  try {
    final tcp = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await tcp.close();
    final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    udp.close();
    return true;
  } on SocketException {
    return false;
  }
}
