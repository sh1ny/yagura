import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../errors.dart';
import '../hooks/hooks.dart';

/// A plugin that passed validation, with the text of its `hooks.js` read at
/// load time, so an operation that holds it keeps this version.
class LoadedPlugin {
  const LoadedPlugin({
    required this.folder,
    required this.directory,
    required this.manifest,
    required this.schemaVersion,
    this.hooksSource,
  });

  final String folder;
  final String directory;
  final PluginManifest manifest;
  final int schemaVersion;
  final String? hooksSource;

  String get id => manifest.id;
}

/// What an explicit reload did to one plugin.
enum PluginReloadStatus {
  /// A plugin that was not loaded before now is.
  loaded,

  /// A loaded plugin was replaced by its edited version.
  reloaded,

  /// The edit no longer validates; the previous version stays active.
  reloadFailed,

  /// A plugin that was not loaded before still does not validate.
  rejected,

  /// The plugin folder is gone; instances of it become `plugin_missing`.
  removed,
}

class PluginReloadOutcome {
  const PluginReloadOutcome(this.id, this.status, [this.reasons = const []]);

  final String id;
  final PluginReloadStatus status;
  final List<PluginReason> reasons;

  @override
  String toString() => 'PluginReloadOutcome($id ${status.name})';
}

/// The loaded plugins of `<data>/plugins/`. Loaded at startup and reloaded
/// only on explicit request, never on file change.
class PluginRegistry {
  PluginRegistry({required this.pluginsDirectory, required this.hooks});

  final String pluginsDirectory;
  final HookHost hooks;

  /// Latest result per plugin folder.
  final _results = <String, PluginResult>{};

  /// The active version per plugin folder.
  final _loaded = <String, LoadedPlugin>{};

  /// Status of every plugin folder, as of the last load or reload, ordered by
  /// folder. A folder whose reload failed lists as `loaded` while its
  /// previous version stays active.
  List<PluginResult> get results => [
    for (final folder in _results.keys.toList()..sort()) _results[folder]!,
  ];

  /// The active plugin with manifest id [pluginId], if any.
  LoadedPlugin? find(String pluginId) {
    for (final plugin in _loaded.values) {
      if (plugin.id == pluginId) return plugin;
    }
    return null;
  }

  /// Loads every plugin folder and returns the result of each, ordered by
  /// folder.
  Future<List<PluginResult>> load() async {
    _results.clear();
    _loaded.clear();
    for (final folder in _folders()) {
      final (result, plugin) = await _loadFolder(folder);
      _results[folder] = result;
      if (plugin != null) _loaded[folder] = plugin;
    }
    return results;
  }

  /// Reloads on explicit request: a fixed plugin replaces the old version, a
  /// broken edit keeps the previous version active, a removed folder removes
  /// the plugin.
  ///
  /// With [pluginIds] only the plugins with those manifest ids are touched;
  /// empty reloads all.
  Future<List<PluginReloadOutcome>> reload({
    Set<String> pluginIds = const {},
  }) async {
    final outcomes = <PluginReloadOutcome>[];
    final folders = _folders();
    bool selected(Iterable<String?> ids) =>
        pluginIds.isEmpty || ids.any(pluginIds.contains);
    for (final folder in folders) {
      final (result, plugin) = await _loadFolder(folder);
      final previous = _loaded[folder];
      if (!selected([plugin?.id, previous?.id, result.id])) continue;
      if (plugin != null) {
        _loaded[folder] = plugin;
        _results[folder] = result;
        outcomes.add(
          PluginReloadOutcome(
            plugin.id,
            previous == null
                ? PluginReloadStatus.loaded
                : PluginReloadStatus.reloaded,
          ),
        );
      } else if (previous != null) {
        // Keep the previous version active and listed as loaded.
        outcomes.add(
          PluginReloadOutcome(
            previous.id,
            PluginReloadStatus.reloadFailed,
            result.reasons,
          ),
        );
      } else {
        _results[folder] = result;
        outcomes.add(
          PluginReloadOutcome(
            result.id,
            PluginReloadStatus.rejected,
            result.reasons,
          ),
        );
      }
    }
    for (final folder in _results.keys.toList()) {
      if (folders.contains(folder)) continue;
      if (!selected([_loaded[folder]?.id, _results[folder]?.id])) continue;
      final gone = _loaded.remove(folder);
      final result = _results.remove(folder)!;
      outcomes.add(
        PluginReloadOutcome(gone?.id ?? result.id, PluginReloadStatus.removed),
      );
    }
    return outcomes;
  }

  List<String> _folders() {
    final directory = Directory(pluginsDirectory);
    if (!directory.existsSync()) return const [];
    return [
      for (final entry in directory.listSync().whereType<Directory>())
        if (File(p.join(entry.path, 'plugin.yaml')).existsSync())
          p.basename(entry.path),
    ]..sort();
  }

  Future<(PluginResult, LoadedPlugin?)> _loadFolder(String folder) async {
    final directory = p.join(pluginsDirectory, folder);
    final result = loadPlugin(directory);
    final manifest = result.manifest;
    if (!result.isLoaded || manifest == null) return (result, null);

    String? hooksSource;
    final hooksFile = File(p.join(directory, 'hooks.js'));
    if (hooksFile.existsSync()) {
      try {
        hooksSource = utf8.decode(hooksFile.readAsBytesSync());
      } on FormatException catch (e) {
        return (
          PluginResult(
            id: result.id,
            status: PluginStatus.rejected,
            name: result.name,
            version: result.version,
            platforms: result.platforms,
            reasons: [
              PluginReason(
                code: 'hook_syntax_error',
                path: 'hooks.js',
                message: 'hooks.js is not valid UTF-8: ${e.message}',
              ),
            ],
          ),
          null,
        );
      }
      final reason = await _checkHooks(hooksSource, directory);
      if (reason != null) {
        return (
          PluginResult(
            id: result.id,
            status: PluginStatus.rejected,
            name: result.name,
            version: result.version,
            platforms: result.platforms,
            reasons: [reason],
          ),
          null,
        );
      }
    }
    return (
      result,
      LoadedPlugin(
        folder: folder,
        directory: directory,
        manifest: manifest,
        schemaVersion: schemaVersion(manifest),
        hooksSource: hooksSource,
      ),
    );
  }

  /// Rejects a `hooks.js` that does not load: a syntax error (with its line)
  /// or a top level that throws or does not finish.
  Future<PluginReason?> _checkHooks(String source, String directory) async {
    try {
      await hooks.checkLoads(source: source, rootPath: directory);
      return null;
    } on YaguraException catch (e) {
      if (!_loadFailures.contains(e.reason)) return null;
      final location = '${e.message}\n${e.details['stack'] ?? ''}';
      final line = RegExp(r'hooks\.js:(\d+)').firstMatch(location)?.group(1);
      return PluginReason(
        code: e.reason,
        path: 'hooks.js',
        message: e.message,
        line: line == null ? null : int.parse(line),
      );
    }
  }

  /// Hook errors that mean the script itself is broken; others (a degraded
  /// runtime, a cancelled wait) say nothing about the plugin.
  static const _loadFailures = {
    'hook_syntax_error',
    'hook_error',
    'hook_timeout',
    'hook_out_of_memory',
  };
}
