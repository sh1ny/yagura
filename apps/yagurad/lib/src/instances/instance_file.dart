import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import 'instance_store.dart';

/// The portable `instance.json` (ADR 0008): written after every committed
/// change, never with secret values, read only by import.
class InstanceFile {
  const InstanceFile._();

  static const formatVersion = 1;
  static const fileName = 'instance.json';

  /// The file's content for [record]. Secret settings appear as
  /// `{"secret": true}` whether or not [manifest] is known; stored settings
  /// never hold a value for one.
  static Map<String, Object?> content(
    InstanceRecord record,
    PluginManifest? manifest,
  ) => {
    'format_version': formatVersion,
    'name': record.name,
    'plugin': {'id': record.pluginId, 'version': record.pluginVersion},
    'settings': withSecretPlaceholders(
      manifest?.settings ?? const {},
      record.settings,
      const {'secret': true},
    ),
    'ports': [
      for (final port in record.ports)
        {
          'name': port.name,
          'number': port.number,
          'protocol': port.protocol.name,
          'purpose': port.purpose.name,
          'exposed': port.exposed,
        },
    ],
    'restart_policy': record.restartPolicy,
    'autostart': record.autostart,
  };

  /// Writes the file into the instance directory by atomic replace. Throws
  /// [FileSystemException] when that fails.
  static void write(InstanceRecord record, PluginManifest? manifest) {
    final target = p.join(record.directory, fileName);
    final temporary = File('$target.tmp');
    try {
      temporary.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(content(record, manifest))}\n',
        flush: true,
      );
      temporary.renameSync(target);
    } on FileSystemException {
      if (temporary.existsSync()) temporary.deleteSync();
      rethrow;
    }
  }
}

/// Copies [values] with every secret setting of [defs] replaced by
/// [placeholder], at any depth. Top-level secrets are always present.
Map<String, Object?> withSecretPlaceholders(
  Map<String, SettingDef> defs,
  Map<String, Object?> values,
  Map<String, Object?> placeholder,
) {
  final out = Map<String, Object?>.of(values);
  for (final MapEntry(key: name, value: def) in defs.entries) {
    switch (def.type) {
      case SettingType.secret:
        out[name] = Map<String, Object?>.of(placeholder);
      case SettingType.object:
        if (out[name] case final Map<String, Object?> nested) {
          out[name] = withSecretPlaceholders(def.fields, nested, placeholder);
        }
      case SettingType.list:
        if (out[name] case final List<Object?> rows) {
          out[name] = [
            for (final row in rows)
              if (row is Map<String, Object?>)
                withSecretPlaceholders(def.fields, row, placeholder)
              else
                row,
          ];
        }
      default:
        break;
    }
  }
  return out;
}
