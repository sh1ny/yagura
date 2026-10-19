import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/confined_fs.dart';
import '../instances/instance_roots.dart' show administratorsSid;
import '../platform/acl_writer.dart';
import 'acl_layout.dart';

/// The data directory, held open so that it cannot be renamed or replaced
/// while the daemon starts (design D6, ADR 0015).
abstract interface class HeldDataDir {
  /// The real path of the directory.
  String get path;

  /// Sets owner Administrators and the protected SYSTEM/Administrators DACL
  /// through the held handle. Throws `data_dir_not_protected`.
  void protect();

  void close();
}

/// The service-mode protection of the data directory (design D6). It runs
/// behind an interface because it needs administrator rights: in-process
/// daemon tests inject a fake, and only the `elevated` rows use the Windows
/// one.
abstract interface class DataDirProtector {
  /// Creates the directory at [path] if it is absent, opens it without
  /// following links and without `FILE_SHARE_DELETE`, and keeps it open.
  /// Throws `data_dir_not_protected` when it is a link, leads through one or
  /// is not where it was asked to be.
  HeldDataDir open(String path);

  /// Walks the contents of the data directory while its recorded layout
  /// version is below the current one; see [walkDataDirectory]. Throws
  /// `data_dir_not_protected` naming the first link. Returns whether it ran.
  bool walk(
    String path, {
    String? serverSid,
    String? steamSid,
    required bool complete,
  });
}

/// The `data_dir_not_protected` for [path], refused because of [why].
YaguraException dataDirNotProtected(String path, String why) => YaguraException(
  'data_dir_not_protected',
  'the data directory cannot be protected: $path: $why',
  details: {'path': path},
);

/// The real protection: [AclWriter] handles for the directory itself and the
/// no-follow [ConfinedFs] walk for what is in it.
class AclDataDirProtector implements DataDirProtector {
  AclDataDirProtector({required this.writer, ConfinedFs Function(String)? fs})
    : _fs = fs ?? ConfinedFs.new;

  final AclWriter writer;
  final ConfinedFs Function(String root) _fs;

  @override
  HeldDataDir open(String path) {
    final normal = p.normalize(p.absolute(path));
    try {
      if (FileSystemEntity.typeSync(normal, followLinks: false) ==
          FileSystemEntityType.notFound) {
        Directory(p.dirname(normal)).createSync(recursive: true);
        try {
          return _Held(
            writer.create(
              normal,
              dataDirectoryDacl(),
              ownerSid: administratorsSid,
            ),
          );
        } on PathExists {
          // Created by someone since: opened and checked like any other.
        }
      }
      return _Held(writer.open(normal));
    } on PathRefused catch (e) {
      throw dataDirNotProtected(normal, e.why);
    } on YaguraException {
      rethrow;
    } on Object catch (e) {
      throw dataDirNotProtected(normal, '$e');
    }
  }

  @override
  bool walk(
    String path, {
    String? serverSid,
    String? steamSid,
    required bool complete,
  }) {
    final root = p.normalize(p.absolute(path));
    final fs = _fs(root);
    try {
      return walkDataDirectory(
        fs,
        serverSid: serverSid,
        steamSid: steamSid,
        complete: complete,
      );
    } on AclLinkFound catch (e) {
      throw dataDirNotProtected(
        fs.absolute(e.path),
        'it is a link or junction (reparse point)',
      );
    } on YaguraException catch (e) {
      throw dataDirNotProtected(root, e.message);
    } on FileSystemException catch (e) {
      throw dataDirNotProtected(root, '${e.message} ${e.path ?? ''}'.trim());
    }
  }
}

class _Held implements HeldDataDir {
  _Held(this._directory);

  final ProtectedDirectory _directory;

  @override
  String get path => _directory.path;

  @override
  void protect() {
    try {
      _directory.writeDacl(dataDirectoryDacl(), ownerSid: administratorsSid);
    } on Object catch (e) {
      throw dataDirNotProtected(path, '$e');
    }
  }

  @override
  void close() => _directory.close();
}
