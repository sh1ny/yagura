import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../schema.dart';

/// What the form hands to its owner on a valid submit.
final class SettingsSubmission {
  const SettingsSubmission({
    required this.settings,
    required this.ports,
    required this.secrets,
  });

  /// Non-secret settings document.
  final Map<String, Object?> settings;

  /// Port number by port name.
  final Map<String, int> ports;

  /// Secret values the admin typed, by setting name (write-only).
  final Map<String, String> secrets;
}

/// Renders [schema] as a form: an input per type, nested groups for objects,
/// sections by `group`, an advanced section, the schema's constraints checked
/// on the client and the daemon's field errors shown on the fields.
///
/// [violations] maps JSON field paths (`ports.game`, `items[1].class`) to the
/// daemon's constraint descriptions. A null [schema] (or a field of an unknown
/// type) is shown read-only.
class SettingsForm extends StatefulWidget {
  const SettingsForm({
    super.key,
    required this.schema,
    required this.values,
    required this.ports,
    required this.onSubmit,
    this.violations = const {},
  });

  final SettingsSchema? schema;
  final Map<String, Object?> values;
  final List<Port> ports;
  final Map<String, String> violations;
  final ValueChanged<SettingsSubmission> onSubmit;

  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, Object?> _values;
  late final Map<String, String> _portText;
  final Map<String, String> _secrets = {};

  /// Paths whose daemon error the admin has since edited away.
  final Set<String> _dismissed = {};
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _values = _deepCopy(widget.values);
    final schema = widget.schema;
    if (schema != null) _applyDefaults(schema.fields, _values);
    _portText = {for (final p in widget.ports) p.name: p.number.toString()};
  }

  @override
  void didUpdateWidget(SettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.violations, widget.violations)) {
      _dismissed.clear();
    }
  }

  String? _violation(String path) =>
      _dismissed.contains(path) ? null : widget.violations[path];

  void _edited(String path) {
    if (widget.violations.containsKey(path) && _dismissed.add(path)) {
      setState(() {});
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final schema = widget.schema!;
    final settings = _prune(schema.fields, _values);
    // Keep values of fields this client cannot edit exactly as they were.
    widget.onSubmit(
      SettingsSubmission(
        settings: settings,
        ports: {
          for (final MapEntry(:key, :value) in _portText.entries)
            key: ?int.tryParse(value),
        },
        secrets: Map.of(_secrets),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schema = widget.schema;
    if (schema == null) return _ReadOnlyValues(values: widget.values);
    final hasAdvanced = _hasAdvanced(schema.fields);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.ports.isNotEmpty) ..._portFields(context),
                ..._groups(context, schema.fields, '', _values),
                if (hasAdvanced)
                  SwitchListTile(
                    key: const ValueKey('form:advanced'),
                    title: const Text('Show advanced settings'),
                    value: _showAdvanced,
                    onChanged: (v) => setState(() => _showAdvanced = v),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const ValueKey('form:save'),
                    onPressed: _submit,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _portFields(BuildContext context) => [
    const _SectionHeader('Ports'),
    for (final port in widget.ports)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          key: ValueKey('field:ports.${port.name}'),
          initialValue: port.number.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: port.purpose.isEmpty
                ? '${port.name} port'
                : '${port.name} port (${port.purpose})',
            errorText: _violation('ports.${port.name}'),
          ),
          validator: (text) => switch (int.tryParse(text ?? '')) {
            final n? when n >= 1 && n <= 65535 => null,
            _ => 'Enter a port between 1 and 65535',
          },
          onChanged: (text) {
            _portText[port.name] = text;
            _edited('ports.${port.name}');
          },
        ),
      ),
  ];

  /// Fields grouped into sections, in the order the groups first appear.
  List<Widget> _groups(
    BuildContext context,
    List<SettingField> fields,
    String prefix,
    Map<String, Object?> container,
  ) {
    final visible = [
      for (final f in fields)
        if (!f.advanced || _showAdvanced) f,
    ];
    final byGroup = <String, List<SettingField>>{};
    for (final f in visible) {
      byGroup.putIfAbsent(f.group, () => []).add(f);
    }
    return [
      for (final MapEntry(:key, :value) in byGroup.entries) ...[
        if (key.isNotEmpty) _SectionHeader(key),
        for (final f in value)
          _field(
            context,
            f,
            prefix.isEmpty ? f.name : '$prefix.${f.name}',
            container,
          ),
      ],
    ];
  }

  Widget _field(
    BuildContext context,
    SettingField field,
    String path,
    Map<String, Object?> container,
  ) {
    final name = field.name;
    final label = field.required ? '${field.title} *' : field.title;
    InputDecoration decoration({String? helper}) => InputDecoration(
      labelText: label,
      helperText:
          helper ?? (field.description.isEmpty ? null : field.description),
      errorText: _violation(path),
    );
    Widget padded(Widget child) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: child);

    switch (field) {
      case StringField():
        return padded(
          TextFormField(
            key: ValueKey('field:$path'),
            initialValue: container[name]?.toString() ?? '',
            decoration: decoration(),
            validator: (text) => _validateString(field, text ?? ''),
            onChanged: (text) {
              container[name] = text.isEmpty ? null : text;
              _edited(path);
            },
          ),
        );
      case IntegerField():
        return padded(
          TextFormField(
            key: ValueKey('field:$path'),
            initialValue: container[name]?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: decoration(),
            validator: (text) => _validateNumber(
              text ?? '',
              required: field.required,
              min: field.min,
              max: field.max,
              parse: int.tryParse,
              invalid: 'Enter a whole number',
            ),
            onChanged: (text) {
              container[name] = int.tryParse(text);
              _edited(path);
            },
          ),
        );
      case NumberField():
        return padded(
          TextFormField(
            key: ValueKey('field:$path'),
            initialValue: container[name]?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: decoration(),
            validator: (text) => _validateNumber(
              text ?? '',
              required: field.required,
              min: field.min,
              max: field.max,
              parse: double.tryParse,
              invalid: 'Enter a number',
            ),
            onChanged: (text) {
              container[name] = double.tryParse(text);
              _edited(path);
            },
          ),
        );
      case BooleanField():
        return SwitchListTile(
          key: ValueKey('field:$path'),
          contentPadding: EdgeInsets.zero,
          title: Text(field.title),
          subtitle: field.description.isEmpty ? null : Text(field.description),
          value: container[name] == true,
          onChanged: (v) {
            setState(() => container[name] = v);
            _edited(path);
          },
        );
      case EnumField():
        final current = container[name];
        return padded(
          DropdownButtonFormField<String>(
            key: ValueKey('field:$path'),
            initialValue: field.values.contains(current)
                ? current as String?
                : null,
            decoration: decoration(),
            items: [
              for (final v in field.values)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            validator: (v) =>
                field.required && v == null ? 'Choose a value' : null,
            onChanged: (v) {
              container[name] = v;
              _edited(path);
            },
          ),
        );
      case SecretField():
        final isSet = switch (container[name]) {
          {'set': true} => true,
          _ => false,
        };
        return padded(
          TextFormField(
            key: ValueKey('field:$path'),
            obscureText: true,
            decoration: decoration(
              helper: isSet
                  ? 'A value is set. Type to replace it (write-only).'
                  : 'Not set. Values are write-only.',
            ),
            onChanged: (text) {
              if (text.isEmpty) {
                _secrets.remove(name);
              } else {
                _secrets[name] = text;
              }
              _edited(path);
            },
          ),
        );
      case StringListField():
        final current = switch (container[name]) {
          final List<Object?> list => list.join('\n'),
          _ => '',
        };
        return padded(
          TextFormField(
            key: ValueKey('field:$path'),
            initialValue: current,
            minLines: 2,
            maxLines: 6,
            decoration: decoration(
              helper: _helper(field, 'One entry per line'),
            ),
            validator: (text) => _validateCount(
              _lines(text ?? '').length,
              required: field.required,
              min: field.min,
              max: field.max,
              noun: 'entries',
            ),
            onChanged: (text) {
              container[name] = _lines(text);
              _edited(path);
            },
          ),
        );
      case ObjectField():
        final child = _childMap(container, name);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (field.description.isNotEmpty) Text(field.description),
                ..._groups(context, field.fields, path, child),
              ],
            ),
          ),
        );
      case ListField():
        return _listField(context, field, path, container);
      case UnknownField():
        return _UnknownFieldView(
          key: ValueKey('readonly:$path'),
          field: field,
          value: container[name],
        );
    }
  }

  Widget _listField(
    BuildContext context,
    ListField field,
    String path,
    Map<String, Object?> container,
  ) {
    final name = field.name;
    final rows = switch (container[name]) {
      final List<Object?> list => list,
      _ => <Object?>[],
    };
    container[name] = rows;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final row = switch (rows[i]) {
        final Map<String, Object?> m => m,
        _ => <String, Object?>{},
      };
      rows[i] = row;
      final index = i;
      children.add(
        Card(
          key: ObjectKey(row),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: _groups(
                      context,
                      field.fields,
                      '$path[$index]',
                      row,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('list:remove:$path:$index'),
                  tooltip: 'Remove row',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => rows.removeAt(index)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return FormField<void>(
      key: ValueKey('field:$path'),
      validator: (_) => _validateCount(
        rows.length,
        required: field.required,
        min: field.min,
        max: field.max,
        noun: 'rows',
      ),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              field.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (field.description.isNotEmpty) Text(field.description),
          ...children,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('list:add:$path'),
              icon: const Icon(Icons.add),
              label: const Text('Add row'),
              onPressed: () => setState(() => rows.add(<String, Object?>{})),
            ),
          ),
          if (state.errorText ?? _violation(path) case final error?)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  String? _helper(SettingField field, String hint) =>
      field.description.isEmpty ? hint : '${field.description} ($hint)';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// A field of a type this client does not know: its raw value and a notice.
class _UnknownFieldView extends StatelessWidget {
  const _UnknownFieldView({
    super.key,
    required this.field,
    required this.value,
  });

  final UnknownField field;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.title, style: Theme.of(context).textTheme.titleSmall),
            Text(
              'Unknown field type "${field.type}": shown read-only, '
              'this client cannot edit it.',
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 4),
            Text(jsonEncode(value)),
          ],
        ),
      ),
    );
  }
}

/// Fallback when no usable schema is available.
class _ReadOnlyValues extends StatelessWidget {
  const _ReadOnlyValues({required this.values});

  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'The settings schema is not available: showing the current values '
        'read-only.',
      ),
      const SizedBox(height: 8),
      Text(
        const JsonEncoder.withIndent('  ').convert(values),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    ],
  );
}

String? _validateString(StringField field, String text) {
  if (text.isEmpty) return field.required ? 'Required' : null;
  final min = field.min;
  if (min != null && text.length < min) {
    return 'Must be at least $min characters';
  }
  final max = field.max;
  if (max != null && text.length > max) {
    return 'Must be at most $max characters';
  }
  if (field.pattern case final pattern?) {
    final RegExp regex;
    try {
      regex = RegExp(pattern);
    } on FormatException {
      return null;
    }
    if (!regex.hasMatch(text)) return 'Does not match the required format';
  }
  return null;
}

String? _validateNumber(
  String text, {
  required bool required,
  required num? min,
  required num? max,
  required num? Function(String) parse,
  required String invalid,
}) {
  if (text.trim().isEmpty) return required ? 'Required' : null;
  final value = parse(text.trim());
  if (value == null) return invalid;
  if (min != null && value < min) return 'Must be at least $min';
  if (max != null && value > max) return 'Must be at most $max';
  return null;
}

String? _validateCount(
  int count, {
  required bool required,
  required int? min,
  required int? max,
  required String noun,
}) {
  if (count == 0 && required) return 'Required';
  if (min != null && count < min) return 'At least $min $noun';
  if (max != null && count > max) return 'At most $max $noun';
  return null;
}

List<String> _lines(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

bool _hasAdvanced(List<SettingField> fields) => fields.any(
  (f) =>
      f.advanced ||
      switch (f) {
        ObjectField(:final fields) ||
        ListField(:final fields) => _hasAdvanced(fields),
        _ => false,
      },
);

Map<String, Object?> _childMap(Map<String, Object?> container, String name) {
  final existing = container[name];
  if (existing is Map<String, Object?>) return existing;
  return container[name] = <String, Object?>{};
}

Map<String, Object?> _deepCopy(Map<String, Object?> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, Object?>;

/// Fills missing values with the schema's defaults.
void _applyDefaults(List<SettingField> fields, Map<String, Object?> values) {
  for (final f in fields) {
    switch (f) {
      case ObjectField(:final fields):
        if (values[f.name] case final Map<String, Object?> child) {
          _applyDefaults(fields, child);
        }
      case ListField(:final fields):
        if (values[f.name] case final List<Object?> rows) {
          for (final row in rows) {
            if (row is Map<String, Object?>) _applyDefaults(fields, row);
          }
        }
      default:
        if (values[f.name] == null && f.defaultValue != null) {
          values[f.name] = f.defaultValue;
        }
    }
  }
}

/// The document to send: secrets and unset values left out, everything this
/// client has no field for (unknown types, extra keys) kept as it was.
Map<String, Object?> _prune(
  List<SettingField> fields,
  Map<String, Object?> values,
) {
  final result = <String, Object?>{};
  final known = {for (final f in fields) f.name: f};
  for (final MapEntry(:key, :value) in values.entries) {
    final field = known[key];
    final Object? pruned = switch (field) {
      SecretField() => null,
      ObjectField(:final fields) when value is Map<String, Object?> => _prune(
        fields,
        value,
      ),
      ListField(:final fields) when value is List<Object?> => [
        for (final row in value)
          if (row is Map<String, Object?>) _prune(fields, row) else row,
      ],
      _ => value,
    };
    final empty = switch (pruned) {
      null => true,
      Map<String, Object?>(isEmpty: true) => true,
      List<Object?>(isEmpty: true) => field is! UnknownField,
      _ => false,
    };
    if (!empty) result[key] = pruned;
  }
  return result;
}
