/// The plugin settings schema (docs/plugins/manifest.md, `settings`) as the
/// daemon serves it in `PluginDetail.settings_schema`: a JSON object from
/// setting name to definition.
library;

import 'dart:convert';

sealed class SettingField {
  const SettingField({
    required this.name,
    this.label = '',
    this.description = '',
    this.required = false,
    this.group = '',
    this.advanced = false,
    this.defaultValue,
  });

  final String name;
  final String label;
  final String description;
  final bool required;
  final String group;
  final bool advanced;
  final Object? defaultValue;

  String get title => label.isEmpty ? name : label;
}

final class StringField extends SettingField {
  const StringField({
    required super.name,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
    super.defaultValue,
    this.min,
    this.max,
    this.pattern,
  });

  final int? min;
  final int? max;
  final String? pattern;
}

final class IntegerField extends SettingField {
  const IntegerField({
    required super.name,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
    super.defaultValue,
    this.min,
    this.max,
  });

  final num? min;
  final num? max;
}

final class NumberField extends SettingField {
  const NumberField({
    required super.name,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
    super.defaultValue,
    this.min,
    this.max,
  });

  final num? min;
  final num? max;
}

final class BooleanField extends SettingField {
  const BooleanField({
    required super.name,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
    super.defaultValue,
  });
}

final class EnumField extends SettingField {
  const EnumField({
    required super.name,
    required this.values,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
    super.defaultValue,
  });

  final List<String> values;
}

/// Write-only; never read back from the daemon.
final class SecretField extends SettingField {
  const SecretField({
    required super.name,
    super.label,
    super.description,
    super.group,
    super.advanced,
  });
}

final class StringListField extends SettingField {
  const StringListField({
    required super.name,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
    super.defaultValue,
    this.min,
    this.max,
  });

  final int? min;
  final int? max;
}

final class ObjectField extends SettingField {
  const ObjectField({
    required super.name,
    required this.fields,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
  });

  final List<SettingField> fields;
}

/// An ordered array of rows, each an object with [fields].
final class ListField extends SettingField {
  const ListField({
    required super.name,
    required this.fields,
    super.label,
    super.description,
    super.required,
    super.group,
    super.advanced,
    this.min,
    this.max,
  });

  final List<SettingField> fields;
  final int? min;
  final int? max;
}

/// A type this client does not know: shown read-only with its raw value.
final class UnknownField extends SettingField {
  const UnknownField({
    required super.name,
    required this.type,
    super.label,
    super.description,
    super.group,
    super.advanced,
  });

  final String type;
}

final class SettingsSchema {
  const SettingsSchema(this.fields);

  final List<SettingField> fields;

  /// Parses the schema document; null when it is not a JSON object of
  /// definitions, in which case the form falls back to read-only.
  static SettingsSchema? tryParse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    return switch (decoded) {
      Map<String, Object?>() => SettingsSchema(_parseFields(decoded)),
      _ => null,
    };
  }
}

List<SettingField> _parseFields(Map<String, Object?> definitions) => [
  for (final MapEntry(:key, :value) in definitions.entries)
    _parseField(key, value),
];

SettingField _parseField(String name, Object? definition) {
  final Map<String, Object?> d = switch (definition) {
    Map<String, Object?>() => definition,
    _ => const {},
  };
  final type = d['type'] is String ? d['type']! as String : '';
  final label = d['label'] is String ? d['label']! as String : '';
  final description = d['description'] is String
      ? d['description']! as String
      : '';
  final group = d['group'] is String ? d['group']! as String : '';
  final required = d['required'] == true;
  final advanced = d['advanced'] == true;
  final defaultValue = d['default'];
  final min = d['min'] is num ? d['min']! as num : null;
  final max = d['max'] is num ? d['max']! as num : null;
  List<SettingField> nested() => switch (d['fields']) {
    Map<String, Object?>(:final entries) => [
      for (final MapEntry(:key, :value) in entries) _parseField(key, value),
    ],
    _ => const [],
  };

  return switch (type) {
    'string' => StringField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      defaultValue: defaultValue,
      min: min?.toInt(),
      max: max?.toInt(),
      pattern: d['pattern'] is String ? d['pattern']! as String : null,
    ),
    'integer' => IntegerField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      defaultValue: defaultValue,
      min: min,
      max: max,
    ),
    'number' => NumberField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      defaultValue: defaultValue,
      min: min,
      max: max,
    ),
    'boolean' => BooleanField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      defaultValue: defaultValue,
    ),
    'enum' => EnumField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      defaultValue: defaultValue,
      values: [
        if (d['values'] case final List<Object?> values)
          for (final v in values)
            if (v is String) v,
      ],
    ),
    'secret' => SecretField(
      name: name,
      label: label,
      description: description,
      group: group,
      advanced: advanced,
    ),
    'string_list' => StringListField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      defaultValue: defaultValue,
      min: min?.toInt(),
      max: max?.toInt(),
    ),
    'object' => ObjectField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      fields: nested(),
    ),
    'list' => ListField(
      name: name,
      label: label,
      description: description,
      required: required,
      group: group,
      advanced: advanced,
      fields: nested(),
      min: min?.toInt(),
      max: max?.toInt(),
    ),
    _ => UnknownField(
      name: name,
      type: type,
      label: label,
      description: description,
      group: group,
      advanced: advanced,
    ),
  };
}
