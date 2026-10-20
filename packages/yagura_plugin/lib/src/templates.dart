import 'package:path/path.dart' as p;

import 'manifest.dart';

/// The values a launch template renders against.
class LaunchContext {
  const LaunchContext({
    required this.settings,
    required this.ports,
    required this.paths,
    required this.os,
    this.mods = const {},
    this.secretsSet = const {},
  });

  /// Validated setting values (defaults applied), see `validateSettings`.
  final Map<String, Object?> settings;

  /// Resolved port numbers by port name, see `resolvePorts`.
  final Map<String, int> ports;

  /// Directories by name: `instance` and `server`.
  final Map<String, String> paths;

  /// `windows` or `linux`.
  final String os;

  /// The instance's ordered mod list per role: staged names, or item ids for
  /// stage `none`. A role without an entry is empty.
  final Map<String, List<String>> mods;

  /// The names of the `secret` settings that have a value. An argument that
  /// names one that has none renders nothing. The values themselves never
  /// pass through the renderer.
  final Set<String> secretsSet;
}

/// Thrown when a template cannot be parsed or rendered.
class TemplateException implements Exception {
  const TemplateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The names a template may reference, for load-time checking.
class TemplateScope {
  const TemplateScope({
    required this.settings,
    required this.ports,
    this.allowSettings = true,
    this.allowPorts = true,
    this.allowSecrets = false,
    this.allowMods = false,
    this.roles = const {},
  });

  final Map<String, SettingDef> settings;
  final Set<String> ports;
  final bool allowSettings;
  final bool allowPorts;

  /// `secrets.<setting>` is available: in launch arguments only.
  final bool allowSecrets;

  /// `mods.<role>` is available: in launch arguments only.
  final bool allowMods;

  /// The roles the manifest's `mods` section declares.
  final Set<String> roles;
}

/// Directories a template can name through `paths.<name>`; `{{instance}}` is
/// a shorthand for `paths.instance`.
const templatePathNames = {'instance', 'server'};

/// A parsed template: literal text and `{{reference}}` segments.
sealed class TemplatePart {
  const TemplatePart();
}

class TemplateText extends TemplatePart {
  const TemplateText(this.text);
  final String text;
}

class TemplateRef extends TemplatePart {
  const TemplateRef(this.reference);

  /// The reference without braces and whitespace, such as `settings.name`.
  final String reference;

  List<String> get segments => reference.split('.');
}

final _referencePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)*$');

/// Splits [template] into text and references. A `{{` always opens a
/// reference; there is no escape.
List<TemplatePart> parseTemplate(String template) {
  final parts = <TemplatePart>[];
  var index = 0;
  while (index < template.length) {
    final open = template.indexOf('{{', index);
    if (open < 0) {
      parts.add(TemplateText(template.substring(index)));
      break;
    }
    if (open > index) parts.add(TemplateText(template.substring(index, open)));
    final close = template.indexOf('}}', open + 2);
    if (close < 0) {
      throw TemplateException('unterminated "{{" in template "$template"');
    }
    final reference = template.substring(open + 2, close).trim();
    if (!_referencePattern.hasMatch(reference)) {
      throw TemplateException(
        'invalid reference "{{$reference}}" in template "$template"',
      );
    }
    parts.add(TemplateRef(reference));
    index = close + 2;
  }
  return parts;
}

const _scalarTypes = {
  SettingType.string,
  SettingType.integer,
  SettingType.number,
  SettingType.boolean,
  SettingType.enumeration,
};

/// Resolves a `settings.<path>` reference in the schema, or explains why not.
(SettingDef?, String?) _lookupSetting(
  List<String> segments,
  Map<String, SettingDef> settings,
) {
  var fields = settings;
  SettingDef? def;
  for (final name in segments.skip(1)) {
    final next = fields[name];
    if (next == null) {
      return (null, 'unknown setting path ${segments.join('.')}');
    }
    def = next;
    fields = next.type == SettingType.object ? next.fields : const {};
  }
  if (def == null) return (null, 'settings needs a setting name');
  return (def, null);
}

/// Checks that [reference] points at something that exists and has a type
/// that suits [expected]; returns an explanation, or null when valid.
///
/// [expected] is `scalar` for interpolation, `boolean` for conditions and
/// `list` for joins.
String? checkReference(
  String reference,
  TemplateScope scope, {
  String expected = 'scalar',
}) {
  final segments = reference.split('.');
  switch (segments.first) {
    case 'settings':
      if (!scope.allowSettings) return 'settings are not available here';
      final (def, problem) = _lookupSetting(segments, scope.settings);
      if (def == null) return problem;
      final ok = switch (expected) {
        'boolean' => def.type == SettingType.boolean,
        'list' => def.type == SettingType.stringList,
        _ => _scalarTypes.contains(def.type),
      };
      if (ok) return null;
      if (def.type == SettingType.secret && expected == 'scalar') {
        return '$reference is a secret and cannot be read through settings'
            '${scope.allowSecrets ? '; a launch argument writes it as '
                '{{secrets.${segments.last}}}' : ''}';
      }
      return switch (expected) {
        'boolean' => '$reference is a ${def.type.wireName}, not a boolean',
        'list' => '$reference is a ${def.type.wireName}, not a string_list',
        _ =>
          '$reference is a ${def.type.wireName} and cannot be written '
              'into a string${def.type == SettingType.stringList ? '; use join' : ''}',
      };
    case 'secrets':
      if (!scope.allowSecrets) {
        return 'secrets are only available in launch arguments';
      }
      if (expected != 'scalar') return '$reference is a secret, not a $expected';
      if (segments.length != 2) return 'secrets needs a setting name';
      final def = scope.settings[segments[1]];
      if (def == null) return 'unknown setting ${segments[1]}';
      if (def.type != SettingType.secret) {
        return '$reference names a ${def.type.wireName} setting, not a '
            'secret; use {{settings.${segments[1]}}}';
      }
      return null;
    case 'mods':
      if (!scope.allowMods) return 'mods are only available in launch arguments';
      if (segments.length != 2 || !scope.roles.contains(segments[1])) {
        return scope.roles.isEmpty
            ? 'unknown mod role $reference (the manifest declares no mods '
                  'section)'
            : 'unknown mod role $reference (declared roles: '
                  '${scope.roles.join(', ')})';
      }
      return expected == 'list'
          ? null
          : '$reference is a list of mods, not a $expected; use join';
    case 'ports':
      if (!scope.allowPorts) return 'ports are not available here';
      if (expected != 'scalar') return '$reference is not a $expected';
      if (segments.length != 2 || !scope.ports.contains(segments[1])) {
        return 'unknown port path $reference';
      }
      return null;
    case 'paths':
      if (expected != 'scalar') return '$reference is not a $expected';
      if (segments.length != 2 || !templatePathNames.contains(segments[1])) {
        return 'unknown path $reference '
            '(known: ${templatePathNames.map((n) => 'paths.$n').join(', ')})';
      }
      return null;
    case 'instance' || 'os':
      if (segments.length != 1 || expected != 'scalar') {
        return 'unknown reference $reference';
      }
      return null;
    default:
      return 'unknown namespace "${segments.first}" in $reference '
          '(known: settings, ports, paths, os, instance, mods, secrets)';
  }
}

/// Load-time check of every reference in [template]; returns explanations.
List<String> checkTemplate(String template, TemplateScope scope) {
  final List<TemplatePart> parts;
  try {
    parts = parseTemplate(template);
  } on TemplateException catch (e) {
    return [e.message];
  }
  return [
    for (final TemplateRef(:reference) in parts.whereType<TemplateRef>())
      ?_describe(template, reference, checkReference(reference, scope)),
  ];
}

String? _describe(String template, String reference, String? problem) =>
    problem == null
    ? null
    : 'template "$template" uses {{$reference}}: $problem';

Object? _lookupValue(List<String> segments, Map<String, Object?> settings) {
  Object? current = settings;
  for (final name in segments.skip(1)) {
    if (current is! Map<String, Object?>) return null;
    current = current[name];
  }
  return current;
}

String _resolveReference(String reference, LaunchContext context) {
  final segments = reference.split('.');
  final value = switch (segments.first) {
    'settings' => _lookupValue(segments, context.settings),
    'ports' => context.ports[segments.elementAtOrNull(1)],
    'paths' => context.paths[segments.elementAtOrNull(1)],
    'instance' => context.paths['instance'],
    'os' => context.os,
    _ => null,
  };
  if (value == null) {
    throw TemplateException('{{$reference}} has no value');
  }
  return '$value';
}

/// Renders one template string.
String renderTemplate(String template, LaunchContext context) {
  final out = StringBuffer();
  for (final part in parseTemplate(template)) {
    switch (part) {
      case TemplateText(:final text):
        out.write(text);
      case TemplateRef(:final reference):
        out.write(_resolveReference(reference, context));
    }
  }
  return out.toString();
}

bool _isTrue(String reference, LaunchContext context) =>
    _lookupValue(reference.split('.'), context.settings) == true;

bool _applies(LaunchEntry entry, LaunchContext context) =>
    (entry.when == null || _isTrue(entry.when!, context)) &&
    (entry.unless == null || !_isTrue(entry.unless!, context));

/// What an argument that holds a secret shows wherever it is logged or
/// reported.
const redactedSecret = '***';

/// One rendered launch argument. A plain argument is [prefix] alone. An
/// argument that holds a secret is [prefix], the value of the setting
/// [secretSetting], then [suffix]; the value is not known here, so the
/// argument can be recorded, logged and reported without it.
class LaunchArgument {
  const LaunchArgument(this.prefix, {this.secretSetting, this.suffix = ''});

  /// The whole text of a plain argument, or the text before the secret.
  final String prefix;

  /// The `secret` setting whose value goes between [prefix] and [suffix].
  final String? secretSetting;

  /// The text after the secret.
  final String suffix;

  /// The argument with the secret as `***`: safe to log and to report.
  String get redacted =>
      secretSetting == null ? prefix : '$prefix$redactedSecret$suffix';

  /// The argument as the server receives it. [secrets] maps setting names to
  /// values; throws [TemplateException] when the secret's value is missing.
  String resolve(Map<String, String> secrets) {
    final setting = secretSetting;
    if (setting == null) return prefix;
    final value = secrets[setting];
    if (value == null) {
      throw TemplateException('the secret "$setting" has no value');
    }
    return '$prefix$value$suffix';
  }
}

/// Renders one launch template. A `{{secrets.<setting>}}` reference becomes
/// the argument's secret slot, or null when the setting has no value.
LaunchArgument? _renderArgument(String template, LaunchContext context) {
  final prefix = StringBuffer();
  final suffix = StringBuffer();
  String? secret;
  for (final part in parseTemplate(template)) {
    switch (part) {
      case TemplateText(:final text):
        (secret == null ? prefix : suffix).write(text);
      case TemplateRef(:final segments)
          when segments.first == 'secrets':
        if (secret != null) {
          throw TemplateException(
            'template "$template" names more than one secret',
          );
        }
        secret = segments.elementAtOrNull(1) ?? '';
        if (!context.secretsSet.contains(secret)) return null;
      case TemplateRef(:final reference):
        (secret == null ? prefix : suffix).write(
          _resolveReference(reference, context),
        );
    }
  }
  return LaunchArgument(
    prefix.toString(),
    secretSetting: secret,
    suffix: suffix.toString(),
  );
}

/// Renders the manifest's launch templates into arguments. Every result is
/// one argv entry, so nothing is split or interpreted by a shell. An argument
/// that names a secret keeps it as a slot ([LaunchArgument.secretSetting]);
/// one whose secret has no value is left out.
List<LaunchArgument> renderLaunchArguments(
  PluginManifest manifest,
  LaunchContext context,
) {
  final args = <LaunchArgument>[];
  void render(List<LaunchEntry> entries) {
    for (final entry in entries) {
      if (!_applies(entry, context)) continue;
      switch (entry) {
        case LiteralEntry(:final template):
          if (_renderArgument(template, context) case final argument?) {
            args.add(argument);
          }
        case GroupEntry(:final entries):
          render(entries);
        case JoinEntry(:final list, :final separator, :final prefix):
          final segments = list.split('.');
          final items = segments.first == 'mods'
              ? context.mods[segments.elementAtOrNull(1)]
              : _lookupValue(segments, context.settings);
          if (items is List<Object?> && items.isNotEmpty) {
            args.add(LaunchArgument('$prefix${items.join(separator)}'));
          }
      }
    }
  }

  render(manifest.launchArgs);
  return args;
}

/// The launch arguments as strings, with every secret shown as `***`: the
/// form a daemon logs and reports. Use [renderLaunchArguments] to start a
/// process.
List<String> renderLaunchArgs(PluginManifest manifest, LaunchContext context) =>
    [
      for (final argument in renderLaunchArguments(manifest, context))
        argument.redacted,
    ];

/// Resolves a path that must stay inside [instanceRoot]: a relative path is
/// taken from the instance root, an absolute one must already be inside.
/// Returns the normalised native path, or null when it is outside, is the
/// instance root itself, or names a drive or root of another location.
///
/// Manifest paths are portable: `/` and `\` both separate segments.
String? resolveInstancePath(String path, String instanceRoot) {
  final root = p.normalize(instanceRoot);
  if (p.isAbsolute(path)) {
    final normalized = p.normalize(path);
    return p.isWithin(root, normalized) ? normalized : null;
  }
  if (p.windows.rootPrefix(path).isNotEmpty) return null;
  final segments = p.windows.split(p.windows.normalize(path));
  if (segments.isEmpty ||
      segments.first == '..' ||
      segments.first == '.' ||
      segments.any((s) => s.contains(':'))) {
    return null;
  }
  final resolved = p.joinAll([root, ...segments]);
  return p.isWithin(root, resolved) ? p.normalize(resolved) : null;
}

/// Renders the manifest's `data_paths` for an instance and resolves each one
/// inside the instance directory.
///
/// Throws [TemplateException] when a path resolves outside it.
List<String> resolveDataPaths(PluginManifest manifest, LaunchContext context) {
  final root = context.paths['instance']!;
  return [
    for (final template in manifest.dataPaths)
      resolveInstancePath(renderTemplate(template, context), root) ??
          (throw TemplateException(
            'data path "$template" resolves outside the instance directory',
          )),
  ];
}
