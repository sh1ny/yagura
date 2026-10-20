import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yagura_formats/yagura_formats.dart';

import '../errors.dart';
import 'confined_fs.dart';

/// One file edit returned by a hook: a merge patch for a file of the given
/// format. Only `json` is supported in this version.
class FileEdit {
  const FileEdit({
    required this.path,
    required this.format,
    required this.patch,
  });

  /// Path relative to the instance root.
  final String path;
  final String format;

  /// RFC 7386 merge patch as plain JSON data.
  final Object? patch;
}

/// Applies the file edits of one hook result inside an instance (design D22
/// and D23): all edits or none.
///
/// Every path goes through the instance's [ConfinedFs], so an edit outside
/// the root, or through a link or junction, fails with `sandbox_violation`.
/// All new contents are computed in memory before anything is written; each
/// file is then written to a temporary file in its directory and moved over
/// the target with an atomic rename. If a rename fails, files already replaced
/// are restored.
class FileEditWriter {
  FileEditWriter(
    this.fs, {
    void Function(String temporary, String target)? rename,
  }) : _rename = rename; // ignore: prefer_initializing_formals

  /// Largest file an edit reads or produces.
  static const maxFileBytes = 16 * 1024 * 1024;

  final ConfinedFs fs;
  final void Function(String temporary, String target)? _rename;

  void _move(String temporary, String target) {
    if (_rename case final rename?) {
      rename(temporary, target);
    } else {
      fs.rename(temporary, target);
    }
  }

  /// Applies [edits] in order; several edits of one file apply in sequence.
  void apply(List<FileEdit> edits) {
    final planned = _plan(edits);
    if (planned.isEmpty) return;
    _commit(planned);
  }

  /// Phase 1: validate formats and paths and compute every new content.
  List<_Planned> _plan(List<FileEdit> edits) {
    for (final edit in edits) {
      if (edit.format != 'json') {
        throw YaguraException(
          'unsupported_in_this_version',
          'file edit "${edit.path}" has format "${edit.format}"; '
              'only json is supported in this version',
          details: {'path': edit.path, 'format': edit.format},
        );
      }
    }
    final byTarget = <String, _Planned>{};
    for (final edit in edits) {
      final target = fs.parse(edit.path).toString();
      final key = Platform.isWindows ? target.toLowerCase() : target;
      final planned = byTarget.putIfAbsent(key, () => _load(edit, target));
      planned.document.mergePatch(edit.patch);
    }
    return [
      for (final planned in byTarget.values)
        planned..content = _encode(planned),
    ];
  }

  /// The rendered content of [planned]; an output over [maxFileBytes] fails
  /// before anything is written.
  List<int> _encode(_Planned planned) {
    final content = utf8.encode(_render(planned));
    if (content.length > maxFileBytes) {
      throw YaguraException(
        'file_too_large',
        'file edit "${planned.path}" would produce a file over the 16 MiB '
            'limit',
        details: {'path': planned.path},
      );
    }
    return content;
  }

  _Planned _load(FileEdit edit, String target) {
    final entry = fs.stat(target);
    if (entry != null && entry.isDirectory) {
      throw YaguraException(
        'config_parse_error',
        'file edit "${edit.path}" names a directory',
        details: {'path': edit.path},
      );
    }
    if (entry == null) {
      // A new file: start from an empty indented object so added keys are
      // pretty printed.
      final seed = JsonDocument.parse('{\n  "k": 0\n}')
        ..mergePatch({'k': null});
      return _Planned(edit.path, target, seed, existed: false);
    }
    if (entry.size > maxFileBytes) {
      throw YaguraException(
        'file_too_large',
        'file edit "${edit.path}" targets a file over the 16 MiB limit',
        details: {'path': edit.path},
      );
    }
    final String text;
    try {
      text = utf8.decode(fs.readBytes(target, maxBytes: maxFileBytes));
    } on FormatException {
      throw YaguraException(
        'config_parse_error',
        'file "${edit.path}" is not valid UTF-8 JSON',
        details: {'path': edit.path},
      );
    } on YaguraException catch (e) {
      if (e.reason != 'file_too_large') rethrow;
      throw YaguraException(
        'file_too_large',
        'file edit "${edit.path}" targets a file over the 16 MiB limit',
        details: {'path': edit.path},
      );
    }
    try {
      return _Planned(
        edit.path,
        target,
        JsonDocument.parse(text),
        existed: true,
        original: utf8.encode(text),
      );
    } on FormatException catch (e) {
      throw YaguraException(
        'config_parse_error',
        'file "${edit.path}" is not valid JSON: ${e.message}',
        details: {'path': edit.path},
      );
    }
  }

  String _render(_Planned planned) {
    final source = planned.document.toSource();
    return planned.existed ? source : '$source\n';
  }

  /// Phase 2: temporary files, then renames, restoring on failure.
  void _commit(List<_Planned> planned) {
    final temporaries = <_Planned, String>{};
    final replaced = <_Planned>[];
    try {
      for (final item in planned) {
        fs.createDirectory(p.posix.dirname(item.target));
        final temporary = fs.temporaryFor(item.target);
        final writer = fs.openWrite(temporary, exclusive: true);
        temporaries[item] = temporary;
        try {
          writer.add(item.content);
        } finally {
          writer.close();
        }
      }
      for (final item in planned) {
        _move(temporaries[item]!, item.target);
        temporaries.remove(item);
        replaced.add(item);
      }
    } on Object catch (error) {
      for (final item in replaced.reversed) {
        _restore(item);
      }
      throw error is YaguraException
          ? error
          : YaguraException(
              'internal_error',
              'could not write file edits: $error',
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

  void _restore(_Planned item) {
    try {
      if (!item.existed) {
        fs.delete(item.target);
      } else {
        final temporary = fs.temporaryFor(item.target);
        try {
          final writer = fs.openWrite(temporary, exclusive: true);
          try {
            writer.add(item.original!);
          } finally {
            writer.close();
          }
          fs.rename(temporary, item.target);
        } on Object {
          try {
            fs.delete(temporary);
          } on Object {
            // Best effort: the temporary file is not the target.
          }
          rethrow;
        }
      }
    } on Object {
      // Nothing more can be done; the original error is reported.
    }
  }
}

class _Planned {
  _Planned(
    this.path,
    this.target,
    this.document, {
    required this.existed,
    this.original,
  });

  final String path;
  final String target;
  final JsonDocument document;
  final bool existed;
  final List<int>? original;
  late List<int> content;
}
