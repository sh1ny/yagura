import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'firewall_backend.dart';
import 'firewall_script.dart';
import 'rule_names.dart';

/// The environment variable that carries the path of the request file.
const requestPathVariable = 'YAGURA_FIREWALL_REQUEST';

const _requestPrefix = 'request-';

/// The most a script may print (300 rules are about 40 KiB).
const _maxOutputBytes = 4 * 1024 * 1024;

/// The real Windows Firewall, driven by [firewallScript] in Windows
/// PowerShell (design D11). One process per call; a call that outlives its
/// timeout ends the process.
class PowerShellFirewall implements FirewallBackend {
  PowerShellFirewall({
    required this.directory,
    this.removeDirectory = false,
    this.scope = '$firewallGroup/',
    this.executable,
    this.arguments,
    this.prelude,
  });

  /// Where each run's request file is written: a folder only SYSTEM and
  /// Administrators can write to.
  final String directory;

  /// Whether [directory] is removed after a run when it is empty (the
  /// installer's, which must leave nothing in the install folder).
  final bool removeDirectory;

  /// The name prefix a reconcile may delete under: the daemon deletes owned
  /// rules anywhere in the group (`Yagura/`); a test passes the prefix of its
  /// own instance, so it prunes nothing else on the host.
  final String scope;

  /// `powershell.exe`; defaults to the one in `%SystemRoot%`, not the first
  /// on the path.
  final String? executable;

  /// The command line for the encoded script; a seam for tests that run a
  /// stand-in for PowerShell.
  final List<String> Function(String encodedScript)? arguments;

  /// PowerShell run before the script, in the same process; a seam for tests
  /// that put stand-ins in place of the firewall cmdlets.
  final String? prelude;

  static String get _defaultExecutable => p.join(
    Platform.environment['SystemRoot'] ?? r'C:\Windows',
    'System32',
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe',
  );

  @override
  Future<List<ActualRule>> list({required Duration timeout}) async {
    final answer = await _run({'mode': 'list'}, timeout);
    return [
      for (final rule in _objects(answer['rules']))
        ActualRule(
          name: '${rule['name']}',
          protocol: '${rule['protocol']}',
          port: '${rule['port']}',
        ),
    ];
  }

  @override
  Future<ReconcileOutcome> reconcile(
    List<DesiredRule> desired, {
    required Duration timeout,
    bool prune = true,
  }) async {
    final answer = await _run({
      'mode': 'reconcile',
      'prune': prune,
      'desired': [
        for (final rule in desired)
          {'name': rule.name, 'protocol': rule.protocol, 'port': rule.port},
      ],
    }, timeout);
    return ReconcileOutcome(
      changes: _changes(answer),
      unmanaged: [for (final name in _list(answer['unmanaged'])) '$name'],
      diagnostics: diagnosticsOf(answer),
    );
  }

  /// One `list` run, answered whole: the rules and the script's own
  /// `timings` and `fallbacks`, for the timing rows.
  Future<Map<String, Object?>> inspect({required Duration timeout}) =>
      _run({'mode': 'list'}, timeout);

  /// The part of a script answer that describes the run.
  static Map<String, Object?> diagnosticsOf(Map<String, Object?> answer) => {
    for (final key in const ['timings', 'fallbacks', 'joinedByName'])
      if (answer.containsKey(key)) key: answer[key],
  };

  @override
  Future<List<RuleChange>> remove(
    List<String> names, {
    required Duration timeout,
  }) async => _changes(await _run({'mode': 'remove', 'names': names}, timeout));

  static List<RuleChange> _changes(Map<String, Object?> answer) => [
    for (final change in _objects(answer['changes']))
      RuleChange(
        name: '${change['name']}',
        action: '${change['action']}',
        error: '${change['error'] ?? ''}',
      ),
  ];

  // PowerShell writes a one-element array as the element itself in places;
  // read both.
  static List<Object?> _list(Object? value) => switch (value) {
    null => const [],
    final List<Object?> list => list,
    _ => [value],
  };

  static List<Map<String, Object?>> _objects(Object? value) => [
    for (final item in _list(value))
      if (item is Map<String, Object?>) item,
  ];

  Future<Map<String, Object?>> _run(
    Map<String, Object?> request,
    Duration timeout,
  ) async {
    final input = utf8.encode(
      jsonEncode({
        ...request,
        // The group and the name pattern are in the script, not here.
        'scope': scope,
      }),
    );
    // The request goes in a file the script reads, not on standard input: a
    // run with a request of a few hundred rules on stdin never started its
    // script in CI. The command line carries only the script, so it stays
    // short however many rules there are.
    // The limit counts from here, so writing the request and starting
    // PowerShell are inside it.
    final deadline = DateTime.now().add(timeout);
    final file = _writeRequest(input);
    try {
      return await _execute(file.path, deadline, timeout);
    } finally {
      _deleteRequest(file);
    }
  }

  /// Makes a new file in [directory] with a name nobody can guess, holding
  /// [content]. The directory is the daemon's (under the protected data
  /// directory, or the protected install folder), so only SYSTEM and
  /// Administrators can put a file there.
  File _writeRequest(List<int> content) {
    final folder = Directory(directory);
    try {
      folder.createSync(recursive: true);
      _sweep(folder);
      final random = Random.secure();
      final name = [
        for (var i = 0; i < 16; i++)
          random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
      final file = File(p.join(directory, '$_requestPrefix$name.json'))
        ..createSync(exclusive: true);
      file.writeAsBytesSync(content, flush: true);
      return file;
    } on FileSystemException catch (e) {
      throw FirewallUnavailable(
        'the request for PowerShell cannot be written in $directory: '
        '${e.message}',
      );
    }
  }

  /// Deletes the request file, and the folder when this backend owns it and
  /// nothing else is in it. Never fails: the answer is already known.
  void _deleteRequest(File file) {
    try {
      file.deleteSync();
    } on FileSystemException {
      // Left for the sweep of the next run.
    }
    if (!removeDirectory) return;
    try {
      Directory(directory).deleteSync();
    } on FileSystemException {
      // Not empty, or in use: it is only a folder.
    }
  }

  /// Deletes requests an earlier run left (a killed process) after ten
  /// minutes.
  static void _sweep(Directory folder) {
    final old = DateTime.now().subtract(const Duration(minutes: 10));
    try {
      for (final entity in folder.listSync(followLinks: false)) {
        if (entity is File &&
            p.basename(entity.path).startsWith(_requestPrefix) &&
            entity.lastModifiedSync().isBefore(old)) {
          entity.deleteSync();
        }
      }
    } on FileSystemException {
      // The sweep is a courtesy.
    }
  }

  Future<Map<String, Object?>> _execute(
    String requestPath,
    DateTime deadline,
    Duration timeout,
  ) async {
    // -EncodedCommand is UTF-16LE in base64.
    final script = base64.encode([
      for (final unit in '${prelude ?? ''}\n$firewallScript'.codeUnits) ...[
        unit & 0xff,
        unit >> 8,
      ],
    ]);
    final Process process;
    try {
      process = await Process.start(
        executable ?? _defaultExecutable,
        arguments?.call(script) ??
            [
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-EncodedCommand',
              script,
            ],
        environment: {requestPathVariable: requestPath},
      );
    } on ProcessException catch (e) {
      throw FirewallUnavailable('PowerShell cannot be started: ${e.message}');
    }
    final out = _Capture();
    final err = _Capture();
    final streams = Future.wait([
      process.stdout.forEach(out.add),
      process.stderr.forEach(err.add),
    ]);
    // Nothing is sent: the host must never wait for input.
    process.stdin.close().ignore();
    var timedOut = false;
    final left = deadline.difference(DateTime.now());
    final code = await process.exitCode.timeout(
      left.isNegative ? Duration.zero : left,
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    // A killed process is gone when the call returns, so the next run never
    // overlaps it.
    if (timedOut) {
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
    // The output ends with the process; a child that kept the pipes open
    // does not hold the call.
    await streams.timeout(
      const Duration(seconds: 5),
      onTimeout: () => const [],
    );
    if (timedOut) {
      throw FirewallUnavailable(
        'the firewall did not answer within ${timeout.inSeconds} s'
        '${_progress(err.bytes)}',
      );
    }
    final text = utf8.decode(out.bytes, allowMalformed: true).trim();
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, Object?>) {
      final detail = utf8.decode(err.bytes, allowMalformed: true).trim();
      throw FirewallUnavailable(
        'PowerShell ended with code $code and no answer'
        '${detail.isEmpty ? '' : ': ${_oneLine(detail)}'}',
      );
    }
    if (decoded['error'] case final String message) {
      throw FirewallUnavailable(message);
    }
    return decoded;
  }

  /// The last progress lines the script wrote, so a hang says where it was.
  static String _progress(List<int> stderr) {
    final lines = const LineSplitter()
        .convert(utf8.decode(stderr, allowMalformed: true))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return ' (it wrote no progress)';
    final tail = lines.skip(lines.length > 3 ? lines.length - 3 : 0);
    return ' (last progress: ${_oneLine(tail.join(' | '))})';
  }

  static String _oneLine(String text) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ');
    return line.length > 300 ? '${line.substring(0, 300)}...' : line;
  }
}

/// Collects output up to [_maxOutputBytes].
class _Capture {
  final bytes = <int>[];

  void add(List<int> chunk) {
    if (bytes.length < _maxOutputBytes) bytes.addAll(chunk);
  }
}
