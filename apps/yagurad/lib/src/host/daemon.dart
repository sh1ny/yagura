import 'dart:async';
import 'dart:io';

import '../errors.dart';
import '../hooks/hooks.dart';
import '../instances/instance_manager.dart';
import '../instances/instance_store.dart';
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
    required this.processHost,
    required this.steam,
    this.snapshotter,
    this.removeDirectory,
    this.hookHost,
    this.os,
    this.migrations,
    this.clock,
  });

  final String dataDirectory;
  final int apiPort;
  final ProcessHost processHost;
  final SteamService steam;

  /// Defaults to a [DirectorySnapshotter] in `<data>/snapshots`.
  final Snapshotter? snapshotter;

  /// Removes an instance directory after a delete with files; a seam for tests.
  final Future<void> Function(String directory)? removeDirectory;
  final HookHost? hookHost;

  /// `windows` or `linux`; defaults to the host OS.
  final String? os;
  final List<Migration>? migrations;
  final DateTime Function()? clock;
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
    required this.startupNotices,
    required SteamService steam,
  }) : _lock = lock, // ignore: prefer_initializing_formals
       _database = database, // ignore: prefer_initializing_formals
       _steam = steam; // ignore: prefer_initializing_formals

  final DataDirLock _lock;
  final YaguraDatabase _database;
  final SteamService _steam;
  var _closed = false;

  final DataDirectory dataDirectory;
  final PluginRegistry plugins;
  final InstanceManager instances;
  final OperationRunner operations;
  final List<StartupNotice> startupNotices;

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
    final runner = OperationRunner(database: database, clock: config.clock);
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
        processHost: config.processHost,
        steam: config.steam,
        hooks: hooks,
        snapshotter:
            config.snapshotter ??
            DirectorySnapshotter(
              root: dataDirectory.snapshotsPath,
              clock: config.clock,
            ),
        removeDirectory: config.removeDirectory,
        clock: config.clock,
      );
    } on Object {
      database.close();
      lock.release();
      rethrow;
    }

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
    await degraded('recovery', manager.recover);
    await degraded('reconcile', manager.reconcilePlugins);
    await degraded('marked_directories', manager.sweepMarkedDirectories);
    await degraded('snapshots', manager.purgeExpiredSnapshots);
    await degraded('instance_files', manager.rewriteInstanceFiles);
    await degraded('history', runner.pruneHistory);

    return Daemon._(
      dataDirectory: dataDirectory,
      lock: lock,
      database: database,
      plugins: registry,
      instances: manager,
      operations: runner,
      startupNotices: List.unmodifiable(notices),
      steam: config.steam,
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
    await instances.close();
    await operations.close();
    await _steam.close();
    _database.close();
    _lock.release();
  }
}
