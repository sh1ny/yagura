import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../host/database.dart';
import '../platform/acl_writer.dart';
import '../platform/win32_paths.dart';

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

/// Resolves the links, short names and case of the part of a path that
/// exists; see [resolveExistingPrefix].
typedef PathResolver = String Function(String path);

/// Characters a path component cannot contain (`:` would name a stream).
final _badCharacters = RegExp(r'[<>:"|?*\x00-\x1f]');

/// The places instance directories may live (design D5, `host-service`).
///
/// The default root is `<data>/instances`. Others are added by an
/// administrator on the host; each is given the protected DACL first, and is
/// not a root when that fails.
///
/// Windows reads a path differently from its text: trailing dots and spaces
/// of a component are dropped (`<root>\...` is the root), 8.3 short names and
/// letter case name the same folder, and a junction or link anywhere in the
/// path leads somewhere else. So a path is checked for components that
/// Windows would rewrite (refused), resolved to the name the file system
/// gives its folder, and only then compared, ignoring case.
class HostRoots {
  HostRoots(
    this._database, {
    required this.defaultRoot,
    required this.dataDirectory,
    this.writer,
    this.accounts,
    PathResolver? resolve,
    DateTime Function()? clock,
  }) : _resolve =
           resolve ?? (Platform.isWindows ? resolveExistingPrefix : _same),
       _clock = clock ?? DateTime.now;

  final YaguraDatabase _database;
  final String defaultRoot;
  final String dataDirectory;
  final AclWriter? writer;
  final AccountSids? accounts;
  final PathResolver _resolve;
  final DateTime Function() _clock;

  static String _same(String path) => path;

  static String _key(String path) => path.toLowerCase();

  static bool _equals(String a, String b) => _key(a) == _key(b);

  static bool _within(String parent, String child) =>
      p.isWithin(_key(parent), _key(child));

  /// [path] made absolute and normalised, or a [FormatException] saying why
  /// Windows would read it as another path: a component ending in a dot or a
  /// space (`...`, `a.`, `a `), a character no name has, or a device path.
  static String checked(String path) {
    final absolute = p.absolute(path);
    if (absolute.startsWith(r'\\?\') || absolute.startsWith(r'\\.\')) {
      throw const FormatException('a device path cannot be used');
    }
    final normal = p.normalize(absolute);
    for (final part in p.split(normal).skip(1)) {
      if (part.endsWith('.') || part.endsWith(' ')) {
        throw FormatException(
          'Windows drops the trailing dots and spaces of "$part", so it '
          'would not name what it says',
        );
      }
      if (part.contains(_badCharacters)) {
        throw FormatException('"$part" is not a valid name');
      }
    }
    return normal;
  }

  /// The real name of [path]: checked (see [checked]), with the links of its
  /// folders resolved, short names expanded and the case of what exists.
  /// Throws a [FormatException] for a path that is not a plain one.
  String canonical(String path) => _resolve(checked(path));

  String _canonicalOr(String path) {
    try {
      return canonical(path);
    } on FormatException {
      return p.normalize(p.absolute(path));
    }
  }

  /// The default root, then the added ones in the order they were added.
  List<HostRootInfo> list() => [
    HostRootInfo(_canonicalOr(defaultRoot), isDefault: true),
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

  /// Whether [directory] is strictly below a root. Throws a
  /// [FormatException] when it is not a plain path.
  bool allows(String directory) {
    final path = canonical(directory);
    return list().any((root) => _within(root.path, path));
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

  /// Refuses a [root] that is a drive, holds or lies in the data directory,
  /// or nests with another root, so that no existing ACL is touched.
  void _checkPlacement(String root) {
    if (p.rootPrefix(root) == root || p.dirname(root) == root) {
      throw _notAllowed(root, 'a whole drive cannot be a root');
    }
    final data = _canonicalOr(dataDirectory);
    if (_equals(root, data) || _within(data, root) || _within(root, data)) {
      throw _notAllowed(root, 'it holds or lies in the data directory $data');
    }
    for (final other in list()) {
      if (_equals(root, other.path)) {
        if (other.isDefault) {
          throw _notAllowed(root, 'it is the default root already');
        }
        continue;
      }
      if (_within(other.path, root) || _within(root, other.path)) {
        throw _notAllowed(root, 'it nests with the root ${other.path}');
      }
    }
  }

  /// Makes [path] an instance root: refuses a path that is not a plain one,
  /// a drive, one that holds or lies in the data directory or nests with
  /// another root; opens the directory by handle (refusing a link, at the end
  /// or on the way) and writes the protected DACL through that handle; then
  /// records the root under its real name. Adding a root again, in any case or
  /// by its short name, writes the DACL again and changes nothing else.
  void add(String path) {
    final String requested;
    try {
      requested = checked(path);
    } on FormatException catch (e) {
      throw _notAllowed(p.absolute(path), e.message);
    }
    _checkPlacement(_resolve(requested));
    final protector = writer;
    if (protector == null) {
      throw _notProtected(requested, 'this daemon cannot write ACLs');
    }
    final ProtectedDirectory directory;
    try {
      directory = protector.open(requested);
    } on Object catch (e) {
      throw _notProtected(requested, e is PathRefused ? e.why : '$e');
    }
    try {
      final root = directory.path;
      _checkPlacement(root);
      try {
        directory.writeDacl(
          rootDaclSddl(
            serverSid: accounts?.sidOf('yagura-srv'),
            steamSid: accounts?.sidOf('yagura-steam'),
          ),
          ownerSid: administratorsSid,
        );
      } on Object catch (e) {
        throw _notProtected(root, '$e');
      }
      final known = list().any((r) => _equals(r.path, root));
      if (!known) {
        _database.sqlite.execute(
          'INSERT INTO instance_roots(path, added_at) VALUES (?, ?)',
          [root, _clock().millisecondsSinceEpoch],
        );
      }
    } finally {
      directory.close();
    }
  }

  /// Removes the root [path] from the configuration while none of
  /// [instances] lives in it. The ACL stays (ADR 0015: entries are never
  /// withdrawn).
  void remove(String path, {required Iterable<RootedInstance> instances}) {
    final String root;
    try {
      root = canonical(path);
    } on FormatException catch (e) {
      throw _notAllowed(p.absolute(path), e.message);
    }
    final info = list().where((r) => _equals(r.path, root)).firstOrNull;
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
        if (_within(info.path, _canonicalOr(i.directory))) i,
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
