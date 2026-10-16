import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:yagura_formats/yagura_formats.dart';

import '../errors.dart';
import 'instance_root.dart';

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
/// Every path is resolved with [InstanceRoot.resolve] first and an edit
/// outside the root fails with `sandbox_violation`. All new contents are
/// computed in memory before anything is written; each file is then written to
/// a temporary file in its directory and moved over the target with an atomic
/// rename. If a rename fails, files already replaced are restored.
class FileEditWriter {
  FileEditWriter(
    this.root, {
    void Function(String temporary, String target)? rename,
  }) : _rename = rename ?? _defaultRename;

  /// Largest file an edit reads or produces.
  static const maxFileBytes = 16 * 1024 * 1024;

  final InstanceRoot root;
  final void Function(String temporary, String target) _rename;
  final _random = Random.secure();

  static void _defaultRename(String temporary, String target) =>
      File(temporary).renameSync(target);

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
      final target = root.resolve(edit.path);
      final key = p.canonicalize(target);
      final planned = byTarget.putIfAbsent(key, () => _load(edit, target));
      planned.document.mergePatch(edit.patch);
    }
    return [
      for (final planned in byTarget.values)
        planned..content = utf8.encode(_render(planned)),
    ];
  }

  _Planned _load(FileEdit edit, String target) {
    final type = FileSystemEntity.typeSync(target);
    if (type == FileSystemEntityType.directory) {
      throw YaguraException(
        'config_parse_error',
        'file edit "${edit.path}" names a directory',
        details: {'path': edit.path},
      );
    }
    if (type == FileSystemEntityType.notFound) {
      // A new file: start from an empty indented object so added keys are
      // pretty printed.
      final seed = JsonDocument.parse('{\n  "k": 0\n}')
        ..mergePatch({'k': null});
      return _Planned(edit.path, target, seed, existed: false);
    }
    final file = File(target);
    if (file.lengthSync() > maxFileBytes) {
      throw YaguraException(
        'file_too_large',
        'file edit "${edit.path}" targets a file over the 16 MiB limit',
        details: {'path': edit.path},
      );
    }
    final String text;
    try {
      text = utf8.decode(file.readAsBytesSync());
    } on FormatException {
      throw YaguraException(
        'config_parse_error',
        'file "${edit.path}" is not valid UTF-8 JSON',
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
        File(item.target).parent.createSync(recursive: true);
        final temporary = p.join(
          p.dirname(item.target),
          '.${p.basename(item.target)}.yagura-${_random.nextInt(1 << 31).toRadixString(16)}.tmp',
        );
        File(temporary).writeAsBytesSync(item.content, flush: true);
        temporaries[item] = temporary;
      }
      for (final item in planned) {
        _rename(temporaries[item]!, item.target);
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
          File(temporary).deleteSync();
        } on FileSystemException {
          // Best effort: the temporary file is not the target.
        }
      }
    }
  }

  void _restore(_Planned item) {
    try {
      if (!item.existed) {
        File(item.target).deleteSync();
      } else {
        final temporary = '${item.target}.yagura-restore.tmp';
        File(temporary).writeAsBytesSync(item.original!, flush: true);
        File(temporary).renameSync(item.target);
      }
    } on FileSystemException {
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
