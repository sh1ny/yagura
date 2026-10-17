import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'process_host.dart';

/// The files of one run in `<instance>/.yagura/run/<run-id>/` (ADR 0009):
/// `launch.json` (what to start; written by the supervisor), `relay.json`
/// and `exit.json` (written by the relay). All carry `format_version: 1`.
class RunFiles {
  const RunFiles(this.directory);

  final String directory;

  static const formatVersion = 1;

  /// `<instance>/.yagura/run`.
  static String rootFor(String instanceDirectory) =>
      p.join(instanceDirectory, '.yagura', 'run');

  /// The directory of run [runId] of an instance.
  static String directoryFor(String instanceDirectory, String runId) =>
      p.join(rootFor(instanceDirectory), runId);

  String get launchPath => p.join(directory, 'launch.json');
  String get relayPath => p.join(directory, 'relay.json');
  String get exitPath => p.join(directory, 'exit.json');

  /// Writes [json] to [path] atomically, so a reader sees all or nothing.
  static void writeJson(String path, Map<String, Object?> json) {
    // The pid keeps writers in different processes off each other's file.
    final temp = File('$path.$pid.tmp');
    temp.writeAsStringSync(
      jsonEncode({'format_version': formatVersion, ...json}),
    );
    temp.renameSync(path);
  }

  /// The decoded file, or null when it is missing, unreadable or not a v1
  /// object (a reader never trusts a half-written file).
  static Map<String, Object?>? readJson(String path) {
    try {
      final decoded = jsonDecode(File(path).readAsStringSync());
      if (decoded is Map<String, Object?> &&
          decoded['format_version'] == formatVersion) {
        return decoded;
      }
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  void writeLaunch(LaunchRequest request) {
    Directory(directory).createSync(recursive: true);
    writeJson(launchPath, {
      'executable': request.executable,
      'args': request.args,
      'working_directory': request.workingDirectory,
      'instance_directory': request.instanceDirectory,
      'run_id': request.runId,
    });
  }

  LaunchRequest? readLaunch() {
    final json = readJson(launchPath);
    if (json == null) return null;
    return LaunchRequest(
      instanceId: '',
      runId: json['run_id'] as String? ?? '',
      executable: json['executable']! as String,
      args: [for (final a in json['args']! as List) a as String],
      env: const {},
      workingDirectory: json['working_directory']! as String,
      instanceDirectory: json['instance_directory']! as String,
      runDirectory: directory,
    );
  }

  /// Writes the relay's own identity, before it starts the server.
  void writeRelay(ProcessIdentity relay) => _writeRelay(relay, null);

  /// Adds the server's identity to `relay.json`.
  void writeRelayAndServer(ProcessIdentity relay, ProcessIdentity server) =>
      _writeRelay(relay, server);

  void _writeRelay(ProcessIdentity relay, ProcessIdentity? server) =>
      writeJson(relayPath, {
        'relay_pid': relay.pid,
        'relay_created': relay.created,
        'relay_executable': relay.executable,
        if (server != null) ...{
          'server_pid': server.pid,
          'server_created': server.created,
          'server_executable': server.executable,
        },
      });

  RelayRecord? readRelay() {
    final json = readJson(relayPath);
    if (json == null) return null;
    ProcessIdentity? identity(String prefix) {
      final pid = json['${prefix}_pid'];
      final created = json['${prefix}_created'];
      final exe = json['${prefix}_executable'];
      if (pid is! int || created is! int || exe is! String) return null;
      return ProcessIdentity(pid: pid, executable: exe, created: created);
    }

    final relay = identity('relay');
    if (relay == null) return null;
    return RelayRecord(relay, identity('server'));
  }

  /// Records the end of the run. [error] is set when the server could not be
  /// started at all.
  void writeExit(int exitCode, DateTime at, {String? error}) =>
      writeJson(exitPath, {
        'exit_code': exitCode,
        'exited_at': at.toUtc().toIso8601String(),
        'error': ?error,
      });

  /// Why the server could not be started, when the relay recorded it.
  String? readError() => readJson(exitPath)?['error'] as String?;

  /// The exit code the relay recorded, or null before the server exited.
  int? readExitCode() => readJson(exitPath)?['exit_code'] as int?;
}

/// The contents of `relay.json`.
class RelayRecord {
  const RelayRecord(this.relay, this.server);

  final ProcessIdentity relay;

  /// Null until the relay has started the server.
  final ProcessIdentity? server;
}
