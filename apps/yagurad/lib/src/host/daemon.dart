import 'dart:async';
import 'dart:io';

import '../errors.dart';
import '../hooks/hooks.dart';
import '../instances/health_check.dart';
import '../instances/instance_manager.dart';
import '../instances/instance_store.dart';
import '../logs/instance_log_sync.dart';
import '../logs/log_hub.dart';
import '../logs/log_match_watch.dart';
import '../operations/operations.dart';
import '../plugins/plugin_registry.dart';
import '../process/process.dart';
import '../snapshots/snapshots.dart';
import '../steam/steam.dart';
import 'data_dir_lock.dart';
import 'data_directory.dart';
import 'database.dart';

/// A step that failed without stopping the daemon (design D9).
class StartupNotice {
  const StartupNotice(this.step, this.message);
  final String step;
  final String message;

  @override
  String toString() => 'StartupNotice($step: $message)';
}

class DaemonConfig {
  DaemonConfig({
    required this.dataDirectory,
    required this.apiPort,
    required this.steam,
    this.processHost,
    this.helperExecutable,
    this.snapshotter,
    this.removeDirectory,
    this.hookHost,
    this.os,
    this.migrations,
    this.clock,
    this.logOptions = const LogHubOptions(),
    this.maxRetainedOperationEvents = 2000,
    this.restartDelay = const Duration(seconds: 5),
    this.autostartInterval = const Duration(seconds: 10),
    this.healthPollInterval = const Duration(milliseconds: 250),
    this.processHealthSettle = const Duration(seconds: 2),
    this.pendingRunWait = const Duration(seconds: 10),
  });

  final String dataDirectory;
  final int apiPort;
  final SteamService steam;

  /// Defaults to the Windows host on Windows (running [helperExecutable]) and
  /// to a host that cannot launch elsewhere (the Linux path is M5).
  final ProcessHost? processHost;

  /// The `yagurad` executable the process host runs its `launch` and `signal`
  /// modes from; defaults to the running executable. Under `dart test` that
  /// is `dart.exe`, so process tests pass a compiled `yagurad`.
  final String? helperExecutable;

  /// Defaults to a [DirectorySnapshotter] in `<data>/snapshots`.
  final Snapshotter? snapshotter;

  /// Removes an instance directory after a delete with files; a seam for tests.
  final Future<void> Function(String directory)? removeDirectory;
  final HookHost? hookHost;

  /// `windows` or `linux`; defaults to the host OS.
  final String? os;
  final List<Migration>? migrations;
  final DateTime Function()? clock;

  /// Polling and persist intervals of the log hub.
  final LogHubOptions logOptions;

  /// Non-progress events an operation keeps for a resuming `WatchOperation`
  /// (design D3).
  final int maxRetainedOperationEvents;

  /// How long after a crash the instance is started again ("within 10 s").
  final Duration restartDelay;

  /// Gap between autostarted instances (design D14).
  final Duration autostartInterval;

  /// How often the start-time health check tries a port.
  final Duration healthPollInterval;

  /// How long a `process` health check watches the process stay alive.
  final Duration processHealthSettle;

  /// How long startup waits for a live relay to record its server (D2).
  final Duration pendingRunWait;
}

/// The daemon core: startup sequence and the services group 8 serves.
///
/// Startup separates fatal steps (data directory, lock, database), which stop
/// the daemon with a reason naming the step, from degraded steps, which are
/// recorded as [startupNotices] and let it come up (design D9).
class Daemon {
  Daemon._({
    required this.dataDirectory,
    required DataDirLock lock,
    required YaguraDatabase database,
    required this.plugins,
    required this.instances,
    required this.operations,
    required this.logs,
    required this.startupNotices,
    required this.hooks,
    required this.os,
    required this.startedAt,
    required SteamService steam,
    required InstanceLogSync logSync,
  }) : _lock = lock, // ignore: prefer_initializing_formals
       _database = database, // ignore: prefer_initializing_formals
       _steam = steam, // ignore: prefer_initializing_formals
       _logSync = logSync; // ignore: prefer_initializing_formals

  final DataDirLock _lock;
  final YaguraDatabase _database;
  final SteamService _steam;
  final InstanceLogSync _logSync;
  var _closed = false;

  final DataDirectory dataDirectory;
  final PluginRegistry plugins;
  final InstanceManager instances;
  final OperationRunner operations;
  final LogHub logs;
  final List<StartupNotice> startupNotices;

  /// The hook host; `GetHealth` reports its leaked and degraded state.
  final HookHost hooks;

  /// `windows` or `linux`.
  final String os;
  final DateTime startedAt;

  static Future<Daemon> start(DaemonConfig config) async {
    final dataDirectory = _fatal('data_directory', () {
      return DataDirectory.prepare(config.dataDirectory);
    });
    final lock = _fatal(
      'data_directory_lock',
      () => DataDirLock.acquire(dataDirectory.lockPath),
    );
    final YaguraDatabase database;
    try {
      database = _fatal(
        'database',
        () => YaguraDatabase.open(
          dataDirectory.databasePath,
          migrations: config.migrations,
        ),
      );
    } on Object {
      lock.release();
      rethrow;
    }

    final notices = <StartupNotice>[];
    Future<void> degraded(String step, FutureOr<void> Function() body) async {
      try {
        await body();
      } on Object catch (e) {
        notices.add(
          StartupNotice(step, e is YaguraException ? e.message : '$e'),
        );
      }
    }

    final hooks = config.hookHost ?? HookHost();
    final runner = OperationRunner(
      database: database,
      clock: config.clock,
      maxRetainedEvents: config.maxRetainedOperationEvents,
    );
    final registry = PluginRegistry(
      pluginsDirectory: dataDirectory.pluginsPath,
      hooks: hooks,
    );
    final InstanceManager manager;
    try {
      manager = InstanceManager(
        store: InstanceStore(database),
        runner: runner,
        registry: registry,
        dataDirectory: dataDirectory,
        apiPort: config.apiPort,
        os: config.os ?? (Platform.isWindows ? 'windows' : 'linux'),
        processHost:
            config.processHost ??
            defaultProcessHost(helperExecutable: config.helperExecutable),
        steam: config.steam,
        hooks: hooks,
        snapshotter:
            config.snapshotter ??
            DirectorySnapshotter(
              root: dataDirectory.snapshotsPath,
              clock: config.clock,
            ),
        runs: RunStore(database),
        healthEvaluator: HealthEvaluator(
          pollInterval: config.healthPollInterval,
          settle: config.processHealthSettle,
        ),
        restartDelay: config.restartDelay,
        autostartInterval: config.autostartInterval,
        pendingRunWait: config.pendingRunWait,
        removeDirectory: config.removeDirectory,
        clock: config.clock,
      );
    } on Object {
      database.close();
      lock.release();
      rethrow;
    }

    final logs = LogHub(
      database: database,
      clock: config.clock,
      options: config.logOptions,
    );

    await degraded('steam_sweep', config.steam.sweepStrays);
    await degraded('plugins', () async {
      for (final result in await registry.load()) {
        if (!result.isLoaded) {
          notices.add(
            StartupNotice(
              'plugins',
              'plugin ${result.id} was rejected: ${result.reasons.join('; ')}',
            ),
          );
        }
      }
    });
    manager.logMatchWatch = (id, source, pattern) =>
        LogHubMatchWatch.open(logs, id, source, pattern);
    manager.logTail = (id, lines) async {
      await logs.pollNow(id);
      return [for (final e in logs.backlog(id, lines: lines).entries) e.text];
    };
    await degraded('recovery', manager.recover);
    await degraded('reconcile', manager.reconcilePlugins);
    await degraded('marked_directories', manager.sweepMarkedDirectories);
    await degraded('snapshots', manager.purgeExpiredSnapshots);
    await degraded('instance_files', manager.rewriteInstanceFiles);
    await degraded('history', runner.pruneHistory);
    final logSync = InstanceLogSync(
      hub: logs,
      manager: manager,
      registry: registry,
      os: config.os ?? (Platform.isWindows ? 'windows' : 'linux'),
    );
    await degraded('log_tailing', logSync.syncAll);
    logSync.listen();
    manager.autostartInstances();

    return Daemon._(
      dataDirectory: dataDirectory,
      lock: lock,
      database: database,
      plugins: registry,
      instances: manager,
      operations: runner,
      logs: logs,
      startupNotices: List.unmodifiable(notices),
      hooks: hooks,
      os: config.os ?? (Platform.isWindows ? 'windows' : 'linux'),
      startedAt: (config.clock ?? DateTime.now)(),
      steam: config.steam,
      logSync: logSync,
    );
  }

  /// Runs a fatal step; a failure carries the step in `details['step']`.
  static T _fatal<T>(String step, T Function() body) {
    try {
      return body();
    } on YaguraException catch (e) {
      throw YaguraException(
        e.reason,
        e.message,
        details: {...e.details, 'step': step},
      );
    }
  }

  /// Stops serving and releases the database and the data directory lock.
  /// Operations still running are not finished: they stay unfinished in the
  /// database, as after a killed daemon, and are marked `interrupted` by the
  /// next start.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _logSync.close();
    await instances.close();
    await logs.close();
    await operations.close();
    await _steam.close();
    _database.close();
    _lock.release();
  }
}
