import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../errors.dart';
import '../files/instance_root.dart';
import '../hooks/hooks.dart';
import '../operations/operations.dart';
import '../plugins/plugin_registry.dart';
import '../process/process.dart';
import '../snapshots/snapshots.dart';
import '../steam/steam.dart';
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
            ),
            ports: {for (final port in record.ports) port.name: port.number},
          ),
          root: InstanceRoot(record.directory),
          deadline: Duration(seconds: manifest.hooksTimeoutSeconds),
        ),
        cancel: ctx.cancel.whenCancelled,
      );
    } on YaguraException catch (e) {
      if (e.reason == 'interrupted' && ctx.cancel.isCancelled) {
        throw const OperationCancelled();
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
    Directory(_serverDirectory(record)).createSync(recursive: true);
    await ctx.heavy(
      () => _manager.steam.installApp(
        SteamAppRequest(
          appId: spec.appId,
          installDirectory: _serverDirectory(record),
          validate: validate,
          account: account,
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
    ctx.cancel.throwIfCancelled();

    if (wasRunning) await _stopRunning(ctx, record, plugin, force: false);

    var updating = false;
    try {
      if (skipSnapshot) {
        ctx.warn('snapshot:skipped');
      } else if (_manager.snapshotter case final snapshotter?) {
        await ctx.step('snapshot', () async {
          await snapshotter.take(
            SnapshotRequest(
              instanceId: record.id,
              instanceName: record.name,
              instanceDirectory: record.directory,
              dataPaths: resolveDataPaths(
                manifest,
                _launchContext(record, manifest),
              ),
              reason: 'pre_update',
            ),
          );
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
      _stoppedAfterStep(record, wasRunning, updating);
      rethrow;
    } on YaguraException catch (e) {
      if (updating) {
        _manager.setState(record, InstanceState.error, reason: e.reason);
      } else {
        _stoppedAfterStep(record, wasRunning, updating);
      }
      rethrow;
    }
    if (wasRunning) {
      await start(ctx, id);
    }
  }

  void _stoppedAfterStep(
    InstanceRecord record,
    bool wasRunning,
    bool updating,
  ) {
    if (record.state == InstanceState.error) return;
    if (wasRunning || updating) {
      record.lastRequestedRunning = false;
      _manager.setState(record, InstanceState.stopped);
    }
  }

  // ---- start and stop ------------------------------------------------------

  Future<void> start(OperationContext ctx, String id) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.start, execution: true);
    final plugin = _manager.requirePlugin(record);
    final manifest = plugin.manifest;
    _manager.setState(record, InstanceState.starting);
    RunningServer? server;
    try {
      var extraArgs = const <String>[];
      var env = const <String, String>{};
      await ctx.step('hook:onPreStart', () async {
        final hook = await _hook(ctx, record, plugin, HookPoint.onPreStart);
        extraArgs = hook.args ?? const [];
        env = hook.env ?? const {};
      });

      final launched = await ctx.step('spawn', () async {
        final executable = manifest.executables[_manager.os]!;
        final launched = await _manager.processHost.launch(
          LaunchRequest(
            instanceId: record.id,
            runId: [
              'run',
              for (var i = 0; i < 12; i++)
                _random.nextInt(16).toRadixString(16),
            ].join(),
            executable: p.join(_serverDirectory(record), executable),
            args: [
              ...renderLaunchArgs(manifest, _launchContext(record, manifest)),
              ...extraArgs,
            ],
            env: env,
            workingDirectory: _serverDirectory(record),
            instanceDirectory: record.directory,
          ),
        );
        return launched;
      });
      server = launched;

      await ctx.step('health', () async {
        var exited = false;
        unawaited(launched.exitCode.then((_) => exited = true));
        await Future<void>.delayed(Duration.zero);
        if (exited) {
          throw YaguraException(
            'launch_failed',
            'the server process ended right after it started',
            details: {'instanceId': record.id},
          );
        }
      });
      ctx.cancel.throwIfCancelled();

      record
        ..server = launched
        ..lastRequestedRunning = true;
      _manager.setState(record, InstanceState.running);
    } on Object {
      if (server != null) {
        try {
          await _manager.processHost.stop(
            server,
            const StopPlan(
              strategy: StopStrategy.kill,
              grace: Duration.zero,
              force: true,
            ),
          );
        } on Object {
          // Best effort: the launch is being abandoned anyway.
        }
      }
      record.server = null;
      _manager.setState(record, InstanceState.stopped);
      rethrow;
    }
  }

  Future<void> stop(
    OperationContext ctx,
    String id, {
    required bool force,
  }) async {
    final record = _manager.recordForOperation(id);
    final plugin = _manager.requirePlugin(record);
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
    await _stopRunning(ctx, record, plugin, force: force);
  }

  Future<void> restart(OperationContext ctx, String id) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.restart, execution: true);
    final plugin = _manager.requirePlugin(record);
    await _stopRunning(ctx, record, plugin, force: false);
    await start(ctx, id);
  }

  Future<void> _stopRunning(
    OperationContext ctx,
    InstanceRecord record,
    LoadedPlugin plugin, {
    required bool force,
  }) async {
    final server = record.server;
    if (server == null) {
      _manager.setState(record, InstanceState.stopped);
      return;
    }
    _manager.setState(record, InstanceState.stopping);
    final spec = plugin.manifest.stop;
    final by = await ctx.step(
      'stop',
      () => _manager.processHost.stop(
        server,
        StopPlan(
          strategy: spec.strategy,
          grace: Duration(seconds: spec.graceSeconds),
          force: force,
        ),
      ),
    );
    ctx.result(reason: 'stopped_by:${by.wireName}');
    record
      ..server = null
      ..lastRequestedRunning = false;
    _manager.setState(record, InstanceState.stopped);
  }

  // ---- delete --------------------------------------------------------------

  Future<void> delete(
    OperationContext ctx,
    String id, {
    required bool deleteFiles,
  }) async {
    final record = _manager.recordForOperation(id);
    _manager.checkAllowed(record, OperationKind.delete, execution: true);
    final marker = File(p.join(record.directory, '.yagura', 'deleting'));

    if (deleteFiles) {
      final plugin = _manager.requirePlugin(record);
      if (_manager.snapshotter case final snapshotter?) {
        await ctx.step('snapshot', () async {
          await snapshotter.take(
            SnapshotRequest(
              instanceId: record.id,
              instanceName: record.name,
              instanceDirectory: record.directory,
              dataPaths: resolveDataPaths(
                plugin.manifest,
                _launchContext(record, plugin.manifest),
              ),
              reason: 'pre_delete',
            ),
          );
        });
      }
      await ctx.step('mark_deleting', () async {
        marker.parent.createSync(recursive: true);
        marker.writeAsStringSync('');
      });
    }

    try {
      await ctx.step('remove_rows', () async {
        _manager.removeRows(record);
      });
    } on OperationCancelled {
      if (marker.existsSync()) marker.deleteSync();
      rethrow;
    }

    if (deleteFiles) {
      // Past the point of no return: cancellation is no longer honoured.
      ctx.beginStep('remove_files');
      final directory = Directory(record.directory);
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
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
}
