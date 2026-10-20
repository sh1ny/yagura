/// The client's list of paired daemons (design D13).
library;

import 'dart:convert';
import 'dart:io';

/// The registry holds at most this many daemons.
const int kMaxDaemons = 32;

/// The id of the optional loopback development daemon.
const String kDevDaemonId = 'dev';

/// One paired daemon: what the list shows and what the connection needs
/// besides the keychain material.
final class DaemonRecord {
  const DaemonRecord({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.caFingerprint = '',
    this.isDev = false,
    this.lastSeen,
    this.lastRenewal,
  });

  /// The loopback development daemon (insecure credentials, loopback only).
  const DaemonRecord.dev({String host = '127.0.0.1', int port = 7443})
    : this(
        id: kDevDaemonId,
        name: 'Development daemon',
        host: host,
        port: port,
        isDev: true,
      );

  /// The daemon id from its TLS authority `yagurad-<daemon-id>`.
  final String id;
  final String name;
  final String host;
  final int port;

  /// SHA-256 of the pinned CA certificate, 64 lower-case hex characters.
  final String caFingerprint;
  final bool isDev;

  /// When the daemon last answered, kept across restarts. Null when it never
  /// did.
  final DateTime? lastSeen;

  /// When the client last renewed its certificate with this daemon, by the
  /// client's clock; the daily limit on renewals survives restarts through it.
  final DateTime? lastRenewal;

  DaemonRecord copyWith({DateTime? lastSeen, DateTime? lastRenewal}) =>
      DaemonRecord(
        id: id,
        name: name,
        host: host,
        port: port,
        caFingerprint: caFingerprint,
        isDev: isDev,
        lastSeen: lastSeen ?? this.lastSeen,
        lastRenewal: lastRenewal ?? this.lastRenewal,
      );

  String get address => '$host:$port';

  /// The name the server certificate carries; the TLS name check uses it
  /// whatever address the admin typed.
  String get authority => 'yagurad-$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'ca_fingerprint': caFingerprint,
    if (lastSeen != null) 'last_seen': lastSeen!.toUtc().toIso8601String(),
    if (lastRenewal != null)
      'last_renewal': lastRenewal!.toUtc().toIso8601String(),
  };

  /// Throws [FormatException] for a malformed entry.
  factory DaemonRecord.fromJson(Object? json) {
    if (json
        case {
          'id': final String id,
          'name': final String name,
          'host': final String host,
          'port': final int port,
          'ca_fingerprint': final String fingerprint,
        }
        when id.isNotEmpty && host.isNotEmpty && port > 0 && port < 65536) {
      return DaemonRecord(
        id: id,
        name: name,
        host: host,
        port: port,
        caFingerprint: fingerprint,
        lastSeen: switch (json['last_seen']) {
          final String text => DateTime.tryParse(text)?.toLocal(),
          _ => null,
        },
        lastRenewal: switch (json['last_renewal']) {
          final String text => DateTime.tryParse(text)?.toLocal(),
          _ => null,
        },
      );
    }
    throw const FormatException('malformed daemon entry');
  }
}

/// What a [DaemonListStore] found.
final class DaemonListLoad {
  const DaemonListLoad(
    this.daemons, {
    this.unreadable = 0,
    this.unreadableNames = const [],
    this.overCapNames = const [],
    this.damaged = false,
    this.copied = true,
    this.readError,
    this.damagedCopies = 0,
  });

  final List<DaemonRecord> daemons;

  /// Entries that could not be read. They stay in the file.
  final int unreadable;

  /// The names of the unreadable entries where they can be told.
  final List<String> unreadableNames;

  /// The daemons beyond the cap of [kMaxDaemons]: not shown, not checked, and
  /// kept in the file under `over_cap`, apart from the unreadable entries.
  final List<String> overCapNames;

  /// The file was read but is not a daemon list (not JSON, or the wrong
  /// shape).
  final bool damaged;

  /// For a [damaged] file: whether a copy of it was kept next to it. When it
  /// was not, the store refuses to save, so the original is never lost.
  final bool copied;

  /// Why the file could not be read at all (locked, no permission, ...). It
  /// is not damaged then: nothing is copied or replaced, saving is refused,
  /// and the next start tries again.
  final String? readError;

  /// How many `daemons.json.damaged*` copies are kept next to the file.
  final int damagedCopies;

  /// Whether the list is known to be complete: only then may key material of
  /// unlisted daemons be deleted.
  bool get clean =>
      unreadable == 0 &&
      overCapNames.isEmpty &&
      !damaged &&
      readError == null &&
      damagedCopies == 0;

  DaemonListLoad without({
    bool unreadableEntries = false,
    bool copies = false,
  }) => DaemonListLoad(
    daemons,
    unreadable: unreadableEntries ? 0 : unreadable,
    unreadableNames: unreadableEntries ? const [] : unreadableNames,
    overCapNames: unreadableEntries ? const [] : overCapNames,
    damaged: damaged,
    copied: copied,
    readError: readError,
    damagedCopies: copies ? 0 : damagedCopies,
  );
}

/// Where the list is kept: a file in the app's support directory.
abstract interface class DaemonListStore {
  Future<DaemonListLoad> load();

  /// Throws when the list cannot be written.
  Future<void> save(List<DaemonRecord> daemons);

  /// Forgets the entries that could not be read; the next [save] drops them
  /// from the file.
  void discardUnreadable();

  /// Deletes the `daemons.json.damaged*` copies.
  Future<void> discardDamagedCopies();

  /// Why [save] will refuse (the list could not be read, or a damaged file
  /// could not be copied aside), or null. Pairing checks it before it uses
  /// the one-time code.
  String? get saveRefusal;
}

/// [DaemonListStore] over one JSON file.
///
/// An entry that cannot be read is skipped, not fatal, and is written back
/// under `unreadable` on every save, so one bad entry never costs the others
/// and a newer client can still read it. A file that is not a daemon list is
/// copied to `<file>.damaged` before anything overwrites it. A file that
/// cannot be read at all (locked, no permission) is not damaged: it is left
/// alone and nothing is saved until a later start can read it.
final class FileDaemonListStore implements DaemonListStore {
  FileDaemonListStore(this.file, {Future<String> Function(File file)? readText})
    : _readText = readText ?? ((file) => file.readAsString());

  final File file;
  final Future<String> Function(File file) _readText;
  List<Object?> _unreadable = const [];
  List<Object?> _overCap = const [];

  /// Set while the file is damaged and no copy of it exists, or could not be
  /// read.
  String? _refuseSave;

  @override
  String? get saveRefusal => _refuseSave;

  @override
  Future<DaemonListLoad> load() async {
    _refuseSave = null;
    final loaded = await _load();
    final List<File> copies;
    try {
      copies = await _copies();
    } on FileSystemException catch (e) {
      return _unreadableFile(e, loaded.daemons);
    }
    return copies.isEmpty
        ? loaded
        : DaemonListLoad(
            loaded.daemons,
            unreadable: loaded.unreadable,
            unreadableNames: loaded.unreadableNames,
            overCapNames: loaded.overCapNames,
            damaged: loaded.damaged,
            copied: loaded.copied,
            readError: loaded.readError,
            damagedCopies: copies.length,
          );
  }

  Future<DaemonListLoad> _load() async {
    try {
      if (!await file.exists()) return const DaemonListLoad([]);
      final json = jsonDecode(await _readText(file));
      if (json case {'daemons': final List<Object?> entries}) {
        final daemons = <DaemonRecord>[];
        final bad = <Object?>[];
        final names = <String>[];
        final over = <Object?>[];
        if (json['unreadable'] case final List<Object?> kept) {
          for (final entry in kept) {
            bad.add(entry);
            if (_nameOf(entry) case final name?) names.add(name);
          }
        }
        // The daemons of the file come first, then those that earlier did
        // not fit; each takes a free place if there is one.
        for (final entry in [
          ...entries,
          if (json['over_cap'] case final List<Object?> kept) ...kept,
        ]) {
          if (daemons.length >= kMaxDaemons) {
            over.add(entry);
            continue;
          }
          try {
            daemons.add(DaemonRecord.fromJson(entry));
          } on FormatException {
            bad.add(entry);
            if (_nameOf(entry) case final name?) names.add(name);
          }
        }
        _unreadable = bad;
        _overCap = over;
        final overCap = [
          for (final entry in over) _nameOf(entry) ?? 'a daemon without a name',
        ];
        return DaemonListLoad(
          daemons,
          unreadable: bad.length,
          unreadableNames: names,
          overCapNames: overCap,
        );
      }
    } on FormatException {
      // Not JSON (or not UTF-8): the file is damaged.
      return _damaged();
    } on FileSystemException catch (e) {
      return _unreadableFile(e, const []);
    }
    // JSON, but not a daemon list.
    return _damaged();
  }

  static String? _nameOf(Object? entry) {
    if (entry case {'name': final String name} when name.isNotEmpty) {
      return name;
    }
    if (entry case {'id': final String id} when id.isNotEmpty) return id;
    return null;
  }

  DaemonListLoad _unreadableFile(
    FileSystemException error,
    List<DaemonRecord> daemons,
  ) {
    final os = error.osError?.message.trim() ?? '';
    final why = os.isEmpty ? error.message : '${error.message}: $os';
    _refuseSave =
        'the daemon list ${file.path} could not be read ($why), so nothing '
        'is saved until it can be';
    return DaemonListLoad(daemons, readError: why);
  }

  /// The `daemons.json.damaged*` files next to the list.
  Future<List<File>> _copies() async {
    final parent = file.parent;
    if (!await parent.exists()) return const [];
    final prefix = '${file.uri.pathSegments.last}.damaged';
    return [
      await for (final entity in parent.list())
        if (entity is File && entity.uri.pathSegments.last.startsWith(prefix))
          entity,
    ];
  }

  @override
  Future<void> discardDamagedCopies() async {
    for (final copy in await _copies()) {
      await copy.delete();
    }
  }

  /// A damaged file is copied to `<file>.damaged` (or `.damaged.1`, ... when
  /// that name holds something else) before anything may overwrite it. If no
  /// copy can be made, saving is refused.
  Future<DaemonListLoad> _damaged() async {
    for (var n = 0; n < 20; n++) {
      final target = File('${file.path}.damaged${n == 0 ? '' : '.$n'}');
      try {
        final bytes = await file.readAsBytes();
        if (await target.exists()) {
          if (_same(await target.readAsBytes(), bytes)) {
            _refuseSave = null;
            return const DaemonListLoad([], damaged: true);
          }
          continue;
        }
        await target.writeAsBytes(bytes, flush: true);
        _refuseSave = null;
        return const DaemonListLoad([], damaged: true);
      } on FileSystemException {
        break;
      }
    }
    _refuseSave =
        'the damaged ${file.path} could not be copied aside, so the list '
        'is not saved; fix or move that file';
    return const DaemonListLoad([], damaged: true, copied: false);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void discardUnreadable() {
    _unreadable = const [];
    _overCap = const [];
  }

  @override
  Future<void> save(List<DaemonRecord> daemons) async {
    if (_refuseSave case final reason?) throw FileSystemException(reason);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'daemons': [
          for (final d in daemons)
            if (!d.isDev) d.toJson(),
        ],
        if (_unreadable.isNotEmpty) 'unreadable': _unreadable,
        if (_overCap.isNotEmpty) 'over_cap': _overCap,
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }
}

/// The directory for the app's own files.
String supportDirectory() {
  final env = Platform.environment;
  final sep = Platform.pathSeparator;
  if (Platform.isWindows) {
    return '${env['APPDATA'] ?? env['USERPROFILE'] ?? '.'}${sep}Yagura';
  }
  if (Platform.isMacOS) {
    return '${env['HOME'] ?? '.'}/Library/Application Support/Yagura';
  }
  final data = env['XDG_DATA_HOME'];
  return data != null && data.isNotEmpty
      ? '$data/yagura'
      : '${env['HOME'] ?? '.'}/.local/share/yagura';
}
