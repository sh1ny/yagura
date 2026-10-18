import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../host/database.dart';
import '../platform/acl_writer.dart';

/// The SID of the Administrators group, owner of every protected root.
const administratorsSid = 'S-1-5-32-544';

/// Access mask of a traverse-only entry: `SYNCHRONIZE | FILE_TRAVERSE`.
const _traverseOnly = '0x100020';

/// The protected DACL of an instance root (ADR 0015): SYSTEM and
/// Administrators full control (inherited by what is created below), and
/// traverse only for the service accounts that exist. Neither service account
/// can create, delete or rename anything directly in the root.
String rootDaclSddl({String? serverSid, String? steamSid}) =>
    'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    '${serverSid == null ? '' : '(A;;$_traverseOnly;;;$serverSid)'}'
    '${steamSid == null ? '' : '(A;;$_traverseOnly;;;$steamSid)'}';

/// One instance root as listed.
class HostRootInfo {
  const HostRootInfo(this.path, {required this.isDefault, this.addedAt});

  final String path;
  final bool isDefault;
  final DateTime? addedAt;
}

/// An instance, as far as the roots care.
typedef RootedInstance = ({String id, String name, String directory});

/// The places instance directories may live (design D5, `host-service`).
///
/// The default root is `<data>/instances`. Others are added by an
/// administrator on the host; each is given the protected DACL first, and is
/// not a root when that fails.
class HostRoots {
  HostRoots(
    this._database, {
    required this.defaultRoot,
    required this.dataDirectory,
    this.writer,
    this.accounts,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final YaguraDatabase _database;
  final String defaultRoot;
  final String dataDirectory;
  final AclWriter? writer;
  final AccountSids? accounts;
  final DateTime Function() _clock;

  static String _normal(String path) => p.normalize(p.absolute(path));

  /// The default root, then the added ones in the order they were added.
  List<HostRootInfo> list() => [
    HostRootInfo(_normal(defaultRoot), isDefault: true),
    for (final row in _database.sqlite.select(
      'SELECT path, added_at FROM instance_roots ORDER BY added_at, path',
    ))
      HostRootInfo(
        row['path']! as String,
        isDefault: false,
        addedAt: DateTime.fromMillisecondsSinceEpoch(
          row['added_at']! as int,
          isUtc: true,
        ),
      ),
  ];

  /// Whether [directory] is strictly below a root.
  bool allows(String directory) {
    final path = _normal(directory);
    return list().any((root) => p.isWithin(root.path, path));
  }

  YaguraException _notAllowed(String path, String why) => YaguraException(
    'directory_not_allowed',
    'cannot use $path as an instance root: $why',
    details: {'path': path},
  );

  YaguraException _notProtected(String path, String why) => YaguraException(
    'root_not_protected',
    'cannot protect the instance root $path: $why',
    details: {'path': path},
  );

  /// Makes [path] an instance root: refuses a path that is a drive, holds or
  /// lies in the data directory, or nests with another root (so that no
  /// existing ACL is touched), then writes the protected DACL and records the
  /// root. Adding a root again writes the DACL again.
  void add(String path) {
    final root = _normal(path);
    if (p.rootPrefix(root) == root || p.dirname(root) == root) {
      throw _notAllowed(root, 'a whole drive cannot be a root');
    }
    final data = _normal(dataDirectory);
    if (p.equals(root, data) ||
        p.isWithin(data, root) ||
        p.isWithin(root, data)) {
      throw _notAllowed(root, 'it holds or lies in the data directory $data');
    }
    final existing = list();
    for (final other in existing) {
      if (p.equals(root, other.path)) {
        if (other.isDefault) {
          throw _notAllowed(root, 'it is the default root already');
        }
        continue;
      }
      if (p.isWithin(other.path, root) || p.isWithin(root, other.path)) {
        throw _notAllowed(root, 'it nests with the root ${other.path}');
      }
    }
    if (FileSystemEntity.typeSync(root, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw _notProtected(
        root,
        'it is not an existing directory (and a link is not one)',
      );
    }
    final protector = writer;
    if (protector == null) {
      throw _notProtected(root, 'this daemon cannot write ACLs');
    }
    try {
      protector.writeProtectedDacl(
        root,
        rootDaclSddl(
          serverSid: accounts?.sidOf('yagura-srv'),
          steamSid: accounts?.sidOf('yagura-steam'),
        ),
        ownerSid: administratorsSid,
      );
    } on Object catch (e) {
      throw _notProtected(root, '$e');
    }
    _database.sqlite.execute(
      'INSERT OR IGNORE INTO instance_roots(path, added_at) VALUES (?, ?)',
      [root, _clock().millisecondsSinceEpoch],
    );
  }

  /// Removes the root [path] from the configuration while none of
  /// [instances] lives in it. The ACL stays (ADR 0015: entries are never
  /// withdrawn).
  void remove(String path, {required Iterable<RootedInstance> instances}) {
    final root = _normal(path);
    final info = list().where((r) => p.equals(r.path, root)).firstOrNull;
    if (info == null) {
      throw YaguraException(
        'root_not_found',
        '$root is not an instance root',
        details: {'path': root},
      );
    }
    if (info.isDefault) {
      throw _notAllowed(root, 'the default root cannot be removed');
    }
    final inUse = [
      for (final i in instances)
        if (p.isWithin(info.path, _normal(i.directory))) i,
    ];
    if (inUse.isNotEmpty) {
      throw YaguraException(
        'root_in_use',
        'the root ${info.path} is in use by '
            '${inUse.map((i) => '"${i.name}"').join(', ')}; delete or move '
            'them first',
        details: {
          'path': info.path,
          'instances': [
            for (final i in inUse) {'id': i.id, 'name': i.name},
          ],
        },
      );
    }
    _database.sqlite.execute('DELETE FROM instance_roots WHERE path = ?', [
      info.path,
    ]);
  }
}
