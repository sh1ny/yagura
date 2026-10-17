import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'manifest.dart';

/// One problem found while validating setting values.
class SettingError {
  const SettingError(this.path, this.message, {this.code});

  /// Field path such as `itemStackOverrides[1].class`.
  final String path;
  final String message;

  /// Set when the daemon maps the problem to a specific reason, for example
  /// `secret_store_unavailable`.
  final String? code;

  @override
  String toString() => '$path: $message';
}

/// The outcome of validating setting values against the schema.
class SettingsValidation {
  const SettingsValidation(this.values, this.errors);

  /// The accepted values with defaults applied. Unset secrets and optional
  /// settings without a default are absent.
  final Map<String, Object?> values;
  final List<SettingError> errors;

  bool get isValid => errors.isEmpty;
}

const _unset = Object();

/// Validates [input] against the manifest's settings schema: types,
/// constraints, required fields and unknown keys, applying defaults.
SettingsValidation validateSettings(
  PluginManifest manifest,
  Map<String, Object?> input,
) {
  final errors = <SettingError>[];
  final values = _validateObject(manifest.settings, input, '', errors);
  return SettingsValidation(values, errors);
}

/// Validates one value (used for defaults at load); returns the errors.
List<SettingError> validateSettingValue(SettingDef def, Object? value) {
  final errors = <SettingError>[];
  _validateValue(def, value, '', errors);
  return errors;
}

String _child(String path, String name) => path.isEmpty ? name : '$path.$name';

Map<String, Object?> _validateObject(
  Map<String, SettingDef> fields,
  Map<String, Object?> input,
  String path,
  List<SettingError> errors,
) {
  final values = <String, Object?>{};
  for (final key in input.keys.where((k) => !fields.containsKey(k))) {
    errors.add(SettingError(_child(path, key), 'unknown setting'));
  }
  for (final MapEntry(key: name, value: def) in fields.entries) {
    final fieldPath = _child(path, name);
    final value = _validateValue(def, input[name], fieldPath, errors);
    if (!identical(value, _unset)) values[name] = value;
  }
  return values;
}

/// Returns the accepted value, or [_unset] when there is none to keep.
Object? _validateValue(
  SettingDef def,
  Object? value,
  String path,
  List<SettingError> errors,
) {
  if (def.type == SettingType.secret) {
    return _validateSecret(value, path, errors);
  }
  if (value == null) {
    // The default goes through the same checks as a supplied value, so the
    // defaults of an object's fields and of a list's rows are filled in.
    if (def.defaultValue != null) {
      return _validateValue(def, def.defaultValue, path, errors);
    }
    if (def.required) errors.add(SettingError(path, 'is required'));
    return _unset;
  }

  void fail(String message) => errors.add(SettingError(path, message));

  switch (def.type) {
    case SettingType.string:
      if (value is! String) return _wrongType(path, 'a string', errors);
      _checkRange(def, value.length, 'length', fail);
      if (def.pattern case final pattern?
          when !RegExp(pattern).hasMatch(value)) {
        fail('must match the pattern $pattern');
      }
    case SettingType.integer:
      if (value is! int) return _wrongType(path, 'an integer', errors);
      _checkRange(def, value, 'value', fail);
    case SettingType.number:
      if (value is! num) return _wrongType(path, 'a number', errors);
      _checkRange(def, value, 'value', fail);
    case SettingType.boolean:
      if (value is! bool) return _wrongType(path, 'a boolean', errors);
    case SettingType.enumeration:
      if (value is! String || !def.values.contains(value)) {
        fail('must be one of ${def.values.join(', ')}');
      }
    case SettingType.stringList:
      if (value is! List<Object?> || value.any((e) => e is! String)) {
        return _wrongType(path, 'a list of strings', errors);
      }
      _checkRange(def, value.length, 'item count', fail);
    case SettingType.object:
      if (value is! Map<String, Object?>) {
        return _wrongType(path, 'an object', errors);
      }
      return _validateObject(def.fields, value, path, errors);
    case SettingType.list:
      if (value is! List<Object?>) return _wrongType(path, 'a list', errors);
      _checkRange(def, value.length, 'row count', fail);
      return [
        for (final (i, row) in value.indexed)
          if (row is Map<String, Object?>)
            _validateObject(def.fields, row, '$path[$i]', errors)
          else
            _wrongType('$path[$i]', 'an object', errors),
      ];
    case SettingType.secret:
      break;
  }
  return value;
}

Object? _wrongType(String path, String expected, List<SettingError> errors) {
  errors.add(SettingError(path, 'must be $expected'));
  return _unset;
}

void _checkRange(
  SettingDef def,
  num measured,
  String what,
  void Function(String) fail,
) {
  if (def.min != null && measured < def.min!) {
    fail('$what must be at least ${def.min}');
  }
  if (def.max != null && measured > def.max!) {
    fail('$what must be at most ${def.max}');
  }
}

/// This version has no secret store: a value is refused, while an omitted key
/// or the `{"secret": true, "set": false}` placeholder leaves the field unset.
Object? _validateSecret(Object? value, String path, List<SettingError> errors) {
  final isPlaceholder =
      value is Map<String, Object?> &&
      value['secret'] == true &&
      value['set'] == false;
  if (value != null && !isPlaceholder) {
    errors.add(
      SettingError(
        path,
        'a secret value cannot be stored: there is no secret store',
        code: 'secret_store_unavailable',
      ),
    );
  }
  return _unset;
}

/// Canonical JSON of [value]: object keys sorted by code unit at every level,
/// no whitespace, array order kept, strings escaped by `dart:convert`.
String canonicalJson(Object? value) => jsonEncode(_sortKeys(value));

Object? _sortKeys(Object? value) => switch (value) {
  Map<String, Object?>() => {
    for (final key in value.keys.toList()..sort()) key: _sortKeys(value[key]),
  },
  List<Object?>() => [for (final e in value) _sortKeys(e)],
  _ => value,
};

/// The settings-schema version (design D5): the first 32 bits of the SHA-256
/// of the canonical JSON of the manifest's `settings` section, read
/// big-endian. Any change to the schema changes the version.
int schemaVersion(PluginManifest manifest) {
  final digest = sha256.convert(
    utf8.encode(canonicalJson(manifest.rawSettings)),
  );
  return ByteData.sublistView(
    Uint8List.fromList(digest.bytes),
    0,
    4,
  ).getUint32(0);
}

/// Resolves every declared port to a number: a [overrides] entry or the
/// default for a base port, and the resolved base plus the offset for a
/// derived port (derived ports cannot be overridden).
///
/// Throws [ArgumentError] for an unknown override or a number outside
/// 1-65535.
Map<String, int> resolvePorts(
  PluginManifest manifest,
  Map<String, int> overrides,
) {
  final known = manifest.ports.map((port) => port.name).toSet();
  for (final name in overrides.keys.where((n) => !known.contains(n))) {
    throw ArgumentError.value(name, 'overrides', 'unknown port');
  }
  final resolved = <String, int>{};
  for (final port in manifest.ports.where((port) => !port.isDerived)) {
    resolved[port.name] = overrides[port.name] ?? port.defaultNumber!;
  }
  for (final port in manifest.ports.where((port) => port.isDerived)) {
    final base = resolved[port.deriveFrom];
    if (base == null) {
      throw ArgumentError.value(
        port.deriveFrom,
        port.name,
        'unknown base port',
      );
    }
    resolved[port.name] = base + port.deriveOffset!;
  }
  for (final MapEntry(:key, :value) in resolved.entries) {
    if (value < 1 || value > 65535) {
      throw ArgumentError.value(value, key, 'port outside 1-65535');
    }
  }
  return {for (final port in manifest.ports) port.name: resolved[port.name]!};
}
