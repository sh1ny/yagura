import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../errors.dart';
import '../admin/admin_server.dart';
import '../admin/admin_service.dart';
import '../admin/admin_transport.dart';
import '../hooks/hooks.dart';
import '../instances/health_check.dart';
import '../instances/instance_manager.dart';
import '../instances/instance_roots.dart';
import '../instances/instance_store.dart';
import '../logs/instance_log_sync.dart';
import '../logs/log_hub.dart';
import '../logs/log_match_watch.dart';
import '../operations/operations.dart';
import '../platform/acl_writer.dart';
import '../plugins/plugin_registry.dart';
import '../process/process.dart';
import '../service/version_sweeper.dart';
import '../snapshots/snapshots.dart';
import '../steam/steam.dart';
import '../version.dart';
import 'data_dir_lock.dart';
import 'data_directory.dart';
import 'database.dart';
import '../security/security.dart';
import 'secret_store.dart';

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
    this.serviceMode = false,
    this.secretProtector,
    this.adminListener,
    this.aclWriter,
    this.accountSids,
    this.hostAddresses,
    this.versionSweeper,
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

  /// Runs as the Windows service (LocalSystem): foreign-scope secrets are
  /// deleted at start instead of refusing it (design D3).
  final bool serviceMode;

  /// Defaults to DPAPI on Windows; a seam for tests.
  final SecretProtector? secretProtector;

  /// Opens the endpoint of the admin channel (design D5); null serves none.
  /// The channel is served in service mode only.
  final AdminListener Function()? adminListener;

  /// Writes the protected DACLs of instance roots; null cannot protect a
  /// root, so `roots add` fails `root_not_protected`.
  final AclWriter? aclWriter;

  /// Resolves `yagura-srv` and `yagura-steam` for the root DACL.
  final AccountSids? accountSids;

  /// The addresses `yagurad pair` picks from; defaults to the host's.
  final Future<List<InternetAddress>> Function()? hostAddresses;

  /// Deletes the install's version directories no run needs (design D6);
  /// null when the daemon does not run from an installed version.
  final VersionSweeper? versionSweeper;

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
    required this.secrets,
    required this.roots,
    required AdminServer? admin,
    required this.security,
    required this.startedAt,
    required SteamService steam,
    required InstanceLogSync logSync,
  }) : _lock = lock, // ignore: prefer_initializing_formals
       _database = database, // ignore: prefer_initializing_formals
       _admin = admin, // ignore: prefer_initializing_formals
       _steam = steam, // ignore: prefer_initializing_formals
       _logSync = logSync; // ignore: prefer_initializing_formals

  final DataDirLock _lock;
  final YaguraDatabase _database;
  final SteamService _steam;
  final AdminServer? _admin;
  final InstanceLogSync _logSync;
  var _closed = false;

  final DataDirectory dataDirectory;
  final PluginRegistry plugins;
  final InstanceManager instances;
  final OperationRunner operations;
  final LogHub logs;
  final List<StartupNotice> startupNotices;

  /// Where instance directories may live (design D5).
  final HostRoots roots;

  /// Whether the admin channel is served (`GetHealth.admin_channel_ok`).
  bool get adminChannelOk => _admin?.serving ?? false;

  /// Identity, devices, pairing and audit; null unless service mode.
  final DaemonSecurity? security;

  /// Notices raised after startup, such as a failed certificate rotation.
  final List<StartupNotice> runtimeNotices = [];

  /// The secret store (design D3).
  final SecretStore secrets;

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
    final DatabaseSecretStore secrets;
    try {
      secrets = _fatal(
        'secret_store',
        () => DatabaseSecretStore.open(
          database,
          config.secretProtector ?? defaultSecretProtector(),
          serviceMode: config.serviceMode,
        ),
      );
    } on Object {
      database.close();
      lock.release();
      rethrow;
    }

    // The identity exists only in service mode (design D5): a dev daemon
    // serves plaintext and has no CA.
    DaemonSecurity? security;
    if (config.serviceMode) {
      try {
        security = _fatal(
          'identity',
          () => DaemonSecurity.open(
            database,
            secrets,
            clock: () => (config.clock ?? DateTime.now)().toUtc(),
          ),
        );
      } on Object {
        database.close();
        lock.release();
        rethrow;
      }
    }

    final notices = <StartupNotice>[];
    if (!secrets.recovery.isEmpty) {
      notices.add(StartupNotice('secrets_reset', secrets.recovery.describe()));
    }
    Future<void> degraded(String step, FutureOr<void> Function() body) async {
      try {
        await body();
      } on Object catch (e) {
        notices.add(
          StartupNotice(step, e is YaguraException ? e.message : '$e'),
        );
      }
    }

    // The Steam service keeps its ready marker and app sizes in the database
    // (design D8), out of reach of the game servers.
    if (config.steam case final SteamCmdService steam) {
      steam.useDatabase(database, config.clock);
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
    final roots = HostRoots(
      database,
      defaultRoot: dataDirectory.instancesPath,
      dataDirectory: dataDirectory.path,
      writer: config.aclWriter,
      accounts: config.accountSids,
      clock: config.clock,
    );
    final runStore = RunStore(database);
    final InstanceManager manager;
    try {
      manager = InstanceManager(
        store: InstanceStore(database),
        roots: roots,
        secrets: secrets,
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
        runs: runStore,
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
    // After the recovery has ended the runs whose relay is gone: what is
    // left names the versions still in use.
    if (config.versionSweeper case final sweeper?) {
      await degraded(
        'version_directories',
        () => sweeper.sweep(runStore.unresolved()),
      );
    }
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

    // The admin channel is served in service mode only, and a name another
    // process holds is a notice, not a reason to stop (design D5).
    AdminServer? admin;
    final listener = config.adminListener;
    if (security != null && listener != null) {
      final service = AdminService(
        security: security,
        roots: roots,
        instances: manager,
        apiPort: () => config.apiPort,
        status: () => {
          'admin_channel': 'ok',
          'mode': 'service',
          'data_dir': dataDirectory.path,
          'version': daemonVersion,
          'executable': Platform.resolvedExecutable,
        },
        hostAddresses: config.hostAddresses,
      );
      final server = AdminServer(listener(), service.handle);
      try {
        await server.start();
        admin = server;
      } on YaguraException catch (e) {
        notices.add(StartupNotice(e.reason, e.message));
      }
    }

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
      secrets: secrets,
      roots: roots,
      admin: admin,
      security: security,
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
    } on SqliteException catch (e) {
      throw YaguraException(
        'internal_error',
        'startup step $step failed: ${e.message}',
        details: {'step': step},
      );
    } on FileSystemException catch (e) {
      throw YaguraException(
        'internal_error',
        'startup step $step failed: ${e.message} ${e.path ?? ''}'.trimRight(),
        details: {'step': step},
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
    await _admin?.close();
    await _logSync.close();
    await instances.close();
    await logs.close();
    await operations.close();
    await _steam.close();
    security?.close();
    _database.close();
    _lock.release();
  }
}
