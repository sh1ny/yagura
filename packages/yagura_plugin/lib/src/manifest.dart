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
    this.path,
    this.stdout = false,
    this.encoding = 'utf-8',
    this.rotation = 'fixed',
  });
  final String name;

  /// Templated path inside the instance directory, with wildcards in the file
  /// name; null for a stdout capture.
  final String? path;

  /// The source is the server's captured standard output and error.
  final bool stdout;
  final String encoding;

  /// `fixed` or `newest`; meaningful for file sources only.
  final String rotation;

  bool get isStdout => stdout;
}

/// The file formats a binding or a hook file edit may name in this version.
const supportedConfigFormats = ['json', 'ini', 'dayz-cfg', 'kv'];

/// Formats of a later version: named in a binding or an edit they are refused
/// with `unsupported_in_this_version`.
const laterConfigFormats = ['ue-ini', 'xml', 'vdf'];

/// The most distinct files a plugin's bindings may name.
const maxBoundFiles = 64;

/// One entry of `bindings`: a setting written to one key of one file.
class FileBinding {
  const FileBinding({
    required this.file,
    required this.format,
    required this.key,
    required this.setting,
    this.create = false,
    this.template,
    this.gameWrites = false,
  });

  factory FileBinding.fromJson(Map<String, Object?> json) => FileBinding(
    file: json['file']! as String,
    format: json['format']! as String,
    key: json['key']! as String,
    setting: json['setting']! as String,
    create: json['create'] as bool? ?? false,
    template: json['template'] as String?,
    gameWrites: json['game_writes'] as bool? ?? false,
  );

  /// The templated path, relative to the instance directory.
  final String file;

  /// One of [supportedConfigFormats].
  final String format;

  /// The key path in the file.
  final String key;

  /// The top-level setting whose value is written.
  final String setting;

  /// Whether a missing file is created instead of failing the start.
  final bool create;

  /// A file of the plugin directory a missing file is created from.
  final String? template;

  /// Whether the game rewrites the file itself.
  final bool gameWrites;
}

/// The `secret` setting that holds the instance's Game Server Login Token,
/// named by `steam.gslt`.
class GsltSpec {
  const GsltSpec({required this.setting, this.required = false});

  factory GsltSpec.fromJson(Map<String, Object?> json) => GsltSpec(
    setting: json['setting']! as String,
    required: json['required'] as bool? ?? false,
  );

  /// The name of a top-level `secret` setting.
  final String setting;

  /// Whether Start fails `gslt_required` while the setting is unset.
  final bool required;
}

/// How a plugin's server is downloaded from Steam (`steam.login`).
enum SteamLogin {
  /// Always the anonymous login.
  anonymous,

  /// Needs the Steam account linked to the instance.
  account,

  /// The linked account when there is one, else the anonymous login.
  accountOptional,
}

class SteamSpec {
  const SteamSpec({
    required this.appId,
    this.login = SteamLogin.anonymous,
    this.sizeHintBytes,
    this.gslt,
  });
  final int appId;
  final SteamLogin login;

  /// Whether the download never uses an account.
  bool get anonymous => login == SteamLogin.anonymous;
  final int? sizeHintBytes;
  final GsltSpec? gslt;
}

/// Where an instance's mods come from. `url_archive` is a later version's.
enum ModSource {
  steamWorkshop('steam_workshop'),
  serverManaged('server_managed');

  const ModSource(this.wireName);

  /// The spelling used in the manifest.
  final String wireName;
}

/// How a mod reaches the server: a directory link, a copy, or not at all (the
/// server fetches its own mods; role lists carry item ids).
enum ModStage { link, copy, none }

/// One entry of `mods.keys`: files of a staged mod matching [from] are placed
/// in the directory [to].
class ModKeyRule {
  const ModKeyRule({required this.from, required this.to});

  factory ModKeyRule.fromJson(Map<String, Object?> json) =>
      ModKeyRule(from: json['from']! as String, to: json['to']! as String);

  /// A glob over the files of the mod's content.
  final String from;

  /// A directory, relative to the instance root.
  final String to;
}

/// The `mods` section: how a plugin's mods are acquired, staged and ordered.
class ModsSpec {
  const ModsSpec({
    required this.source,
    required this.stage,
    required this.roles,
    this.workshopAppId,
    this.stageDir = defaultStageDir,
    this.linkName = defaultLinkName,
    this.copyFallback = false,
    this.keys = const [],
  });

  factory ModsSpec.fromJson(Map<String, Object?> json) {
    final source = ModSource.values.firstWhere(
      (s) => s.wireName == json['source'],
    );
    return ModsSpec(
      source: source,
      workshopAppId: json['workshop_app_id'] as int?,
      stage: switch (json['stage']) {
        final String name => ModStage.values.byName(name),
        _ => source == ModSource.serverManaged ? ModStage.none : ModStage.link,
      },
      stageDir: json['stage_dir'] as String? ?? defaultStageDir,
      linkName: json['link_name'] as String? ?? defaultLinkName,
      copyFallback: json['copy_fallback'] as bool? ?? false,
      keys: [
        for (final k in (json['keys'] as List<Object?>?) ?? const [])
          ModKeyRule.fromJson(k! as Map<String, Object?>),
      ],
      roles: [...(json['roles']! as List<Object?>).cast<String>()],
    );
  }

  /// The stage directory when the manifest names none.
  static const defaultStageDir = 'server';

  /// The link name template when the manifest names none.
  static const defaultLinkName = '{{mod.name_safe}}';

  final ModSource source;

  /// The Steam app the workshop items belong to; `steam_workshop` only.
  final int? workshopAppId;
  final ModStage stage;

  /// Where links or copies are made, relative to the instance root.
  final String stageDir;

  /// The template of a staged mod's name; `{{mod.name_safe}}` is its sanitised
  /// title.
  final String linkName;

  /// Copy a mod whose link could not be created.
  final bool copyFallback;
  final List<ModKeyRule> keys;

  /// The roles a mod can have; each is a list in the launch templates.
  final List<String> roles;
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
    this.bindings = const [],
    this.mods,
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
              login: switch (steam['login']) {
                'account' => SteamLogin.account,
                'account_optional' => SteamLogin.accountOptional,
                _ => SteamLogin.anonymous,
              },
              sizeHintBytes: steam['size_hint_bytes'] as int?,
              gslt: switch (steam['gslt']) {
                final Map<String, Object?> gslt => GsltSpec.fromJson(gslt),
                _ => null,
              },
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
            path: l['path'] as String?,
            stdout: l['stdout'] == true,
            encoding: l['encoding'] as String? ?? 'utf-8',
            rotation: l['rotation'] as String? ?? 'fixed',
          ),
      ],
      hooksTimeoutSeconds:
          hooks?['timeout_seconds'] as int? ?? defaultHookTimeoutSeconds,
      bindings: [
        for (final b in (json['bindings'] as List<Object?>?) ?? const [])
          FileBinding.fromJson(b! as Map<String, Object?>),
      ],
      mods: switch (json['mods']) {
        final Map<String, Object?> mods => ModsSpec.fromJson(mods),
        _ => null,
      },
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

  /// The settings written into game files, in the manifest's order.
  final List<FileBinding> bindings;

  /// How the plugin's mods are acquired and staged; null when it has none.
  final ModsSpec? mods;

  /// Operating systems with a declared executable, sorted.
  List<String> get platforms => executables.keys.toList()..sort();
}
