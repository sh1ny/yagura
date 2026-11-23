import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yagura_formats/yagura_formats.dart';

import '../errors.dart';
import '../files/confined_fs.dart';
import 'bound_file_store.dart';

/// A byte order mark as decoded text.
const _bomChar = '﻿';

/// The formats a binding or a hook file edit may name in this version.
const supportedFormats = ['json', 'ini', 'dayz-cfg', 'kv'];

/// Fails `unsupported_in_this_version` unless [format] is one of
/// [supportedFormats]; [path] names the file in the message.
void checkFormat(String path, String format) {
  if (supportedFormats.contains(format)) return;
  throw YaguraException(
    'unsupported_in_this_version',
    'file edit "$path" has format "$format"; only '
        '${supportedFormats.join(', ')} are supported in this version',
    details: {'path': path, 'format': format},
  );
}

/// One file edit returned by a hook: for `json` an RFC 7386 merge patch, for
/// the other formats a map from key path to value (`null` removes the key).
class FileEdit {
  const FileEdit({
    required this.path,
    required this.format,
    required this.patch,
  });

  /// Path relative to the instance root.
  final String path;
  final String format;

  /// The patch as plain JSON data.
  final Object? patch;
}

/// One manifest binding resolved for an instance: write [value] of the
/// setting [setting] to the key [key] of [file].
class BoundKey {
  const BoundKey({
    required this.id,
    required this.file,
    required this.format,
    required this.key,
    required this.setting,
    required this.value,
    this.secret = false,
    this.create = false,
    this.template,
    this.gameWrites = false,
  });

  /// The binding's place in the manifest (`bindings[0]`), for messages.
  final String id;

  /// The resolved path relative to the instance root.
  final String file;
  final String format;
  final String key;
  final String setting;

  /// The value to write, read when the pass applies it (a secret is read from
  /// the secret store here and nowhere earlier). `null` writes nothing.
  final Object? Function() value;

  /// Whether the value is a secret: masked in events.
  final bool secret;

  /// Whether a missing file is created.
  final bool create;

  /// The content a created file starts from.
  final List<int> Function()? template;

  /// Whether the game rewrites the file itself.
  final bool gameWrites;
}

/// What one pass reports.
class ConfigPassResult {
  const ConfigPassResult({this.externalEdits = const []});

  /// One `external_edit: ...` line per bound key that was changed by hand
  /// since the last pass and has been overwritten (secrets masked).
  final List<String> externalEdits;
}

/// The only writer of instance configuration files (design D9).
///
/// A pass applies the bindings and the hook edits it is given, in order: every
/// file is read once, its hash compared with the last recorded one (a change is
/// a hand edit, reported for the bound keys the pass overwrites), the new
/// content computed in memory, and only the files whose bytes change written,
/// all or none, through a temporary file and an atomic rename. A file held by a
/// running process is retried every 250 ms for 5 s, then the pass fails
/// `file_locked` with everything rolled back. Every path goes through the
/// instance's [ConfinedFs].
class ConfigBinder {
  ConfigBinder(
    this.fs, {
    this.store,
    this.instanceId = '',
    void Function(String temporary, String target)? rename,
    Future<void> Function(Duration duration)? delay,
  }) : _rename = rename, // ignore: prefer_initializing_formals
       _delay = delay ?? Future<void>.delayed;

  /// Largest file a pass reads or produces.
  static const maxFileBytes = 16 * 1024 * 1024;

  /// How often and how long a locked file is retried.
  static const lockStep = Duration(milliseconds: 250);
  static const lockTimeout = Duration(seconds: 5);

  final ConfinedFs fs;

  /// Where hashes are kept; without it nothing is compared or recorded.
  final BoundFileStore? store;
  final String instanceId;
  final void Function(String temporary, String target)? _rename;
  final Future<void> Function(Duration duration) _delay;

  /// Applies [bindings] then [edits] in one pass.
  Future<ConfigPassResult> apply({
    List<BoundKey> bindings = const [],
    List<FileEdit> edits = const [],
  }) async {
    for (final edit in edits) {
      checkFormat(edit.path, edit.format);
    }
    for (final binding in bindings) {
      checkFormat(binding.file, binding.format);
    }
    final files = <String, _File>{};
    _File fileFor(String path, String format) {
      final target = fs.parse(path).toString();
      final key = Platform.isWindows ? target.toLowerCase() : target;
      final file = files.putIfAbsent(key, () => _File(path, target, format));
      if (file.format != format) {
        throw YaguraException(
          'config_parse_error',
          'file "$path" is used as ${file.format} and as $format',
          details: {'path': path},
        );
      }
      return file;
    }

    for (final binding in bindings) {
      fileFor(binding.file, binding.format).bindings.add(binding);
    }
    for (final edit in edits) {
      fileFor(edit.path, edit.format).edits.add(edit);
    }
    if (files.isEmpty) return const ConfigPassResult();

    final known = store?.hashes(instanceId) ?? const <String, String>{};
    final events = <String>[];
    for (final file in files.values) {
      await _load(file);
      events.addAll(_externalEdits(file, known[file.target]));
      _modify(file);
    }

    final changed = [
      for (final file in files.values)
        if (file.changed) file,
    ];
    if (changed.isNotEmpty) await _commit(changed);
    store?.record(instanceId, {
      for (final file in files.values) file.target: file.finalHash,
    });
    return ConfigPassResult(externalEdits: events);
  }

  // ---- reading ---------------------------------------------------------------

  Future<void> _load(_File file) async {
    final entry = fs.stat(file.target);
    if (entry != null && entry.isDirectory) {
      throw YaguraException(
        'config_parse_error',
        'file "${file.path}" is a directory',
        details: {'path': file.path},
      );
    }
    var source = '';
    var addNewline = false;
    if (entry == null) {
      if (file.bindings.isNotEmpty) {
        final creating = file.bindings.where((b) => b.create);
        if (creating.isEmpty) {
          final first = file.bindings.first;
          throw YaguraException(
            'binding_file_missing',
            'file "${file.path}" bound by ${first.id} (setting '
                '"${first.setting}") does not exist and the binding does not '
                'create it',
            details: {'path': file.path, 'binding': first.id},
          );
        }
        final template = creating
            .map((b) => b.template)
            .whereType<List<int> Function()>()
            .firstOrNull;
        if (template != null) source = _decode(file, template());
      }
      // A new JSON file starts as an empty indented object.
      addNewline = file.format == 'json' && source.isEmpty;
      // Added keys then take the layout of an indented object.
      if (addNewline) source = '{\n  "k": 0\n}';
    } else {
      if (entry.size > maxFileBytes) throw _tooLarge(file);
      final bytes = await _locked(file, () {
        try {
          return fs.readBytes(file.target, maxBytes: maxFileBytes);
        } on YaguraException catch (e) {
          if (e.reason != 'file_too_large') rethrow;
          throw _tooLarge(file);
        }
      });
      file
        ..existed = true
        ..original = bytes
        ..originalHash = sha256.convert(bytes).toString();
      source = _decode(file, bytes);
    }
    file
      ..bom = source.startsWith(_bomChar)
      ..addNewline = addNewline;
    if (file.bom) source = source.substring(1);
    file.document = _parse(file, source);
    if (addNewline) file.document.patch({'k': null});
  }

  /// Text of [bytes]; a byte order mark is kept as [_bomChar].
  String _decode(_File file, List<int> bytes) {
    if (bytes.length > maxFileBytes) throw _tooLarge(file);
    final bom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    try {
      final text = utf8.decode(bom ? bytes.sublist(3) : bytes);
      return bom ? '$_bomChar$text' : text;
    } on FormatException {
      throw YaguraException(
        'config_parse_error',
        'file "${file.path}" is not valid UTF-8',
        details: {'path': file.path},
      );
    }
  }

  _Doc _parse(_File file, String source) {
    try {
      return switch (file.format) {
        'json' => _JsonDoc(JsonDocument.parse(source)),
        'ini' => _KeyDoc(IniDocument.parse(source), joinLists: true),
        'kv' => _KeyDoc(KvDocument.parse(source), joinLists: true),
        _ => _KeyDoc(DayzCfgDocument.parse(source), joinLists: false),
      };
    } on ConfigParseException catch (e) {
      throw YaguraException(
        'config_parse_error',
        'file "${file.path}" is not valid ${file.format}: ${e.message} '
            '(line ${e.line}, column ${e.column})',
        details: {'path': file.path, 'line': e.line, 'column': e.column},
      );
    } on FormatException catch (e) {
      throw YaguraException(
        'config_parse_error',
        'file "${file.path}" is not valid ${file.format}: ${e.message}',
        details: {'path': file.path},
      );
    }
  }

  YaguraException _tooLarge(_File file) => YaguraException(
    'file_too_large',
    'file edit "${file.path}" targets or produces a file over the 16 MiB limit',
    details: {'path': file.path},
  );

  // ---- hand edits ------------------------------------------------------------

  /// The bound keys of [file] that were changed by hand since the pass that
  /// wrote [recorded] and that this pass overwrites.
  List<String> _externalEdits(_File file, String? recorded) {
    if (!file.existed ||
        recorded == null ||
        recorded.isEmpty ||
        recorded == file.originalHash ||
        file.bindings.any((b) => b.gameWrites)) {
      return const [];
    }
    final events = <String>[];
    for (final binding in file.bindings) {
      final wanted = file.valueOf(binding);
      if (wanted == null) continue;
      final current = file.document.get(binding.key);
      if (current == null || _same(current, wanted)) continue;
      final was = binding.secret ? '***' : '$current';
      final now = binding.secret ? '***' : '$wanted';
      events.add(
        'external_edit: ${file.path} ${binding.key} was changed by hand to '
        '"$was"; it is set to "$now"',
      );
    }
    return events;
  }

  static bool _same(Object current, Object wanted) =>
      '$current' == '$wanted' ||
      (current is List &&
          wanted is List &&
          current.join(',') == wanted.join(','));

  // ---- computing -------------------------------------------------------------

  /// Applies the bindings, then the hook edits, to the document of [file] and
  /// renders it.
  void _modify(_File file) {
    try {
      for (final binding in file.bindings) {
        final value = file.valueOf(binding);
        if (value != null) file.document.set(binding.key, value);
      }
      for (final edit in file.edits) {
        file.document.patch(edit.patch);
      }
    } on ArgumentError catch (e) {
      throw YaguraException(
        'config_parse_error',
        'cannot edit "${file.path}": ${e.message}',
        details: {'path': file.path},
      );
    }
    final source = file.document.toSource();
    final text =
        '${file.bom ? _bomChar : ''}$source${file.addNewline ? '\n' : ''}';
    final bytes = utf8.encode(text);
    if (bytes.length > maxFileBytes) throw _tooLarge(file);
    file.content = bytes;
    file.changed =
        !file.existed || !_sameBytes(bytes, file.original ?? const []);
    file.finalHash = file.changed
        ? sha256.convert(bytes).toString()
        : file.originalHash;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- writing ---------------------------------------------------------------

  void _move(String temporary, String target) {
    if (_rename case final rename?) {
      rename(temporary, target);
    } else {
      fs.rename(temporary, target);
    }
  }

  /// Temporary files, then renames, restoring on failure.
  Future<void> _commit(List<_File> planned) async {
    final temporaries = <_File, String>{};
    final replaced = <_File>[];
    try {
      for (final file in planned) {
        fs.createDirectory(p.posix.dirname(file.target));
        final temporary = fs.temporaryFor(file.target);
        final writer = fs.openWrite(temporary, exclusive: true);
        temporaries[file] = temporary;
        try {
          writer.add(file.content);
        } finally {
          writer.close();
        }
      }
      for (final file in planned) {
        await _locked(file, () => _move(temporaries[file]!, file.target));
        temporaries.remove(file);
        replaced.add(file);
      }
    } on Object catch (error) {
      for (final file in replaced.reversed) {
        _restore(file);
      }
      throw error is YaguraException
          ? error
          : YaguraException(
              'internal_error',
              'could not write configuration files: $error',
            );
    } finally {
      for (final temporary in temporaries.values) {
        try {
          fs.delete(temporary);
        } on Object {
          // Best effort: the temporary file is not the target.
        }
      }
    }
  }

  void _restore(_File file) {
    try {
      if (!file.existed) {
        fs.delete(file.target);
        return;
      }
      final temporary = fs.temporaryFor(file.target);
      try {
        final writer = fs.openWrite(temporary, exclusive: true);
        try {
          writer.add(file.original!);
        } finally {
          writer.close();
        }
        fs.rename(temporary, file.target);
      } on Object {
        try {
          fs.delete(temporary);
        } on Object {
          // Best effort: the temporary file is not the target.
        }
        rethrow;
      }
    } on Object {
      // Nothing more can be done; the original error is reported.
    }
  }

  // ---- locks -----------------------------------------------------------------

  /// Runs [operation], trying again every [lockStep] while another process
  /// holds the file, for at most [lockTimeout].
  Future<T> _locked<T>(_File file, T Function() operation) async {
    var waited = Duration.zero;
    while (true) {
      try {
        return operation();
      } on FileSystemException catch (e) {
        if (!_isLock(e)) rethrow;
        if (waited >= lockTimeout) {
          throw YaguraException(
            'file_locked',
            'file "${file.path}" stayed locked by another process for '
                '${lockTimeout.inSeconds} s; stop the process using it',
            details: {'path': file.path},
          );
        }
        await _delay(lockStep);
        waited += lockStep;
      }
    }
  }

  /// Windows: `ERROR_SHARING_VIOLATION` (32) or `ERROR_LOCK_VIOLATION` (33).
  static bool _isLock(FileSystemException e) {
    if (!Platform.isWindows) return false;
    final code = e.osError?.errorCode;
    return code == 32 || code == 33;
  }
}

/// One file of a pass.
class _File {
  _File(this.path, this.target, this.format);

  /// As the caller wrote it, for messages.
  final String path;

  /// The normalised path relative to the instance root.
  final String target;
  final String format;
  final bindings = <BoundKey>[];
  final edits = <FileEdit>[];

  var existed = false;
  List<int>? original;
  String originalHash = '';
  var bom = false;
  var addNewline = false;
  late _Doc document;
  late List<int> content;
  var changed = false;
  String finalHash = '';

  final _values = <BoundKey, Object?>{};

  /// The value of [binding], read once per pass.
  Object? valueOf(BoundKey binding) =>
      _values.putIfAbsent(binding, binding.value);
}

/// A parsed document of any supported format.
abstract class _Doc {
  String toSource();
  Object? get(String key);
  void set(String key, Object value);
  void patch(Object? patch);
}

class _JsonDoc implements _Doc {
  _JsonDoc(this._document);

  final JsonDocument _document;

  @override
  String toSource() => _document.toSource();

  @override
  Object? get(String key) {
    Object? node = _document.toValue();
    for (final segment in key.split('.')) {
      if (node is! Map || !node.containsKey(segment)) return null;
      node = node[segment];
    }
    return node;
  }

  @override
  void set(String key, Object value) {
    Object? patch = value;
    for (final segment in key.split('.').reversed) {
      patch = {segment: patch};
    }
    _document.mergePatch(patch);
  }

  @override
  void patch(Object? patch) => _document.mergePatch(patch);
}

class _KeyDoc implements _Doc {
  _KeyDoc(this._document, {required this.joinLists});

  final ConfigDocument _document;
  final bool joinLists;

  @override
  String toSource() => _document.toSource();

  @override
  Object? get(String key) => _document.get(key);

  @override
  void set(String key, Object value) =>
      _document.set(key, value is List && joinLists ? value.join(',') : value);

  @override
  void patch(Object? patch) {
    if (patch is! Map) {
      throw ArgumentError('the patch must be an object of key paths');
    }
    _document.applyPatch({
      for (final MapEntry(:key, :value) in patch.entries)
        key as String: value is List && joinLists ? value.join(',') : value,
    });
  }
}
