import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../errors.dart';
import '../files/files.dart';
import 'mod_entry.dart';
import 'stage_link.dart';

/// The marker a staged copy carries so the daemon can tell it from an admin's
/// folder (design D7).
const stagedMarker = '.yagura-staged';

/// Makes and removes the entries of staged mods in an instance's stage
/// directory (design D7). It works through an [InstanceFs] without recorded
/// junctions: it looks at an entry without following it, and removes a link
/// itself, never what it points at.
class ModStager {
  ModStager({
    required this.fs,
    required this.spec,
    required this.instanceId,
    required this.operationId,
    required this.stageLink,
  });

  final InstanceFs fs;
  final ModsSpec spec;
  final String instanceId;
  final String operationId;
  final StageLinkCreator stageLink;

  String get stageDir => spec.stageDir;

  String pathOf(ModEntry mod) => p.posix.join(stageDir, mod.stagedName);

  /// The entry named [name] in the stage directory, not followed.
  ConfinedEntry? entryNamed(String name) {
    if (fs.stat(stageDir) == null) return null;
    final wanted = name.toLowerCase();
    for (final entry in fs.list(stageDir)) {
      if (entry.name.toLowerCase() == wanted) return entry;
    }
    return null;
  }

  /// Names present in the stage directory, lower-cased.
  Set<String> presentNames() {
    if (fs.stat(stageDir) == null) return {};
    return {for (final e in fs.list(stageDir)) e.name.toLowerCase()};
  }

  /// Whether [entry], the entry of [mod], is one Yagura made (design D7): a
  /// link of any target when the row records a link, or a directory with the
  /// marker of this instance and item when it records a copy.
  bool isRecorded(ModEntry mod, ConfinedEntry entry) {
    switch (mod.stageKind) {
      case 'link':
        return entry.isLink;
      case 'copy':
        if (!entry.isDirectory || entry.isLink) return false;
        final marker = _marker(mod);
        return marker != null &&
            marker['instanceId'] == instanceId &&
            marker['itemId'] == mod.itemId;
      default:
        return false;
    }
  }

  Map<String, Object?>? _marker(ModEntry mod) {
    final path = p.posix.join(pathOf(mod), stagedMarker);
    try {
      if (fs.stat(path) == null) return null;
      final decoded = jsonDecode(
        utf8.decode(fs.readBytes(path, maxBytes: 4096)),
      );
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  /// Whether the recorded [entry] already is what staging [mod] at [target]
  /// would make.
  bool isCurrent(ModEntry mod, ConfinedEntry entry, String target) {
    if (mod.stageKind == 'link') {
      if (!entry.isLink) return false;
      final actual = fs.junctionTarget(pathOf(mod));
      return actual != null && p.equals(actual, p.normalize(target));
    }
    return _marker(mod)?['version'] == mod.desiredVersion;
  }

  /// Removes the entry at [mod]'s path without following it.
  void remove(ModEntry mod) => fs.deleteTree(pathOf(mod));

  /// The `stage_name_conflict` failure for [mod].
  YaguraException conflict(ModEntry mod) => YaguraException(
    'stage_name_conflict',
    '"${pathOf(mod)}" exists and was not made by Yagura for '
        '${mod.itemId}; rename or remove it and apply the mods again',
    details: {'path': pathOf(mod), 'item': mod.itemId},
  );

  /// Makes the entry of [mod] for the content directory [target] and returns
  /// its kind. Nothing is at the path.
  String create(ModEntry mod, String target) {
    final path = pathOf(mod);
    if (spec.stage == ModStage.link) {
      try {
        stageLink(fs, path, target);
        return 'link';
      } on Object catch (e) {
        _dropEmpty(path);
        if (!spec.copyFallback) {
          throw YaguraException(
            'stage_link_failed',
            'could not link "$path" to the mod ${mod.itemId}: ${_why(e)}',
            details: {'path': path, 'item': mod.itemId},
          );
        }
      }
    }
    _copy(mod, target);
    return 'copy';
  }

  /// A directory a failed link left behind, if it is an empty plain one.
  void _dropEmpty(String path) {
    try {
      final left = fs.stat(path);
      if (left != null && left.isDirectory && !left.isLink) fs.delete(path);
    } on Object {
      // Not empty or not ours: left for the admin.
    }
  }

  void _copy(ModEntry mod, String target) {
    final path = pathOf(mod);
    final scratch = p.posix.join(
      InstanceFs.yaguraDirectory,
      'stage-$operationId',
    );
    final copy = p.posix.join(scratch, mod.stagedName);
    try {
      fs.createDirectory(scratch);
      fs.copyIn(target, copy);
      fs.writeBytes(
        p.posix.join(copy, stagedMarker),
        utf8.encode(
          jsonEncode({
            'instanceId': instanceId,
            'itemId': mod.itemId,
            'version': mod.desiredVersion,
          }),
        ),
      );
      fs.rename(copy, path);
    } on YaguraException {
      rethrow;
    } on FileSystemException catch (e) {
      throw YaguraException(
        'stage_link_failed',
        'could not copy the mod ${mod.itemId} to "$path": ${_why(e)}',
        details: {'path': path, 'item': mod.itemId},
      );
    } finally {
      try {
        fs.deleteTree(scratch);
      } on Object {
        // The scratch directory is swept with the instance's own files.
      }
    }
  }

  static String _why(Object error) => switch (error) {
    FileSystemException(:final message, :final osError) =>
      osError == null || message.contains(osError.message)
          ? message
          : '$message (${osError.message})',
    YaguraException(:final message) => message,
    _ => '$error',
  };
}
