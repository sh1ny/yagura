import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../errors.dart';
import '../files/files.dart';
import '../host/database.dart';
import 'mod_entry.dart';

/// The most files one key rule may match in one mod (design D8).
const maxKeyFilesPerRule = 1024;

/// Key files are small; a larger match is not a key.
const _maxKeyBytes = 1024 * 1024;

/// A mod whose content may provide key files.
class KeySource {
  const KeySource(this.mod, this.directory);

  final ModEntry mod;

  /// The mod's version directory in the content store, read directly (never
  /// through the instance's link).
  final String directory;
}

/// A regular expression for the glob [pattern] over `/`-separated relative
/// paths: `**/` any directories (also none), `*` within a name, `?` one
/// character. Names compare case-insensitively, as on Windows.
RegExp globToRegExp(String pattern) {
  final out = StringBuffer('^');
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    if (c == '*') {
      if (pattern.startsWith('**/', i)) {
        out.write('(?:.*/)?');
        i += 3;
        continue;
      }
      if (pattern.startsWith('**', i)) {
        out.write('.*');
        i += 2;
        continue;
      }
      out.write('[^/]*');
    } else if (c == '?') {
      out.write('[^/]');
    } else {
      out.write(RegExp.escape(c));
    }
    i++;
  }
  out.write(r'$');
  return RegExp(out.toString(), caseSensitive: false);
}

/// Places the key files of staged mods (design D8). A key file is owned by the
/// mods that provide it and never replaces an admin's file with other content.
class KeyPlacer {
  KeyPlacer(this._database);

  final YaguraDatabase _database;

  /// Applies the key rules of [spec] for the staged [sources] of [instanceId]
  /// and returns the `key_conflict:<file>` warnings by mod key.
  Map<String, List<String>> place({
    required InstanceFs fs,
    required String instanceId,
    required ModsSpec spec,
    required List<KeySource> sources,
  }) {
    // target -> providers in load order, each with the file to copy.
    final candidates = <String, List<({KeySource source, String file})>>{};
    for (final rule in spec.keys) {
      final pattern = globToRegExp(rule.from);
      for (final source in sources) {
        final matches = _matches(source.directory, pattern, rule.from);
        for (final file in matches) {
          final target = p.posix.join(
            rule.to,
            p.basename(file).replaceAll('\\', '/'),
          );
          candidates.putIfAbsent(target, () => []).add((
            source: source,
            file: file,
          ));
        }
      }
    }

    final rows = _rows(instanceId);
    final warnings = <String, Set<String>>{};
    for (final MapEntry(key: target, value: providers) in candidates.entries) {
      final first = providers.first;
      final bytes = File(first.file).readAsBytesSync();
      final hash = sha256.convert(bytes).toString();
      final names = <String>{for (final c in providers) c.source.mod.key};
      final existing = _existing(fs, target);
      final row = rows[target];
      if (existing == null) {
        _write(fs, target, bytes);
        _save(instanceId, target, hash, names);
        continue;
      }
      final onDisk = existing.hash;
      final ours = row != null && (onDisk == row.hash || onDisk == hash);
      final identical = onDisk == hash;
      if (identical || ours) {
        // Ours already, or the same content: adopt it.
        if (!identical) _write(fs, target, bytes);
        _save(instanceId, target, hash, names);
        continue;
      }
      // Another file with this name: left as it is, and said so.
      for (final provider in providers) {
        warnings
            .putIfAbsent(provider.source.mod.key, () => {})
            .add('key_conflict:${p.posix.basename(target)}');
      }
    }

    // Keys nobody provides any more go; a file changed since is left.
    for (final MapEntry(key: target, value: row) in rows.entries) {
      if (candidates.containsKey(target)) continue;
      final existing = _existing(fs, target);
      if (existing != null && existing.hash == row.hash) fs.delete(target);
      _delete(instanceId, target);
    }
    return {
      for (final MapEntry(:key, :value) in warnings.entries)
        key: value.toList()..sort(),
    };
  }

  /// The files of [directory] matching [pattern], relative and `/`-separated.
  /// More than [maxKeyFilesPerRule] fail `key_rule_too_broad`.
  List<String> _matches(String directory, RegExp pattern, String rule) {
    final root = Directory(directory);
    if (!root.existsSync()) return const [];
    final out = <String>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: directory)
          .replaceAll('\\', '/');
      if (!pattern.hasMatch(relative)) continue;
      if (out.length >= maxKeyFilesPerRule) {
        throw YaguraException(
          'key_rule_too_broad',
          'the key rule "$rule" matches more than $maxKeyFilesPerRule files '
              'in $directory; narrow its pattern',
          details: {'rule': rule, 'limit': maxKeyFilesPerRule},
        );
      }
      out.add(entity.path);
    }
    return out;
  }

  /// The file at [target] and the SHA-256 of its content, or null when
  /// nothing is there. A directory or link, or a file too large to be a key,
  /// has an empty hash, which no key has.
  ({String hash})? _existing(InstanceFs fs, String target) {
    final entry = fs.stat(target);
    if (entry == null) return null;
    if (entry.isDirectory || entry.isLink) return (hash: '');
    try {
      return (
        hash: sha256
            .convert(fs.readBytes(target, maxBytes: _maxKeyBytes))
            .toString(),
      );
    } on YaguraException {
      return (hash: '');
    }
  }

  void _write(InstanceFs fs, String target, List<int> bytes) {
    fs.createDirectory(p.posix.dirname(target));
    fs.writeAtomic(target, bytes);
  }

  Map<String, ({String hash, List<String> providers})> _rows(
    String instanceId,
  ) => {
    for (final row in _database.sqlite.select(
      'SELECT file_name, content_hash, providers_json FROM placed_keys '
      'WHERE instance_id = ?',
      [instanceId],
    ))
      row['file_name']! as String: (
        hash: row['content_hash']! as String,
        providers: [
          for (final v in jsonDecode(row['providers_json']! as String) as List)
            v as String,
        ],
      ),
  };

  void _save(
    String instanceId,
    String target,
    String hash,
    Set<String> providers,
  ) => _database.sqlite.execute(
    'INSERT INTO placed_keys (instance_id, file_name, content_hash, '
    'providers_json) VALUES (?, ?, ?, ?) ON CONFLICT (instance_id, file_name) '
    'DO UPDATE SET content_hash = excluded.content_hash, '
    'providers_json = excluded.providers_json',
    [instanceId, target, hash, jsonEncode(providers.toList())],
  );

  void _delete(String instanceId, String target) => _database.sqlite.execute(
    'DELETE FROM placed_keys WHERE instance_id = ? AND file_name = ?',
    [instanceId, target],
  );
}
