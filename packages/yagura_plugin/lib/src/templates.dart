import 'package:path/path.dart' as p;

import 'manifest.dart';

/// The values a launch template renders against.
class LaunchContext {
  const LaunchContext({
    required this.settings,
    required this.ports,
    required this.paths,
    required this.os,
  });

  /// Validated setting values (defaults applied), see `validateSettings`.
  final Map<String, Object?> settings;

  /// Resolved port numbers by port name, see `resolvePorts`.
  final Map<String, int> ports;

  /// Directories by name: `instance` and `server`.
  final Map<String, String> paths;

  /// `windows` or `linux`.
  final String os;
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
  });

  final Map<String, SettingDef> settings;
  final Set<String> ports;
  final bool allowSettings;
  final bool allowPorts;
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
      return switch (expected) {
        'boolean' => '$reference is a ${def.type.wireName}, not a boolean',
        'list' => '$reference is a ${def.type.wireName}, not a string_list',
        _ =>
          '$reference is a ${def.type.wireName} and cannot be written '
              'into a string${def.type == SettingType.stringList ? '; use join' : ''}',
      };
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
          '(known: settings, ports, paths, os, instance)';
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

/// Renders the manifest's launch templates into an argument list. Every
/// result is one argv entry, so nothing is split or interpreted by a shell.
List<String> renderLaunchArgs(PluginManifest manifest, LaunchContext context) {
  final args = <String>[];
  void render(List<LaunchEntry> entries) {
    for (final entry in entries) {
      if (!_applies(entry, context)) continue;
      switch (entry) {
        case LiteralEntry(:final template):
          args.add(renderTemplate(template, context));
        case GroupEntry(:final entries):
          render(entries);
        case JoinEntry(:final list, :final separator, :final prefix):
          final items = _lookupValue(list.split('.'), context.settings);
          if (items is List<Object?> && items.isNotEmpty) {
            args.add('$prefix${items.join(separator)}');
          }
      }
    }
  }

  render(manifest.launchArgs);
  return args;
}

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
