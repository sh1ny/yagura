import 'dart:async';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../errors.dart';
import '../files/files.dart';
import '../hooks/hooks.dart';
import '../operations/operations.dart';
import '../plugins/plugin_registry.dart';
import '../process/process.dart';
import '../snapshots/snapshots.dart';
import '../steam/steam.dart';
import 'health_check.dart';
import 'instance.dart';
import 'instance_file.dart';
import 'instance_manager.dart';
import 'instance_store.dart';

/// The bodies of the lifecycle operations (design D3, D17, D18, D25). Each
/// holds the plugin captured when it starts, so a reload during the operation
/// does not change what it runs.
class Lifecycle {
  Lifecycle(this._manager);

  final InstanceManager _manager;

  static final _random = Random.secure();

  String _serverDirectory(InstanceRecord record) =>
      p.join(record.directory, 'server');

  LaunchContext _launchContext(
    InstanceRecord record,
    PluginManifest manifest,
  ) => LaunchContext(
    settings: record.settings,
    ports: {for (final port in record.ports) port.name: port.number},
    paths: {'instance': record.directory, 'server': _serverDirectory(record)},
    os: _manager.os,
  );

  /// Runs hook [point] of [plugin] when it has a `hooks.js`; returns its
  /// result (empty when the plugin has no script or does not export it).
  Future<HookRunResult> _hook(
    OperationContext ctx,
    InstanceRecord record,
    LoadedPlugin plugin,
    HookPoint point,
  ) async {
    final source = plugin.hooksSource;
    if (source == null) return const HookRunResult.skipped();
    final manifest = plugin.manifest;
    try {
      return await _manager.hooks.run(
        HookInvocation(
          point: point,
          source: source,
          context: HookContext(
            instanceId: record.id,
            pluginId: manifest.id,
            pluginVersion: manifest.version,
            os: _manager.os,
            paths: const {'server': 'server'},
            settings: withSecretPlaceholders(
              manifest.settings,
              record.settings,
              const {'secret': true, 'set': false},
              setSecrets: _manager.setSecretsOf(record),
            ),
            ports: {for (final port in record.ports) port.name: port.number},
          ),
          root: InstanceFs(record.directory),
          deadline: Duration(seconds: manifest.hooksTimeoutSeconds),
        ),
        cancel: ctx.cancel.whenCancelled,
      );
    } on YaguraException catch (e) {
      if (e.reason == 'interrupted' && ctx.cancel.isCancelled) {
        throw const OperationCancelled();
      }
      // The operation keeps only the message, so the script location (the
      // stack names `hooks.js:<line>`) goes into it.
      final stack = e.details['stack'];
      if (stack is String && stack.isNotEmpty && !e.message.contains(stack)) {
        throw YaguraException(
          e.reason,
          '${e.message}\n$stack',
          details: e.details,
        );
      }
      rethrow;
    }
  }

  // ---- install and update --------------------------------------------------

  Future<void> _steamRun(
    OperationContext ctx,
    InstanceRecord record,
    PluginManifest manifest, {
    required bool validate,
  }) async {
    final spec = manifest.steam;
    if (spec == null) {
      throw YaguraException(
        'invalid_state',
        'plugin ${manifest.id} does not install through Steam',
      );
    }
    final account = spec.anonymous || record.steamAccountId.isEmpty
        ? null
        : record.steamAccountId;
    InstanceFs(record.directory).createDirectory('server');
    await ctx.heavy(
      () => _manager.steam.installApp(
        SteamAppRequest(
          appId: spec.appId,
          installDirectory: _serverDirectory(record),
          instanceDirectory: record.directory,
          validate: validate,
          account: account,
          accountRequired: !spec.anonymous,
          sizeHintBytes: spec.sizeHintBytes,
        ),
        _Reporter(ctx),
        ctx.cancel,
      ),
      installation: account == null ? 'anonymous' : 'account:$account',
    );
    ctx.cancel.throwIfCancelled();
  }

  Future<void> install(
    OperationContext ctx,
    String id, {
    required bool validate,
  }) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.install, execution: true);
    final plugin = _manager.requirePlugin(record);
    _manager.setState(record, InstanceState.installing);
    try {
      await _steamRun(ctx, record, plugin.manifest, validate: validate);
      await ctx.step('post_install', () async {
        await _hook(ctx, record, plugin, HookPoint.onPostInstall);
      });
      _manager.setState(record, InstanceState.stopped);
    } on Object {
      _manager.setState(record, InstanceState.notInstalled);
      rethrow;
    }
  }

  Future<void> update(
    OperationContext ctx,
    String id, {
    required OperationKind kind,
    required bool validate,
    required bool skipSnapshot,
  }) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, kind, execution: true);
    final plugin = _manager.requirePlugin(record);
    final manifest = plugin.manifest;
    final wasRunning = record.state == InstanceState.running;
    // A running server is started again at the end: refuse before stopping it.
    if (wasRunning) _manager.requireSecrets(record);
    ctx.cancel.throwIfCancelled();

    // The space check comes before anything is stopped or changed, so a full
    // snapshots volume leaves a running server running (design D12).
    final snapshotRequest = skipSnapshot
        ? null
        : _snapshotRequest(record, plugin, 'pre_update');
    if (snapshotRequest != null) {
      await _manager.snapshotter.ensureSpace(snapshotRequest);
    }

    // Stopping for the update is internal: it keeps the last requested state
    // (design D14) until the operation's outcome is known.
    final stoppedBy = wasRunning
        ? await _stopRunning(
            ctx,
            record,
            plugin,
            force: false,
            clearRequested: false,
          )
        : null;

    var updating = false;
    try {
      if (snapshotRequest == null) {
        ctx.result(
          reason: stoppedBy == null ? '' : 'stopped_by:$stoppedBy',
          message: 'snapshot: skipped',
        );
      } else {
        await ctx.step('snapshot', () async {
          await _manager.snapshotter.take(snapshotRequest);
        });
      }
      ctx.cancel.throwIfCancelled();
      _manager.setState(record, InstanceState.updating);
      updating = true;
      await _steamRun(ctx, record, manifest, validate: validate);
      await ctx.step('apply_config', () async {
        await _hook(ctx, record, plugin, HookPoint.onPostUpdate);
      });
      _manager.setState(record, InstanceState.stopped);
    } on OperationCancelled {
      _endedStopped(record, wasRunning, updating);
      rethrow;
    } on Object catch (e) {
      if (updating) {
        record.lastRequestedRunning = false;
        _manager.setState(
          record,
          InstanceState.error,
          reason: e is YaguraException ? e.reason : 'internal_error',
        );
      } else {
        _endedStopped(record, wasRunning, updating);
      }
      rethrow;
    }
    if (wasRunning) {
      ctx.beginStep('start');
      try {
        await start(ctx, id);
      } on Object {
        // The operation ends with the server stopped.
        record.lastRequestedRunning = false;
        _manager.saveChanges(record);
        rethrow;
      }
    }
  }

  SnapshotRequest _snapshotRequest(
    InstanceRecord record,
    LoadedPlugin plugin,
    String reason,
  ) => SnapshotRequest(
    instanceId: record.id,
    instanceName: record.name,
    instanceDirectory: record.directory,
    dataPaths: resolveDataPaths(
      plugin.manifest,
      _launchContext(record, plugin.manifest),
    ),
    reason: reason,
  );

  /// An update, validate or restart that ends with the server stopped clears
  /// the last requested state (design D14).
  void _endedStopped(InstanceRecord record, bool wasRunning, bool updating) {
    if (wasRunning) record.lastRequestedRunning = false;
    if (record.state == InstanceState.error) {
      _manager.saveChanges(record);
    } else if (wasRunning || updating) {
      _manager.setState(record, InstanceState.stopped);
    }
  }

  // ---- start and stop ------------------------------------------------------

  Future<void> start(OperationContext ctx, String id) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.start, execution: true);
    final plugin = _manager.requirePlugin(record);
    final manifest = plugin.manifest;
    _manager.requireSecrets(record);
    _manager.cancelRestart(record.id);
    // Start leaves a crash loop and resets the restart counter.
    if (record.state == InstanceState.error) {
      _manager.runs.clearCrashes(record.id);
    }
    _manager.setState(record, InstanceState.starting);
    RunningServer? server;
    var runId = '';
    var serverGone = false;
    LogMatchWatch? logWatch;
    try {
      var extraArgs = const <String>[];
      var env = const <String, String>{};
      await ctx.step('hook:onPreStart', () async {
        final hook = await _hook(ctx, record, plugin, HookPoint.onPreStart);
        extraArgs = hook.args ?? const [];
        env = hook.env ?? const {};
      });

      // The log is marked before the launch, so a line left from the
      // previous run cannot pass the check.
      final healthSpec = manifest.health;
      if (healthSpec case HealthSpec(
        type: HealthType.logMatch,
        logMatch: final pattern?,
        source: final source?,
      )) {
        logWatch = await _manager.logMatchWatch?.call(
          record.id,
          source,
          RegExp(pattern),
        );
      }

      final launched = await ctx.step('spawn', () async {
        final executable = manifest.executables[_manager.os]!;
        runId = [
          'run',
          for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
        ].join();
        final runDirectory = RunFiles.directoryFor(record.directory, runId);
        InstanceFs(record.directory)
            .createDirectory(p.relative(runDirectory, from: record.directory));
        // The run is recorded `pending` before anything is spawned, so a
        // daemon killed from here on can find what it started.
        _manager.runs.insertPending(
          runId: runId,
          instanceId: record.id,
          directory: runDirectory,
          at: _manager.clock(),
        );
        // The arguments below are the settings this run uses; an edit made
        // after this point is what a restart is needed for.
        record.restartRequired = false;
        final launched = await _manager.processHost.launch(
          LaunchRequest(
            instanceId: record.id,
            runId: runId,
            executable: p.join(_serverDirectory(record), executable),
            args: [
              ...renderLaunchArgs(manifest, _launchContext(record, manifest)),
              ...extraArgs,
            ],
            env: env,
            workingDirectory: _serverDirectory(record),
            instanceDirectory: record.directory,
            runDirectory: runDirectory,
            stdoutEncoding:
                [
                  for (final source in manifest.logs)
                    if (source.isStdout) source.encoding,
                ].firstOrNull ??
                'utf-8',
            onRelayStarted: (relay) =>
                _manager.withRuns((runs) => runs.recordRelay(runId, relay)),
          ),
        );
        _manager.withRuns(
          (runs) => runs.markRunning(
            runId,
            server: launched.identity,
            relay: launched.relay,
          ),
        );
        return launched;
      });
      server = launched;
      record
        ..server = launched
        ..runId = runId;

      var health = InstanceHealth.ok;
      await ctx.step('health', () async {
        final outcome = await _manager.healthEvaluator.evaluate(
          spec: manifest.health,
          ports: record.ports,
          server: launched,
          cancelled: ctx.cancel.whenCancelled,
          logMatch: logWatch?.check,
        );
        switch (outcome) {
          case HealthPassed():
            break;
          case HealthTimedOut():
            health = InstanceHealth.unknown;
            final waited = manifest.health.startTimeoutSeconds;
            final message =
                'health: the server is running but its health check did not '
                'pass within $waited s';
            ctx.warn(message);
            _manager.notice(record.id, 'health_unknown', message);
          case HealthProcessExited(:final exitCode):
            serverGone = true;
            throw YaguraException(
              'launch_failed',
              '${p.basename(launched.executable)} exited during the health '
                  'window with exit code $exitCode',
              details: {'instanceId': record.id, 'exitCode': exitCode},
            );
          case HealthInterrupted():
            throw const OperationCancelled();
        }
      });
      ctx.cancel.throwIfCancelled();

      record
        ..lastRequestedRunning = true
        ..health = health;
      _manager.setState(record, InstanceState.running);
      _manager.watchExit(record, launched);
    } on Object catch (e) {
      final cancelled = e is OperationCancelled;
      if (server != null && !serverGone) {
        // A Stop that cancelled the start gets the plugin's stop plan; any
        // other failure ends the abandoned server at once.
        try {
          await _stopServer(
            record,
            server,
            manifest.stop,
            force: !cancelled,
            clearsRequested: true,
          );
        } on Object {
          // Best effort: the launch is being abandoned anyway.
        }
      } else if (runId.isNotEmpty) {
        _manager.withRuns(
          (runs) => runs.markEnded(
            runId,
            at: _manager.clock(),
            reason: 'launch_failed',
            exitCode: serverGone ? _exitCodeOf(e) : null,
          ),
        );
      }
      record.server = null;
      if (!cancelled) record.lastRequestedRunning = false;
      _manager.setState(record, InstanceState.stopped);
      rethrow;
    } finally {
      await logWatch?.close();
    }
  }

  int? _exitCodeOf(Object error) =>
      error is YaguraException ? error.details['exitCode'] as int? : null;

  /// Asks [server] to stop following [spec] and returns who ended it. The
  /// stop request is written on the run before the strategy is sent, so a
  /// daemon killed in the middle can resume the stop (design D2).
  Future<StoppedBy> _stopServer(
    InstanceRecord record,
    RunningServer server,
    StopSpec spec, {
    required bool force,
    required bool clearsRequested,
  }) async {
    final plan = StopPlan(
      strategy: spec.strategy,
      grace: Duration(seconds: spec.graceSeconds),
      force: force,
    );
    final runId = record.runId;
    record.stopRequested = true;
    _manager.withRuns(
      (runs) => runs.markStopRequested(
        runId,
        at: _manager.clock(),
        grace: plan.grace,
        clearsRequested: clearsRequested,
      ),
    );
    final by = await _manager.processHost.stop(server, plan);
    final code = await server.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    _manager.withRuns(
      (runs) => runs.markEnded(
        runId,
        at: _manager.clock(),
        reason: 'stopped',
        stoppedBy: by.wireName,
        exitCode: code,
      ),
    );
    return by;
  }

  Future<void> stop(
    OperationContext ctx,
    String id, {
    required bool force,
  }) async {
    final record = _manager.recordForOperation(id);
    final plugin = _manager.requirePlugin(record);
    if (record.state == InstanceState.error &&
        record.stateReason == runRecordRejectedReason) {
      // Stop is the retry: verify the run record again; a verified server is
      // then stopped as usual.
      if (!await _manager.retryRejectedRun(record)) {
        _manager.saveChanges(record);
        return;
      }
    }
    final running =
        record.server != null &&
        (record.state == InstanceState.running ||
            record.state == InstanceState.starting ||
            record.state == InstanceState.stopping);
    if (!running) {
      // Nothing left to stop (a queued stop that outlived its target).
      record.lastRequestedRunning = false;
      _manager.saveChanges(record);
      return;
    }
    await _stopRunning(ctx, record, plugin, force: force, clearRequested: true);
  }

  Future<void> restart(OperationContext ctx, String id) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.restart, execution: true);
    final plugin = _manager.requirePlugin(record);
    // Before the stop, so a refused restart leaves the server running.
    _manager.requireSecrets(record);
    await _stopRunning(
      ctx,
      record,
      plugin,
      force: false,
      clearRequested: false,
    );
    try {
      await start(ctx, id);
    } on Object {
      // The restart ends with the server stopped (design D14).
      record.lastRequestedRunning = false;
      _manager.saveChanges(record);
      rethrow;
    }
  }

  /// Stops the running server and returns who ended it (`graceful`, `kill`...).
  /// [clearRequested] is false for the internal stop of an update or restart,
  /// which keeps the last requested state until the operation ends (D14).
  Future<String?> _stopRunning(
    OperationContext ctx,
    InstanceRecord record,
    LoadedPlugin plugin, {
    required bool force,
    required bool clearRequested,
  }) async {
    final server = record.server;
    if (server == null) {
      _manager.setState(record, InstanceState.stopped);
      return null;
    }
    _manager.cancelRestart(record.id);
    _manager.setState(record, InstanceState.stopping);
    final by = await ctx.step(
      'stop',
      () => _stopServer(
        record,
        server,
        plugin.manifest.stop,
        force: force,
        clearsRequested: clearRequested,
      ),
    );
    ctx.result(reason: 'stopped_by:${by.wireName}');
    try {
      if (plugin.hooksSource != null) {
        // The server is gone: a failing hook is reported, it cannot undo the
        // stop.
        await ctx.step('hook:onPostStop', () async {
          try {
            await _hook(ctx, record, plugin, HookPoint.onPostStop);
          } on YaguraException catch (e) {
            ctx.warn('onPostStop failed: ${e.message}');
          }
        });
      }
    } finally {
      // Also when the operation is cancelled before the hook: the server is
      // gone and nothing else would finish the instance.
      record.server = null;
      if (clearRequested) record.lastRequestedRunning = false;
      _manager.setState(record, InstanceState.stopped);
    }
    return by.wireName;
  }

  // ---- delete --------------------------------------------------------------

  Future<void> delete(
    OperationContext ctx,
    String id, {
    required bool deleteFiles,
  }) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.delete, execution: true);
    final fs = InstanceFs(record.directory);

    if (deleteFiles) {
      final plugin = _manager.requirePlugin(record);
      final snapshotId = await ctx.step(
        'snapshot',
        () => _manager.snapshotter.take(
          _snapshotRequest(record, plugin, 'pre_delete'),
        ),
      );
      ctx.result(
        reason: 'pre_delete_snapshot:$snapshotId',
        message:
            'pre_delete snapshot $snapshotId was written before the files '
            'were removed',
      );
      await ctx.step('mark_deleting', () async {
        fs.createDirectory(InstanceFs.yaguraDirectory);
        fs.writeBytes(InstanceFs.deletingMarker, const []);
      });
    }

    try {
      await ctx.step('remove_rows', () async {
        _manager.removeRows(record);
      });
    } on OperationCancelled {
      if (fs.exists(InstanceFs.deletingMarker)) {
        fs.delete(InstanceFs.deletingMarker);
      }
      rethrow;
    }

    if (deleteFiles) {
      // Past the point of no return: cancellation is no longer honoured.
      ctx.beginStep('remove_files');
      await _manager.removeDirectory(record.directory);
    }
  }

  // ---- restore -------------------------------------------------------------

  Future<void> restoreSnapshot(
    OperationContext ctx,
    String id,
    String snapshotId,
  ) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.restore, execution: true);
    final plugin = _manager.requirePlugin(record);
    final manifest = plugin.manifest;
    final snapshotter = _manager.snapshotter;
    try {
      await snapshotter.restore(
        RestoreRequest(
          instanceId: record.id,
          instanceName: record.name,
          instanceDirectory: record.directory,
          dataPaths: resolveDataPaths(
            manifest,
            _launchContext(record, manifest),
          ),
          snapshotId: snapshotId,
        ),
        onStep: ctx.beginStep,
        checkCancelled: ctx.cancel.throwIfCancelled,
      );
    } on Object {
      // A restore that failed after it began replacing data leaves mixed data
      // paths: the instance must not start until the admin decides.
      if (_manager.snapshotter.interruptedRestores().contains(record.id)) {
        _manager.setState(
          record,
          InstanceState.error,
          reason: restoreInterruptedReason,
        );
      }
      rethrow;
    }
    // A finished restore also clears `error: restore_interrupted`.
    _manager.setState(record, InstanceState.stopped);
    ctx.result(
      reason: 'restored:$snapshotId',
      message: 'data paths were replaced by snapshot $snapshotId',
    );
  }
}

/// Maps a Steam run's reports to step and progress events of the operation.
class _Reporter implements SteamRunReporter {
  _Reporter(this._ctx);

  final OperationContext _ctx;
  var _step = '';

  @override
  void step(String name) {
    _step = name;
    _ctx.beginStep(name);
  }

  @override
  void progress({double percent = -1, int bytesDone = 0, int bytesTotal = 0}) =>
      _ctx.progress(
        _step,
        percent: percent,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      );

  @override
  void log(String text) => _ctx.log(text);

  @override
  void warn(String warning) => _ctx.warn(warning);
}
