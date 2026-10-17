import 'manifest.dart';

/// Whether a plugin folder passed validation.
enum PluginStatus { loaded, rejected }

/// One reason a plugin was rejected.
class PluginReason {
  const PluginReason({
    required this.code,
    required this.message,
    this.path,
    this.line,
  });

  /// Machine-readable reason code, for example `unsupported_manifest_version`.
  final String code;

  /// Field path in the manifest, for example `ports[0].protocol`.
  final String? path;

  /// Human-readable explanation, naming the field and the allowed values.
  final String message;

  /// 1-based line in the offending file, when known.
  final int? line;

  @override
  String toString() {
    final where = [?path, if (line != null) 'line $line'].join(', ');
    return '[$code]${where.isEmpty ? '' : ' $where:'} $message';
  }
}

/// The outcome of loading one plugin folder.
class PluginResult {
  const PluginResult({
    required this.id,
    required this.status,
    this.name,
    this.version,
    this.platforms = const [],
    this.reasons = const [],
    this.manifest,
  });

  /// The manifest `id` when it could be read, otherwise the folder name.
  final String id;
  final PluginStatus status;
  final String? name;
  final String? version;

  /// Operating systems that have an executable declared (`windows`, `linux`).
  final List<String> platforms;
  final List<PluginReason> reasons;

  /// Present only when [status] is [PluginStatus.loaded].
  final PluginManifest? manifest;

  bool get isLoaded => status == PluginStatus.loaded;
}
