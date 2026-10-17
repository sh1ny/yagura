import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'manifest.dart';
import 'manifest_schema.g.dart';
import 'plugin_result.dart';
import 'settings.dart';
import 'templates.dart';

/// Manifest versions this build can load.
const supportedManifestVersions = [1];

/// Largest accepted `plugin.yaml`, checked before parsing.
const maxManifestBytes = 256 * 1024;

/// Largest accepted `hooks.js`, checked before parsing.
const maxHooksBytes = 1024 * 1024;

/// Reason code for any manifest content problem that has no dedicated code
/// (schema violations, bad regexes, unknown template references, paths outside
/// the instance).
const invalidManifestCode = 'invalid_manifest';

/// Loads every subfolder of [pluginsDirectory] that contains a `plugin.yaml`,
/// ordered by folder name.
List<PluginResult> discoverPlugins(String pluginsDirectory) {
  final folders =
      Directory(pluginsDirectory)
          .listSync()
          .whereType<Directory>()
          .where((d) => File(p.join(d.path, 'plugin.yaml')).existsSync())
          .map((d) => d.path)
          .toList()
        ..sort((a, b) => p.basename(a).compareTo(p.basename(b)));
  return folders.map(loadPlugin).toList();
}

/// Loads and validates the plugin in [directory]: size limits, YAML syntax,
/// manifest version, the v1 JSON Schema, features unsupported in this
/// version, then cross-field checks (ports, templates, settings, health,
/// paths). Never throws for a bad plugin; the result carries the reasons.
PluginResult loadPlugin(String directory) {
  final folder = p.basename(p.normalize(directory));
  final manifestFile = File(p.join(directory, 'plugin.yaml'));
  final hooksFile = File(p.join(directory, 'hooks.js'));

  PluginResult rejected(
    List<PluginReason> reasons, [
    Map<String, Object?> json = const {},
  ]) {
    final executable = json['executable'];
    return PluginResult(
      id: json['id'] is String ? json['id']! as String : folder,
      status: PluginStatus.rejected,
      name: json['name'] is String ? json['name']! as String : null,
      version: json['version'] is String ? json['version']! as String : null,
      platforms: executable is Map<String, Object?>
          ? (executable.keys.toList()..sort())
          : const [],
      reasons: reasons,
    );
  }

  if (!manifestFile.existsSync()) {
    return rejected([
      const PluginReason(
        code: invalidManifestCode,
        path: 'plugin.yaml',
        message: 'plugin.yaml not found',
      ),
    ]);
  }

  // Size limits come before any parsing.
  final tooLarge = [
    if (manifestFile.lengthSync() > maxManifestBytes)
      const PluginReason(
        code: 'file_too_large',
        path: 'plugin.yaml',
        message: 'plugin.yaml exceeds the 256 KiB limit',
      ),
    if (hooksFile.existsSync() && hooksFile.lengthSync() > maxHooksBytes)
      const PluginReason(
        code: 'file_too_large',
        path: 'hooks.js',
        message: 'hooks.js exceeds the 1 MiB limit',
      ),
  ];
  if (tooLarge.isNotEmpty) return rejected(tooLarge);

  final YamlNode document;
  try {
    document = loadYamlNode(
      manifestFile.readAsStringSync(),
      sourceUrl: manifestFile.uri,
    );
  } on YamlException catch (e) {
    return rejected([
      PluginReason(
        code: invalidManifestCode,
        message: 'YAML syntax error: ${e.message}',
        line: e.span?.start.line == null ? null : e.span!.start.line + 1,
      ),
    ]);
  } on FormatException catch (e) {
    return rejected([
      PluginReason(
        code: invalidManifestCode,
        path: 'plugin.yaml',
        message: 'plugin.yaml is not valid UTF-8: ${e.message}',
      ),
    ]);
  }

  final json = _toPlain(document);
  if (json is! Map<String, Object?>) {
    return rejected([
      const PluginReason(
        code: invalidManifestCode,
        message: 'plugin.yaml must be a mapping of manifest fields',
        line: 1,
      ),
    ]);
  }

  final report = _Report(document);

  final version = json['manifest_version'];
  if (version != null && !supportedManifestVersions.contains(version)) {
    report.add(
      'unsupported_manifest_version',
      ['manifest_version'],
      'manifest_version $version is not supported; '
          'supported versions: $supportedManifestVersions',
    );
    return rejected(report.reasons, json);
  }

  _checkSchema(json, report);
  if (report.isNotEmpty) return rejected(report.reasons, json);

  _checkUnsupported(json, report);
  if (report.isNotEmpty) return rejected(report.reasons, json);

  final manifest = PluginManifest.fromJson(json);
  _checkSemantics(manifest, report);
  if (report.isNotEmpty) return rejected(report.reasons, json);

  return PluginResult(
    id: manifest.id,
    status: PluginStatus.loaded,
    name: manifest.name,
    version: manifest.version,
    platforms: manifest.platforms,
    manifest: manifest,
  );
}

Object? _toPlain(YamlNode node) => switch (node) {
  YamlMap() => <String, Object?>{
    for (final MapEntry(:key, :value) in node.nodes.entries)
      '${(key as YamlNode).value}': _toPlain(value),
  },
  YamlList() => [for (final e in node.nodes) _toPlain(e)],
  YamlScalar(:final value) => value,
  _ => null,
};

/// Collects reasons with display paths and line numbers taken from the YAML.
class _Report {
  _Report(this._root);

  final YamlNode _root;
  final reasons = <PluginReason>[];
  final _seen = <String>{};

  bool get isNotEmpty => reasons.isNotEmpty;

  void add(String code, List<Object> segments, String message) {
    final (display, node) = _locate(segments);
    if (!_seen.add('$display\n$message')) return;
    reasons.add(
      PluginReason(
        code: code,
        path: display.isEmpty ? null : display,
        message: message,
        line: node.span.start.line + 1,
      ),
    );
  }

  /// Walks [segments] through the YAML, returning the display path and the
  /// deepest node that exists (the line of a missing field is its parent's).
  (String, YamlNode) _locate(List<Object> segments) {
    var node = _root;
    final out = StringBuffer();
    for (final segment in segments) {
      if (segment is int) {
        out.write('[$segment]');
      } else {
        out.write(out.isEmpty ? segment : '.$segment');
      }
      final next = switch (node) {
        YamlMap(:final nodes) => nodes[segment],
        YamlList(:final nodes) when segment is int =>
          segment < nodes.length ? nodes[segment] : null,
        _ => null,
      };
      if (next != null) node = next;
    }
    return ('$out', node);
  }

  /// Converts a JSON pointer such as `/ports/0/protocol` to path segments.
  List<Object> segmentsOf(String pointer) {
    final out = <Object>[];
    var node = _root;
    for (final raw in pointer.split('/').skip(1)) {
      final name = raw.replaceAll('~1', '/').replaceAll('~0', '~');
      if (node is YamlList && int.tryParse(name) != null) {
        final index = int.parse(name);
        out.add(index);
        node = index < node.nodes.length ? node.nodes[index] : node;
      } else {
        out.add(name);
        if (node case YamlMap(:final nodes) when nodes[name] != null) {
          node = nodes[name]!;
        }
      }
    }
    return out;
  }
}

final JsonSchema _schema = JsonSchema.create(manifestSchemaV1);

void _checkSchema(Map<String, Object?> json, _Report report) {
  final schemaJson = jsonDecode(manifestSchemaV1) as Map<String, Object?>;
  for (final error in _schema.validate(json).errors) {
    final segments = report.segmentsOf(error.instancePath);
    final message = error.message;

    if (RegExp(r'^required prop missing: (\S+) from').firstMatch(message)
        case final match?) {
      // The validator reports a missing field twice; keep the copy that
      // points at the field.
      final name = match.group(1)!;
      if (error.instancePath.endsWith('/$name')) {
        report.add(
          invalidManifestCode,
          segments,
          'required field "$name" is missing',
        );
      }
      continue;
    }
    if (RegExp(r'^unallowed additional property (.+)$').firstMatch(message)
        case final match?) {
      report.add(invalidManifestCode, [
        ...segments,
        match.group(1)!,
      ], 'unknown field "${match.group(1)}"');
      continue;
    }
    if (error.schemaPath.endsWith('/allOf') ||
        error.schemaPath.endsWith('/oneOf')) {
      final refined = _refine(error.schemaPath, _at(json, segments), segments);
      if (refined.isNotEmpty) {
        for (final (path, text) in refined) {
          report.add(invalidManifestCode, path, text);
        }
        continue;
      }
    }
    report.add(
      invalidManifestCode,
      segments,
      _describe(
        message,
        error.schemaPath,
        schemaJson,
        error.instancePath,
        json,
      ),
    );
  }
}

Object? _at(Object? json, List<Object> segments) {
  var current = json;
  for (final segment in segments) {
    current = switch (current) {
      Map<String, Object?>() => current['$segment'],
      List<Object?>() when segment is int => current.elementAtOrNull(segment),
      _ => null,
    };
  }
  return current;
}

/// Targeted explanations for the schema's `if`/`then` and `oneOf` rules, whose
/// raw errors only point at the enclosing object.
List<(List<Object>, String)> _refine(
  String schemaPath,
  Object? instance,
  List<Object> segments,
) {
  if (instance is! Map<String, Object?>) return const [];
  switch (schemaPath) {
    case '/definitions/setting/allOf':
      final type = instance['type'];
      return [
        if (type == 'secret' && instance.containsKey('default'))
          ([...segments, 'default'], 'a secret setting cannot have a default'),
        if (type == 'enum' && !instance.containsKey('values'))
          (segments, 'an enum setting needs "values"'),
        if ((type == 'object' || type == 'list') &&
            !instance.containsKey('fields'))
          (segments, 'an $type setting needs "fields"'),
      ];
    case '/properties/health/allOf':
      final type = instance['type'];
      return [
        if (type == 'log_match')
          for (final key in ['log_match', 'source'])
            if (!instance.containsKey(key))
              ([...segments, key], 'is required for health type log_match'),
        if (type == 'port' && !instance.containsKey('port'))
          ([...segments, 'port'], 'is required for health type port'),
      ];
    case '/definitions/port/oneOf':
      return [(segments, 'declare exactly one of "default" or "derive"')];
    case '/definitions/launch_entry/oneOf':
      return [
        (
          segments,
          'must be a string, a group with "when" or "unless" and "args", '
              'or a "join" entry',
        ),
      ];
  }
  return const [];
}

/// Rewrites the validator's terse messages to name the allowed values and
/// limits.
String _describe(
  String message,
  String schemaPath,
  Map<String, Object?> schema,
  String instancePath,
  Map<String, Object?> json,
) {
  Object? node = schema;
  for (final key in schemaPath.split('/').skip(1)) {
    node = node is Map<String, Object?> ? node[key] : null;
  }
  // The error's schemaPath names the failing keyword's parent.
  final rule = node is Map<String, Object?> ? node : const <String, Object?>{};

  if (message.startsWith('enum violated') && rule['enum'] is List<Object?>) {
    final allowed = (rule['enum']! as List<Object?>).join(', ');
    return 'must be one of $allowed (got ${_valueAt(json, instancePath)})';
  }
  if (message.startsWith('maximum exceeded')) {
    return 'must be at most ${rule['maximum']} '
        '(got ${_valueAt(json, instancePath)})';
  }
  if (message.startsWith('minimum violated')) {
    return 'must be at least ${rule['minimum']} '
        '(got ${_valueAt(json, instancePath)})';
  }
  if (message.startsWith('minLength violated')) return 'must not be empty';
  if (message.startsWith('pattern violated')) {
    return 'does not match the pattern ${rule['pattern']} '
        '(got ${_valueAt(json, instancePath)})';
  }
  if (RegExp(r'^type: wanted \[(\w+)\]').firstMatch(message)
      case final match?) {
    final wanted = match.group(1)!;
    return 'must be ${wanted == 'integer' || wanted == 'array' ? 'an' : 'a'} '
        '$wanted (got ${_valueAt(json, instancePath)})';
  }
  return message;
}

Object? _valueAt(Map<String, Object?> json, String pointer) {
  Object? current = json;
  for (final raw in pointer.split('/').skip(1)) {
    final name = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    current = switch (current) {
      Map<String, Object?>() => current[name],
      List<Object?>() => current.elementAtOrNull(int.tryParse(name) ?? -1),
      _ => null,
    };
  }
  return current;
}

/// Sections and values the schema accepts but this version refuses.
void _checkUnsupported(Map<String, Object?> json, _Report report) {
  const code = 'unsupported_in_this_version';
  for (final section in ['bindings', 'mods', 'rcon']) {
    if (json.containsKey(section)) {
      report.add(code, [
        section,
      ], 'the "$section" section is not supported in this version');
    }
  }
  if ((json['stop'] as Map<String, Object?>?)?['strategy'] == 'rcon') {
    report.add(code, [
      'stop',
      'strategy',
    ], 'stop strategy "rcon" is not supported in this version');
  }
  if ((json['health'] as Map<String, Object?>?)?['type'] == 'query') {
    report.add(code, [
      'health',
      'type',
    ], 'health type "query" is not supported in this version');
  }
}

/// A placeholder instance and server directory, to check containment at load.
final _placeholderContext = LaunchContext(
  settings: const {},
  ports: const {},
  paths: {
    'instance': p.join(p.current, '__yagura_instance__'),
    'server': p.join(p.current, '__yagura_server__'),
  },
  os: 'linux',
);

/// Cross-field checks that JSON Schema cannot express.
void _checkSemantics(PluginManifest manifest, _Report report) {
  const code = invalidManifestCode;
  final portNames = <String>{};
  final basePorts = {
    for (final port in manifest.ports.where((port) => !port.isDerived))
      port.name: port,
  };

  for (final (i, port) in manifest.ports.indexed) {
    if (!portNames.add(port.name)) {
      report.add(code, [
        'ports',
        i,
        'name',
      ], 'port name "${port.name}" is declared twice');
    }
    if (port.isDerived) {
      final base = basePorts[port.deriveFrom];
      if (base == null) {
        report.add(
          code,
          ['ports', i, 'derive', 'from'],
          'derived port "${port.name}" is based on "${port.deriveFrom}", '
          'which is not a declared port with a default number',
        );
      } else if (base.defaultNumber! + port.deriveOffset! case final n
          when n < 1 || n > 65535) {
        report.add(code, [
          'ports',
          i,
          'derive',
          'offset',
        ], 'derives port $n, outside 1-65535');
      }
    }
  }

  for (final MapEntry(key: name, value: def) in manifest.settings.entries) {
    _checkSetting(def, ['settings', name], report);
  }

  final scope = TemplateScope(settings: manifest.settings, ports: portNames);
  _checkLaunch(manifest.launchArgs, ['launch', 'args'], scope, report);

  final health = manifest.health;
  if (health.type == HealthType.logMatch) {
    try {
      RegExp(health.logMatch!);
    } on FormatException catch (e) {
      report.add(code, [
        'health',
        'log_match',
      ], 'invalid regular expression "${health.logMatch}": ${e.message}');
    }
    if (!manifest.logs.any((l) => l.name == health.source)) {
      report.add(code, [
        'health',
        'source',
      ], 'health.source "${health.source}" is not a declared log source');
    }
  }
  if (health.type == HealthType.port && !portNames.contains(health.port)) {
    report.add(code, [
      'health',
      'port',
    ], 'health.port "${health.port}" is not a declared port');
  }

  final logNames = <String>{};
  for (final (i, log) in manifest.logs.indexed) {
    if (!logNames.add(log.name)) {
      report.add(code, [
        'logs',
        i,
        'name',
      ], 'log source "${log.name}" is declared twice');
    }
    if (log.path case final path?) {
      _checkInstancePath(path, ['logs', i, 'path'], 'log path', report);
    }
  }
  for (final (i, path) in manifest.dataPaths.indexed) {
    _checkInstancePath(path, ['data_paths', i], 'data path', report);
  }
}

/// Whether every pattern in [def] and its fields compiles. A default is only
/// validated when they all do, since validating it compiles the patterns.
bool _checkSetting(SettingDef def, List<Object> path, _Report report) {
  var patternsOk = true;
  if (def.pattern case final pattern?) {
    try {
      RegExp(pattern);
    } on FormatException catch (e) {
      patternsOk = false;
      report.add(invalidManifestCode, [
        ...path,
        'pattern',
      ], 'invalid regular expression "$pattern": ${e.message}');
    }
  }
  for (final MapEntry(key: name, value: field) in def.fields.entries) {
    if (!_checkSetting(field, [...path, 'fields', name], report)) {
      patternsOk = false;
    }
  }
  if (patternsOk && def.defaultValue != null) {
    for (final error in validateSettingValue(def, def.defaultValue)) {
      report.add(
        invalidManifestCode,
        [...path, 'default'],
        'the default ${error.path.isEmpty ? '' : '(${error.path}) '}${error.message}',
      );
    }
  }
  return patternsOk;
}

void _checkLaunch(
  List<LaunchEntry> entries,
  List<Object> path,
  TemplateScope scope,
  _Report report,
) {
  for (final (i, entry) in entries.indexed) {
    final here = [...path, i];
    for (final (key, reference) in [
      ('when', entry.when),
      ('unless', entry.unless),
    ]) {
      if (reference == null) continue;
      final problem = checkReference(reference, scope, expected: 'boolean');
      if (problem != null) {
        report.add(invalidManifestCode, [
          ...here,
          key,
        ], '$key "$reference": $problem');
      }
    }
    switch (entry) {
      case LiteralEntry(:final template):
        for (final problem in checkTemplate(template, scope)) {
          report.add(invalidManifestCode, here, problem);
        }
      case GroupEntry(:final entries):
        _checkLaunch(entries, [...here, 'args'], scope, report);
      case JoinEntry(:final list):
        final problem = checkReference(list, scope, expected: 'list');
        if (problem != null) {
          report.add(invalidManifestCode, [
            ...here,
            'join',
            'list',
          ], 'join list "$list": $problem');
        }
    }
  }
}

void _checkInstancePath(
  String template,
  List<Object> path,
  String label,
  _Report report,
) {
  const scope = TemplateScope(
    settings: {},
    ports: {},
    allowSettings: false,
    allowPorts: false,
  );
  final problems = checkTemplate(template, scope);
  for (final problem in problems) {
    report.add(invalidManifestCode, path, problem);
  }
  if (problems.isNotEmpty) return;
  final rendered = renderTemplate(template, _placeholderContext);
  if (resolveInstancePath(rendered, _placeholderContext.paths['instance']!) ==
      null) {
    report.add(
      invalidManifestCode,
      path,
      '$label "$template" resolves outside the instance directory',
    );
  }
}
