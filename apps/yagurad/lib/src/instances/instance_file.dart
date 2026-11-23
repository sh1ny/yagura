import 'dart:convert';
import 'dart:io';

import 'package:yagura_plugin/yagura_plugin.dart';

import '../files/instance_fs.dart';
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
    'mods': [
      for (final mod in record.listedMods)
        {
          'source': mod.source,
          'item_id': mod.itemId,
          'role': mod.role,
          'staged_name': mod.stagedName,
        },
    ],
  };

  /// Writes the file into the instance directory by atomic replace. Throws
  /// [FileSystemException] when that fails and a `sandbox_violation`
  /// `YaguraException` when a link is in the way.
  static void write(InstanceRecord record, PluginManifest? manifest) {
    InstanceFs(record.directory).writeAtomic(
      fileName,
      utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(content(record, manifest))}\n',
      ),
    );
  }
}

/// Copies [values] with every secret setting of [defs] replaced by
/// [placeholder]. Secrets are top-level settings only (the manifest loader
/// rejects one inside an `object` or `list`), and are always present. A
/// placeholder with a `set` entry gets `set: true` for the keys in
/// [setSecrets].
Map<String, Object?> withSecretPlaceholders(
  Map<String, SettingDef> defs,
  Map<String, Object?> values,
  Map<String, Object?> placeholder, {
  Set<String> setSecrets = const {},
}) {
  final out = Map<String, Object?>.of(values);
  for (final MapEntry(key: name, value: def) in defs.entries) {
    if (def.type != SettingType.secret) continue;
    out[name] = {
      ...placeholder,
      if (placeholder.containsKey('set')) 'set': setSecrets.contains(name),
    };
  }
  return out;
}
