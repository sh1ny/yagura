/// Setting value types of the manifest `settings` section.
enum SettingType {
  string,
  integer,
  number,
  boolean,
  enumeration('enum'),
  secret,
  stringList('string_list'),
  object,
  list;

  const SettingType([this._wire]);
  final String? _wire;

  /// The spelling used in the manifest.
  String get wireName => _wire ?? name;

  static SettingType parse(String wire) =>
      values.firstWhere((t) => t.wireName == wire);
}

/// One entry of the settings schema.
class SettingDef {
  const SettingDef({
    required this.name,
    required this.type,
    this.label,
    this.description,
    this.defaultValue,
    this.required = false,
    this.min,
    this.max,
    this.pattern,
    this.group,
    this.advanced = false,
    this.values = const [],
    this.fields = const {},
  });

  factory SettingDef.fromJson(String name, Map<String, Object?> json) =>
      SettingDef(
        name: name,
        type: SettingType.parse(json['type']! as String),
        label: json['label'] as String?,
        description: json['description'] as String?,
        defaultValue: json['default'],
        required: json['required'] as bool? ?? false,
        min: json['min'] as num?,
        max: json['max'] as num?,
        pattern: json['pattern'] as String?,
        group: json['group'] as String?,
        advanced: json['advanced'] as bool? ?? false,
        values: [...?(json['values'] as List<Object?>?)?.cast<String>()],
        fields: {
          for (final MapEntry(:key, :value)
              in ((json['fields'] as Map<String, Object?>?) ?? {}).entries)
            key: SettingDef.fromJson(key, value! as Map<String, Object?>),
        },
      );

  final String name;
  final SettingType type;
  final String? label;
  final String? description;
  final Object? defaultValue;
  final bool required;
  final num? min;
  final num? max;
  final String? pattern;
  final String? group;
  final bool advanced;

  /// Allowed values of an `enum` setting.
  final List<String> values;

  /// Nested fields of an `object`, or the columns of a `list` row.
  final Map<String, SettingDef> fields;
}

enum PortProtocol { udp, tcp, both }

enum PortPurpose { game, query, rcon, web, other }

/// A declared port: either a default number or derived from another port.
class PortDecl {
  const PortDecl({
    required this.name,
    required this.protocol,
    required this.purpose,
    required this.exposed,
    this.defaultNumber,
    this.deriveFrom,
    this.deriveOffset,
  });

  factory PortDecl.fromJson(Map<String, Object?> json) {
    final purpose = PortPurpose.values.byName(json['purpose']! as String);
    final derive = json['derive'] as Map<String, Object?>?;
    return PortDecl(
      name: json['name']! as String,
      protocol: PortProtocol.values.byName(json['protocol']! as String),
      purpose: purpose,
      exposed: json['exposed'] as bool? ?? purpose != PortPurpose.rcon,
      defaultNumber: json['default'] as int?,
      deriveFrom: derive?['from'] as String?,
      deriveOffset: derive?['offset'] as int?,
    );
  }

  final String name;
  final PortProtocol protocol;
  final PortPurpose purpose;

  /// Whether the firewall opens this port (default true, false for RCON).
  final bool exposed;
  final int? defaultNumber;
  final String? deriveFrom;
  final int? deriveOffset;

  bool get isDerived => deriveFrom != null;
}

/// One entry of `launch.args`.
sealed class LaunchEntry {
  const LaunchEntry({this.when, this.unless});

  factory LaunchEntry.fromJson(Object? json) {
    if (json is String) return LiteralEntry(json);
    if (json is! Map<String, Object?>) {
      throw ArgumentError('Not a launch entry: $json');
    }
    final when = json['when'] as String?;
    final unless = json['unless'] as String?;
    if (json['join'] case final Map<String, Object?> join) {
      return JoinEntry(
        list: join['list']! as String,
        separator: join['separator']! as String,
        prefix: join['prefix'] as String? ?? '',
        when: when,
        unless: unless,
      );
    }
    return GroupEntry(
      [for (final e in json['args']! as List<Object?>) LaunchEntry.fromJson(e)],
      when: when,
      unless: unless,
    );
  }

  /// Reference that must be true for this entry to apply.
  final String? when;

  /// Reference that must not be true for this entry to apply.
  final String? unless;
}

/// A templated string rendering to one argv entry.
class LiteralEntry extends LaunchEntry {
  const LiteralEntry(this.template);
  final String template;
}

/// Entries rendered only when the condition holds.
class GroupEntry extends LaunchEntry {
  const GroupEntry(this.entries, {super.when, super.unless});
  final List<LaunchEntry> entries;
}

/// A `string_list` setting joined into one argv entry: `prefix` followed by
/// the items joined with `separator`. Renders nothing for an empty list.
class JoinEntry extends LaunchEntry {
  const JoinEntry({
    required this.list,
    required this.separator,
    this.prefix = '',
    super.when,
    super.unless,
  });
  final String list;
  final String separator;
  final String prefix;
}

enum StopStrategy { signal, kill, rcon }

class StopSpec {
  const StopSpec({this.strategy = StopStrategy.signal, this.graceSeconds = 30});
  final StopStrategy strategy;
  final int graceSeconds;
}

enum HealthType { process, port, logMatch, query }

class HealthSpec {
  const HealthSpec({
    this.type = HealthType.process,
    this.port,
    this.logMatch,
    this.source,
    this.startTimeoutSeconds = 120,
  });
  final HealthType type;
  final String? port;
  final String? logMatch;
  final String? source;
  final int startTimeoutSeconds;
}

class LogSource {
  const LogSource({
    required this.name,
    required this.path,
    this.encoding = 'utf-8',
    this.rotation = 'fixed',
  });
  final String name;

  /// Templated path inside the instance directory.
  final String path;
  final String encoding;
  final String rotation;
}

class SteamSpec {
  const SteamSpec({
    required this.appId,
    this.anonymous = true,
    this.sizeHintBytes,
  });
  final int appId;
  final bool anonymous;
  final int? sizeHintBytes;
}

/// The validated plugin manifest.
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.executables,
    required this.ports,
    required this.settings,
    required this.rawSettings,
    required this.launchArgs,
    required this.stop,
    required this.health,
    required this.dataPaths,
    required this.logs,
    required this.hooksTimeoutSeconds,
    this.description,
    this.steam,
  });

  /// Builds the model from a document that passed the manifest schema.
  factory PluginManifest.fromJson(Map<String, Object?> json) {
    final stop = json['stop'] as Map<String, Object?>?;
    final health = json['health'] as Map<String, Object?>?;
    final steam = json['steam'] as Map<String, Object?>?;
    final rawSettings = (json['settings'] as Map<String, Object?>?) ?? {};
    final launch = json['launch']! as Map<String, Object?>;
    final hooks = json['hooks'] as Map<String, Object?>?;
    return PluginManifest(
      id: json['id']! as String,
      name: json['name']! as String,
      version: json['version']! as String,
      description: json['description'] as String?,
      steam: steam == null
          ? null
          : SteamSpec(
              appId: steam['app_id']! as int,
              anonymous: steam['login'] != 'account',
              sizeHintBytes: steam['size_hint_bytes'] as int?,
            ),
      executables: (json['executable']! as Map<String, Object?>)
          .cast<String, String>(),
      ports: [
        for (final p in (json['ports'] as List<Object?>?) ?? const [])
          PortDecl.fromJson(p! as Map<String, Object?>),
      ],
      settings: {
        for (final MapEntry(:key, :value) in rawSettings.entries)
          key: SettingDef.fromJson(key, value! as Map<String, Object?>),
      },
      rawSettings: rawSettings,
      launchArgs: [
        for (final e in launch['args']! as List<Object?>)
          LaunchEntry.fromJson(e),
      ],
      stop: stop == null
          ? const StopSpec()
          : StopSpec(
              strategy: StopStrategy.values.byName(stop['strategy']! as String),
              graceSeconds: stop['grace_seconds'] as int? ?? 30,
            ),
      health: health == null
          ? const HealthSpec()
          : HealthSpec(
              type: switch (health['type']! as String) {
                'log_match' => HealthType.logMatch,
                final t => HealthType.values.byName(t),
              },
              port: health['port'] as String?,
              logMatch: health['log_match'] as String?,
              source: health['source'] as String?,
              startTimeoutSeconds:
                  health['start_timeout_seconds'] as int? ?? 120,
            ),
      dataPaths: [...?(json['data_paths'] as List<Object?>?)?.cast<String>()],
      logs: [
        for (final l in (json['logs'] as List<Object?>?) ?? const [])
          LogSource(
            name: (l! as Map<String, Object?>)['name']! as String,
            path: l['path']! as String,
            encoding: l['encoding'] as String? ?? 'utf-8',
            rotation: l['rotation'] as String? ?? 'fixed',
          ),
      ],
      hooksTimeoutSeconds:
          hooks?['timeout_seconds'] as int? ?? defaultHookTimeoutSeconds,
    );
  }

  /// Hook deadline when the manifest does not set one.
  static const defaultHookTimeoutSeconds = 5;

  /// Largest hook deadline a manifest may declare.
  static const maxHookTimeoutSeconds = 60;

  final String id;
  final String name;
  final String version;
  final String? description;
  final SteamSpec? steam;

  /// Executable per OS name (`windows`, `linux`).
  final Map<String, String> executables;
  final List<PortDecl> ports;
  final Map<String, SettingDef> settings;

  /// The settings section as parsed JSON, the input of the schema version.
  final Map<String, Object?> rawSettings;
  final List<LaunchEntry> launchArgs;
  final StopSpec stop;
  final HealthSpec health;
  final List<String> dataPaths;
  final List<LogSource> logs;
  final int hooksTimeoutSeconds;

  /// Operating systems with a declared executable, sorted.
  List<String> get platforms => executables.keys.toList()..sort();
}
