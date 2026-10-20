import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/confined_fs.dart';
import '../files/instance_fs.dart';
import 'process_host.dart';

/// The files of one run in `<instance>/.yagura/run/<run-id>/` (ADR 0009):
/// `launch.json` (what to start; written by the supervisor), `relay.json`
/// and `exit.json` (written by the relay), and `cancel.json` (written by a
/// supervisor that gave up waiting for the server). All carry
/// `format_version: 1`.
///
/// The daemon reads and writes every run file through [fs], the instance's
/// confinement, so a link a server planted in the run path stops the access
/// (design D8): the daemon runs as SYSTEM and must not follow a link to a file
/// only SYSTEM can read. [RunFiles.forRun] builds it for the daemon. The relay
/// is a separate process running as the server's account; it reads and writes
/// by path (`relay_run_files.dart`), without [fs], because a link in its own
/// run directory gains it nothing the account does not already have. How far
/// the daemon trusts what it reads is design D9.
class RunFiles {
  const RunFiles(this.directory, {this.fs});

  /// The files of the run in [runDirectory] (`<instance>/.yagura/run/<id>`),
  /// confined to its instance directory: what the daemon uses.
  factory RunFiles.forRun(String runDirectory) => RunFiles(
    runDirectory,
    fs: InstanceFs(p.dirname(p.dirname(p.dirname(runDirectory)))),
  );

  final String directory;

  /// The instance's files; the daemon's reads and writes go through it. A
  /// null [fs] reads by path (the relay and tests).
  final ConfinedFs? fs;

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
  String get cancelPath => p.join(directory, 'cancel.json');

  /// The serialised content of a run file.
  static List<int> encode(Map<String, Object?> json) =>
      utf8.encode(jsonEncode({'format_version': formatVersion, ...json}));

  /// Writes [json] to [path] (inside the instance) atomically through [fs],
  /// creating the run directory first.
  void _writeConfined(String path, Map<String, Object?> json) {
    final confined = fs;
    if (confined == null) {
      throw StateError('the daemon-side run file writes need an InstanceFs');
    }
    confined.createDirectory(confined.relative(directory));
    confined.writeAtomic(confined.relative(path), encode(json));
  }

  /// The decoded file, or null when it is missing, unreadable, behind a link
  /// (through [fs]) or not a v1 object (a reader never trusts a half-written
  /// file).
  Map<String, Object?>? readJson(String path) {
    try {
      final confined = fs;
      final text = confined == null
          ? File(path).readAsStringSync()
          : utf8.decode(
              confined.readBytes(confined.relative(path), maxBytes: _maxBytes),
            );
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?> &&
          decoded['format_version'] == formatVersion) {
        return decoded;
      }
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on YaguraException {
      // A link planted in the run path, or a file over the limit: the file
      // counts as missing.
      return null;
    }
    return null;
  }

  static const _maxBytes = 1024 * 1024;

  void writeLaunch(LaunchRequest request) {
    _writeConfined(launchPath, {
      'executable': request.executable,
      // A secret argument is recorded as its slot, never with the value.
      'args': [
        for (final (index, arg) in request.args.indexed)
          if (request.secretArguments.where((s) => s.index == index).firstOrNull
              case final s?)
            {'secret': s.setting, 'prefix': s.prefix, 'suffix': s.suffix}
          else
            arg,
      ],
      'working_directory': request.workingDirectory,
      'instance_directory': request.instanceDirectory,
      'run_id': request.runId,
      'stdout_encoding': request.stdoutEncoding,
    });
  }

  LaunchRequest? readLaunch() {
    final json = readJson(launchPath);
    if (json == null) return null;
    final args = <String>[];
    final secretArguments = <SecretArgument>[];
    for (final arg in json['args']! as List) {
      switch (arg) {
        case String():
          args.add(arg);
        case {
          'secret': final String setting,
          'prefix': final String prefix,
          'suffix': final String suffix,
        }:
          final slot = SecretArgument(
            index: args.length,
            setting: setting,
            prefix: prefix,
            suffix: suffix,
          );
          secretArguments.add(slot);
          args.add(slot.redacted);
        default:
          return null;
      }
    }
    return LaunchRequest(
      instanceId: '',
      runId: json['run_id'] as String? ?? '',
      executable: json['executable']! as String,
      args: args,
      secretArguments: secretArguments,
      env: const {},
      workingDirectory: json['working_directory']! as String,
      instanceDirectory: json['instance_directory']! as String,
      runDirectory: directory,
      stdoutEncoding: json['stdout_encoding'] as String? ?? 'utf-8',
    );
  }

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

  /// Tells the relay that nobody waits for its server any more: it must not
  /// start one, and ends one it already started.
  void writeCancel() => _writeConfined(cancelPath, {});

  bool get isCancelled => readJson(cancelPath) != null;

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
