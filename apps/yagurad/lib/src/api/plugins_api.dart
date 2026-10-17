import 'package:grpc/grpc.dart';
import 'package:yagura_plugin/yagura_plugin.dart' as plugin;
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/daemon.dart';
import '../plugins/plugin_registry.dart';
import 'convert.dart';
import 'service_support.dart';

/// The `Plugins` service.
class PluginsApi extends pb.PluginsServiceBase with GuardedService {
  PluginsApi(this.daemon, this.logSink);

  final Daemon daemon;

  @override
  final LogSink logSink;

  @override
  Future<pb.ListPluginsResponse> listPlugins(
    ServiceCall call,
    pb.ListPluginsRequest request,
  ) async => pb.ListPluginsResponse(
    plugins: [
      for (final result in daemon.plugins.results)
        _summary(result, daemon.plugins.find(result.id)),
    ],
  );

  @override
  Future<pb.PluginDetail> getPlugin(
    ServiceCall call,
    pb.GetPluginRequest request,
  ) async {
    final loaded = daemon.plugins.find(request.pluginId);
    final result = daemon.plugins.results
        .where((r) => r.id == request.pluginId)
        .firstOrNull;
    if (result == null) {
      throw YaguraException(
        'plugin_missing',
        'there is no plugin ${request.pluginId}',
        details: {'pluginId': request.pluginId},
      );
    }
    final manifest = loaded?.manifest;
    return pb.PluginDetail(
      summary: _summary(result, loaded),
      settingsSchema: loaded == null
          ? null
          : pb.JsonDocument(
              json: plugin.canonicalJson(manifest!.rawSettings),
              schemaVersion: loaded.schemaVersion,
            ),
      defaultPorts: [
        if (manifest != null)
          for (final port in manifest.ports)
            pb.Port(
              name: port.name,
              number: port.defaultNumber ?? 0,
              protocol: protocolToPb(port.protocol),
              purpose: port.purpose.name,
              exposed: port.exposed,
            ),
      ],
      logSources: [
        if (manifest != null)
          for (final l in manifest.logs) l.name,
      ],
    );
  }

  @override
  Future<pb.ReloadPluginsResponse> reloadPlugins(
    ServiceCall call,
    pb.ReloadPluginsRequest request,
  ) async {
    final outcomes = await daemon.instances.reloadPlugins();
    final wanted = request.pluginIds.toSet();
    return pb.ReloadPluginsResponse(
      results: [
        for (final outcome in outcomes)
          if (wanted.isEmpty || wanted.contains(outcome.id))
            pb.PluginReloadResult(
              pluginId: outcome.id,
              outcome: switch (outcome.status) {
                PluginReloadStatus.loaded => 'added',
                PluginReloadStatus.reloaded => 'reloaded',
                PluginReloadStatus.reloadFailed ||
                PluginReloadStatus.rejected => 'reload_failed',
                PluginReloadStatus.removed => 'removed',
              },
              problems: [for (final r in outcome.reasons) _problem(r)],
            ),
      ],
    );
  }

  pb.PluginSummary _summary(plugin.PluginResult result, LoadedPlugin? loaded) {
    final manifest = result.manifest;
    return pb.PluginSummary(
      id: result.id,
      name: result.name ?? result.id,
      version: result.version ?? '',
      manifestVersion: 1,
      status: result.isLoaded
          ? pb.PluginStatus.PLUGIN_STATUS_LOADED
          : pb.PluginStatus.PLUGIN_STATUS_REJECTED,
      platforms: result.platforms,
      problems: [for (final r in result.reasons) _problem(r)],
      hasHooks: loaded?.hooksSource != null,
      rconProtocol: 'none',
      steamLogin: manifest?.steam == null
          ? ''
          : (manifest!.steam!.anonymous ? 'anonymous' : 'account'),
    );
  }

  pb.PluginProblem _problem(plugin.PluginReason reason) => pb.PluginProblem(
    reason: reason.code,
    path: reason.path ?? '',
    line: reason.line ?? 0,
    message: reason.message,
  );
}
