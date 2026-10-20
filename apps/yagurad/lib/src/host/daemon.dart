import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../errors.dart';
import '../firewall/firewall_backend.dart';
import '../firewall/firewall_reconciler.dart';
import '../admin/admin_server.dart';
import '../admin/admin_service.dart';
import '../admin/admin_transport.dart';
import '../config/bound_file_store.dart';
import '../hooks/hooks.dart';
import '../instances/health_check.dart';
import '../instances/instance.dart' show aclMigrationFailedReason;
import '../instances/instance_acls.dart';
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
import '../service/service_accounts.dart';
import '../service/version_sweeper.dart';
import '../snapshots/snapshots.dart';
import '../steam/steam.dart';
import '../version.dart';
import 'data_dir_lock.dart';
import 'data_dir_protector.dart';
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
    this.adminProbe,
    this.adminStartupWait = const Duration(seconds: 3),
    this.aclWriter,
    this.accountSids,
    this.dataDirProtector,
    this.serviceAccounts,
    this.instanceAcls,
    this.hostAddresses,
    this.versionSweeper,
    this.firewall,
    this.firewallTimeout = const Duration(seconds: 30),
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

  /// A connector to the admin channel, to tell whether a Yagura daemon
  /// already holds it when this daemon cannot open it; null trusts nobody.
  final AdminConnector Function()? adminProbe;

  /// How long a request on the admin channel waits for startup to finish
  /// before it is refused `daemon_starting`. Below the 5 seconds a client
  /// waits for the reply, so a request the client gave up on never runs.
  final Duration adminStartupWait;

  /// Writes the protected DACLs of instance roots; null cannot protect a
  /// root, so `roots add` fails `root_not_protected`.
  final AclWriter? aclWriter;

  /// Resolves `yagura-srv` and `yagura-steam` for the root DACL.
  final AccountSids? accountSids;

  /// Protects the data directory before the database opens (design D6);
  /// null in development mode and where a test has no administrator rights.
  final DataDirProtector? dataDirProtector;

  /// Makes the object that creates and repairs `yagura-srv` and
  /// `yagura-steam` at every service start (design D7), given the secret store
  /// that keeps their passwords; null manages no accounts.
  final ServiceAccounts Function(SecretStore secrets)? serviceAccounts;

  /// Gives instance directories their DACL at create and for older
  /// instances; null manages no instance ACLs.
  final InstanceAcls? instanceAcls;

  /// The addresses `yagurad pair` picks from; defaults to the host's.
  final Future<List<InternetAddress>> Function()? hostAddresses;

  /// Deletes the install's version directories no run needs (design D6);
  /// null when the daemon does not run from an installed version.
  final VersionSweeper? versionSweeper;

  /// The Windows Firewall the reconciler drives (design D11); null in
  /// development mode and where the host has none, which manage no rules.
  /// Used in service mode only.
  final FirewallBackend? firewall;

  /// How long one reconcile may take before it fails `firewall_unavailable`.
  final Duration firewallTimeout;

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
    required this.firewall,
    required this.security,
    required this.startedAt,
    required this.serviceAccountsManaged,
    required this.serviceAccountsOk,
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

  /// Whether this daemon manages the service accounts (service mode).
  final bool serviceAccountsManaged;

  /// Whether the service accounts were set up at this start
  /// (`GetHealth.service_accounts_ok`).
  final bool serviceAccountsOk;

  /// Whether the admin channel is served (`GetHealth.admin_channel_ok`).
  bool get adminChannelOk => _admin?.serving ?? false;

  /// The firewall reconciler; null unless service mode with a firewall.
  final FirewallReconciler? firewall;

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
    // Design D6: in service mode the data directory is opened first, without
    // following links, and held until it is protected, so nothing is created
    // behind a link and the directory cannot be swapped.
    final protector = config.serviceMode ? config.dataDirProtector : null;
    final held = protector == null
        ? null
        : _fatal(
            'data_directory_protection',
            () => protector.open(config.dataDirectory),
          );
    final DataDirectory dataDirectory;
    try {
      dataDirectory = _fatal('data_directory', () {
        return DataDirectory.prepare(
          config.dataDirectory,
          probe: protector == null,
        );
      });
    } on Object {
      held?.close();
      rethrow;
    }
    final DataDirLock lock;
    try {
      lock = _fatal(
        'data_directory_lock',
        () => DataDirLock.acquire(dataDirectory.lockPath),
      );
    } on Object {
      held?.close();
      rethrow;
    }
    if (held != null && protector != null) {
      try {
        _fatal('data_directory_protection', () {
          try {
            held.protect();
          } finally {
            held.close();
          }
          protector.walk(dataDirectory.path, complete: false);
          dataDirectory.checkWritable();
        });
      } on Object {
        lock.release();
        rethrow;
      }
    }
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
        boundFiles: BoundFileStore(database),
        acls: config.serviceMode ? config.instanceAcls : null,
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
    // Design D7, D6: the accounts, then the rest of the data directory (which
    // needs their SIDs), then the instance directories.
    var accountsOk = false;
    final accounts = config.serviceMode
        ? config.serviceAccounts?.call(secrets)
        : null;
    if (accounts != null) {
      await degraded('service_accounts', () {
        accounts.ensure();
        accountsOk = true;
      });
    }
    if (protector != null) {
      final server = config.accountSids?.sidOf(gameServerAccount);
      final steamSid = config.accountSids?.sidOf(steamAccount);
      await degraded('data_directory_protection', () {
        protector.walk(
          dataDirectory.path,
          serverSid: server,
          steamSid: steamSid,
          complete: accountsOk && server != null && steamSid != null,
        );
      });
    }
    await degraded('instance_acls', () {
      for (final failure in manager.migrateInstanceAcls()) {
        notices.add(StartupNotice(aclMigrationFailedReason, failure));
      }
    });
    // The admin channel is served in service mode only, and a name another
    // process holds is a notice, not a reason to stop (design D5).
    FirewallReconciler? firewall;
    AdminServer? admin;
    final adminListener = config.adminListener;
    final listener = adminListener;
    // Requests wait until startup has finished: the channel answering means
    // the daemon is ready (design D6), though it opens before the firewall
    // step so that step knows who holds the channel.
    final started = Completer<void>();
    var anotherDaemonHoldsChannel = false;
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
          'service_accounts_ok': accountsOk,
          'api_port_rule': firewall?.apiRuleStatus ?? 'not_managed',
        },
        hostAddresses: config.hostAddresses,
      );
      final server = AdminServer(listener(), (request) async {
        // A request that waits longer than the client does would run after
        // the client was told it failed: refuse it instead.
        await started.future.timeout(
          config.adminStartupWait,
          onTimeout: () => throw YaguraException(
            'daemon_starting',
            'the daemon is still starting; nothing was done. Run the '
                'command again in a moment',
          ),
        );
        return service.handle(request);
      });
      try {
        await server.start();
        admin = server;
      } on YaguraException catch (e) {
        notices.add(StartupNotice(e.reason, e.message));
        // A name another process holds is no reason to leave the group
        // unmanaged unless that process is a Yagura daemon.
        anotherDaemonHoldsChannel =
            e.reason == 'admin_channel_squatted' &&
            await _holderIsYaguraDaemon(config.adminProbe);
      }
    }

    // Design D11: in service mode the owned rules follow the instances, from
    // the first start on; an unusable firewall is a notice and a health flag.
    // A host runs one service and it manages the group `Yagura`. The one
    // exception is a daemon that finds a trusted Yagura daemon on the admin
    // channel: that one manages it, and this daemon runs no reconciler.
    if (config.serviceMode &&
        config.firewall != null &&
        anotherDaemonHoldsChannel) {
      await degraded('firewall', () {
        throw YaguraException(
          'firewall_unavailable',
          'this daemon does not manage the firewall rules: another Yagura '
              'daemon holds the admin channel and manages the group Yagura',
        );
      });
    } else if (config.serviceMode && config.firewall != null) {
      firewall = FirewallReconciler(
        backend: config.firewall!,
        desired: manager.desiredFirewallRules,
        timeout: config.firewallTimeout,
        onStatusChanged: manager.firewallStatusChanged,
      );
      manager.firewall = firewall;
      await degraded('firewall', () async {
        final result = await firewall!.request();
        if (!result.ok) {
          throw YaguraException('firewall_unavailable', result.problem);
        }
      });
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
    started.complete();

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
      firewall: firewall,
      security: security,
      startedAt: (config.clock ?? DateTime.now)(),
      serviceAccountsManaged: accounts != null,
      serviceAccountsOk: accountsOk,
      steam: config.steam,
      logSync: logSync,
    );
  }

  /// Whether a trusted Yagura daemon answers on the admin channel [probe]
  /// reaches (the same check `yagurad service` makes): a connection that the
  /// connector accepts is one to a LocalSystem server.
  static Future<bool> _holderIsYaguraDaemon(
    AdminConnector Function()? probe,
  ) async {
    if (probe == null) return false;
    try {
      final connection = await probe().connect();
      await connection.close();
      return true;
    } on YaguraException {
      return false;
    }
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
    firewall?.close();
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
