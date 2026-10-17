import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../instances/instance.dart';
import '../instances/instance_manager.dart';
import '../plugins/plugin_registry.dart';
import 'capture_writer.dart';
import 'log_hub.dart';
import 'log_models.dart';

/// The log sources a plugin declares for [instance], with paths rendered
/// inside the instance directory.
///
/// A source declared `stdout: true` is the relay's capture. A file source
/// whose path cannot be resolved inside the instance is left out; the plugin
/// loader rejects such manifests.
List<LogSourceSpec> logSourcesFor(
  Instance instance,
  PluginManifest manifest,
  String os,
) {
  final context = LaunchContext(
    settings: const {},
    ports: const {},
    paths: {
      'instance': instance.directory,
      'server': p.join(instance.directory, 'server'),
    },
    os: os,
  );
  final specs = <LogSourceSpec>[];
  for (final source in manifest.logs) {
    final encoding = LogEncoding.parse(source.encoding)!;
    if (source.isStdout) {
      specs.add(
        LogSourceSpec.stdout(
          name: source.name,
          encoding: encoding,
          directory: CaptureWriter.directoryFor(instance.directory),
        ),
      );
      continue;
    }
    final String? path;
    try {
      path = resolveInstancePath(
        renderTemplate(source.path!, context),
        instance.directory,
      );
    } on TemplateException {
      continue;
    }
    if (path == null) continue;
    specs.add(
      LogSourceSpec(
        name: source.name,
        kind: LogSourceKind.file,
        pattern: path,
        encoding: encoding,
        rotation: source.rotation == 'newest'
            ? LogRotation.newest
            : LogRotation.fixed,
      ),
    );
  }
  return specs;
}

/// Keeps the hub's sources in line with the instances: attaches every
/// instance whose plugin is loaded, re-attaches it when its sources change
/// and drops it (with its saved offsets) when it is deleted.
class InstanceLogSync {
  InstanceLogSync({
    required this.hub,
    required this.manager,
    required this.registry,
    required this.os,
  });

  final LogHub hub;
  final InstanceManager manager;
  final PluginRegistry registry;
  final String os;
  StreamSubscription<InstanceEvent>? _subscription;

  /// Attaches every instance now.
  Future<void> syncAll() async {
    for (final instance in manager.list()) {
      await _sync(instance);
    }
  }

  /// Follows instance events from now on.
  void listen() {
    _subscription = manager.events.listen((event) {
      switch (event) {
        case InstanceChanged(:final instance):
          unawaited(_sync(instance));
        case InstanceRemoved(:final instanceId):
          unawaited(hub.detach(instanceId, forget: true));
        case InstanceNotice():
          break;
      }
    });
  }

  Future<void> close() async => _subscription?.cancel();

  Future<void> _sync(Instance instance) async {
    final plugin = registry.find(instance.pluginId);
    if (plugin == null) return;
    try {
      await hub.attach(
        instance.id,
        logSourcesFor(instance, plugin.manifest, os),
      );
    } on Object {
      // A source that cannot be tailed reports it as its own status.
    }
  }
}
