import 'package:path/path.dart' as p;

import '../errors.dart';

/// The JSON context every hook receives as its only argument.
///
/// Contains the instance and plugin identity, the OS, paths relative to the
/// instance root, settings (secrets replaced by `{"secret": true, "set":
/// bool}`) and ports. The same shape is passed to every hook point;
/// `migrateSettings` adds the versions it migrates between.
class HookContext {
  HookContext({
    required this.instanceId,
    required this.pluginId,
    required this.pluginVersion,
    required this.os,
    this.paths = const {},
    this.settings = const {},
    this.ports = const {},
    this.fromVersion,
    this.toVersion,
  }) {
    if (os != 'windows' && os != 'linux') {
      throw ArgumentError.value(os, 'os', 'expected "windows" or "linux"');
    }
    for (final entry in paths.entries) {
      final path = entry.value;
      if (p.isAbsolute(path) || p.split(path).contains('..')) {
        throw ArgumentError.value(
          path,
          'paths.${entry.key}',
          'must be relative to the instance root',
        );
      }
    }
    for (final entry in settings.entries) {
      final value = entry.value;
      if (value is Map && value.containsKey('secret')) {
        if (value.length != 2 ||
            value['secret'] != true ||
            value['set'] is! bool) {
          throw ArgumentError.value(
            value,
            'settings.${entry.key}',
            'a secret may only appear as {"secret": true, "set": bool}',
          );
        }
      }
    }
  }

  final String instanceId;
  final String pluginId;
  final String pluginVersion;

  /// `windows` or `linux`.
  final String os;

  /// Named paths relative to the instance root.
  final Map<String, String> paths;

  /// Setting values by key; secrets as `{"secret": true, "set": bool}`.
  final Map<String, Object?> settings;

  /// Port numbers by name.
  final Map<String, int> ports;

  /// The plugin versions a `migrateSettings` call moves the settings between;
  /// absent from every other hook's context.
  final String? fromVersion;
  final String? toVersion;

  /// Largest serialised context a hook receives.
  static const maxBytes = 1024 * 1024;

  Map<String, Object?> toJson() => {
    'instanceId': instanceId,
    'pluginId': pluginId,
    'pluginVersion': pluginVersion,
    'os': os,
    'paths': paths,
    'settings': settings,
    'ports': ports,
    'fromVersion': ?fromVersion,
    'toVersion': ?toVersion,
  };

  /// Throws `internal_error` when the context exceeds [maxBytes].
  void checkSize(int bytes) {
    if (bytes > maxBytes) {
      throw YaguraException(
        'internal_error',
        'the hook context is $bytes bytes, over the 1 MiB limit',
      );
    }
  }
}
