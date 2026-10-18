import 'dart:io';

import 'process_host.dart';
import 'run_files.dart';

/// The run files the relay writes: `relay.json` and `exit.json`.
///
/// The relay is a separate process that owns the server's pipes. It writes
/// by path, not through `ConfinedFs`: it is not the daemon, and it runs as
/// the server's account once group 9 lands, so a link in the run directory
/// gains nothing a server did not already have. The daemon's own writes are
/// in [RunFiles].
extension RelayRunFiles on RunFiles {
  /// Writes [json] to [path] atomically, so a reader sees all or nothing.
  static void writeJson(String path, Map<String, Object?> json) {
    // The pid keeps writers in different processes off each other's file.
    final temp = File('$path.$pid.tmp');
    temp.writeAsBytesSync(RunFiles.encode(json));
    temp.renameSync(path);
  }

  /// Writes the relay's own identity, before it starts the server.
  void writeRelay(ProcessIdentity relay) => _writeRelay(relay, null);

  /// Adds the server's identity to `relay.json`.
  void writeRelayAndServer(ProcessIdentity relay, ProcessIdentity server) =>
      _writeRelay(relay, server);

  void _writeRelay(ProcessIdentity relay, ProcessIdentity? server) =>
      RelayRunFiles.writeJson(relayPath, {
        'relay_pid': relay.pid,
        'relay_created': relay.created,
        'relay_executable': relay.executable,
        if (server != null) ...{
          'server_pid': server.pid,
          'server_created': server.created,
          'server_executable': server.executable,
        },
      });

  /// Records the end of the run. [error] is set when the server could not be
  /// started at all.
  void writeExit(int exitCode, DateTime at, {String? error}) =>
      RelayRunFiles.writeJson(exitPath, {
        'exit_code': exitCode,
        'exited_at': at.toUtc().toIso8601String(),
        'error': ?error,
      });
}
