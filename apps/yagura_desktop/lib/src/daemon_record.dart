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
      );
    }
    throw const FormatException('malformed daemon entry');
  }
}

/// Where the list is kept: a file in the app's support directory.
abstract interface class DaemonListStore {
  /// The saved daemons; an unreadable store yields an empty list.
  Future<List<DaemonRecord>> load();
  Future<void> save(List<DaemonRecord> daemons);
}

/// [DaemonListStore] over one JSON file.
final class FileDaemonListStore implements DaemonListStore {
  FileDaemonListStore(this.file);

  final File file;

  @override
  Future<List<DaemonRecord>> load() async {
    try {
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString());
      if (json case {'daemons': final List<Object?> entries}) {
        return [
          for (final entry in entries.take(kMaxDaemons))
            DaemonRecord.fromJson(entry),
        ];
      }
    } on FormatException {
      // A damaged list is treated as empty: pairing again recreates it.
    } on FileSystemException {
      // Unreadable: same.
    }
    return const [];
  }

  @override
  Future<void> save(List<DaemonRecord> daemons) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'daemons': [
          for (final d in daemons)
            if (!d.isDev) d.toJson(),
        ],
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
