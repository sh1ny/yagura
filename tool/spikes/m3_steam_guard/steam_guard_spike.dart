// Throwaway spike for M3 task 1.1 (design A1): how SteamCMD behaves on a
// Steam Guard login with stdin on NUL, and whether it writes the password
// into its own files. Uses no packages; run it from the repository root:
//
//   dart run tool/spikes/m3_steam_guard/steam_guard_spike.dart <scenario> \
//       --dir <empty folder for a fresh SteamCMD> --out <folder for results>
//
// Scenarios, run in this order once per Guard kind (email code,
// authenticator code, mobile approval):
//   bootstrap  download SteamCMD into --dir and let it self-update
//   guard      +login <user> <pass> +quit; if it asks for a code, asks you
//              for it and runs +login <user> <pass> <code> +quit
//   cached     +login <user> +quit, with the cached login from `guard`
//   expired    +login <user> +quit after you removed the cached login
//              (delete <dir>/config/config.vdf, or deauthorise the device on
//              the Steam website, before running it)
//   install    once, anonymous: +force_install_dir <dir>/app +login
//              anonymous +app_update <--app> +quit, to see whether download
//              progress reaches the pipe while the run lives
//   workshop   optional, once: +login <user, cached> (or anonymous)
//              +workshop_download_item <app> <item> per item +quit, to record
//              SteamCMD's real workshop output. Pass --app 221100 --items
//              <id>,<id> (one small item and one id that does not exist)
//
// Whether the account owns DayZ is not needed for the Guard scenarios; the
// workshop scenario needs an account that may download from --app.
//
// The password and the code are read from the console with echo off and live
// only in this process's memory. They are never written: every transcript
// line is scrubbed (password, code and username replaced) before it is
// stored. After each run every file under --dir is scanned for the password
// and the code (UTF-8 and UTF-16LE); the report names the files, never their
// content. Send the --out folder back; it holds nothing secret.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How long a run may live before the spike kills it. Long enough to see
/// whether a mobile approval completes inside the same run, and whether an
/// expired login loops.
const runLimit = Duration(minutes: 3);

Future<void> main(List<String> args) async {
  if (args.isEmpty) _usage();
  final scenario = args.first;
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final dir = option('--dir') ?? _usage();
  final out = option('--out') ?? _usage();
  Directory(out).createSync(recursive: true);
  final steamcmd = '$dir${Platform.pathSeparator}steamcmd.exe';

  switch (scenario) {
    case 'bootstrap':
      await _bootstrap(dir, steamcmd, out);
    case 'guard':
      final user = _ask('Steam username: ');
      final password = _ask('Password (not shown): ', hidden: true);
      final scrub = _Scrubber(user: user, secrets: [password]);
      final first = await _run(
        'guard-1',
        steamcmd,
        ['+login', user, password, '+quit'],
        dir: dir,
        out: out,
        scrub: scrub,
        scanFor: [password],
      );
      stdout.writeln(
        '\nIf SteamCMD asked for a Steam Guard code (email or authenticator), '
        'enter it now. For a mobile approval that already completed, or no '
        'prompt at all, press Enter.',
      );
      final code = _ask('Code (blank to skip): ', hidden: true);
      if (code.isNotEmpty) {
        scrub.secrets.add(code);
        await _run(
          'guard-2-with-code',
          steamcmd,
          ['+login', user, password, code, '+quit'],
          dir: dir,
          out: out,
          scrub: scrub,
          scanFor: [password, code],
        );
      }
      stdout.writeln(
        '\nFirst run exit: ${first.exitCode}, killed: ${first.killed}',
      );
    case 'cached':
    case 'expired':
      final user = _ask('Steam username: ');
      final password = _ask(
        'Password, only to scan files for it (not passed to SteamCMD, not shown): ',
        hidden: true,
      );
      await _run(
        scenario,
        steamcmd,
        ['+login', user, '+quit'],
        dir: dir,
        out: out,
        scrub: _Scrubber(user: user, secrets: [password]),
        scanFor: [password],
      );
    case 'install':
      final app = option('--app') ?? _usage();
      await _run(
        'install',
        steamcmd,
        [
          '+force_install_dir',
          '$dir${Platform.pathSeparator}app',
          '+login',
          'anonymous',
          '+app_update',
          app,
          '+quit',
        ],
        dir: dir,
        out: out,
        scrub: _Scrubber(user: '', secrets: []),
        scanFor: [],
        limit: const Duration(minutes: 15),
      );
    case 'workshop':
      final app = option('--app') ?? _usage();
      final items = (option('--items') ?? _usage()).split(',');
      final user = _ask('Steam username (blank for anonymous): ');
      await _run(
        'workshop',
        steamcmd,
        [
          '+login',
          if (user.isEmpty) 'anonymous' else user,
          for (final item in items) ...['+workshop_download_item', app, item],
          '+quit',
        ],
        dir: dir,
        out: out,
        scrub: _Scrubber(user: user, secrets: []),
        scanFor: [],
      );
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln(
    'usage: steam_guard_spike.dart bootstrap|guard|cached|expired|install|workshop '
    '--dir <steamcmd folder> --out <results folder> '
    '[--app <id> --items <id,id>]',
  );
  exit(64);
}

String _ask(String prompt, {bool hidden = false}) {
  stdout.write(prompt);
  if (hidden) stdin.echoMode = false;
  try {
    return (stdin.readLineSync() ?? '').trim();
  } finally {
    if (hidden) {
      stdin.echoMode = true;
      stdout.writeln();
    }
  }
}

Future<void> _bootstrap(String dir, String steamcmd, String out) async {
  Directory(dir).createSync(recursive: true);
  if (!File(steamcmd).existsSync()) {
    final zip = '$dir${Platform.pathSeparator}steamcmd.zip';
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip',
        ),
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('download failed: HTTP ${response.statusCode}');
      }
      await response.pipe(File(zip).openWrite());
    } finally {
      client.close();
    }
    final unpack = await Process.run('tar', ['-xf', zip, '-C', dir]);
    if (unpack.exitCode != 0) throw StateError('tar: ${unpack.stderr}');
    File(zip).deleteSync();
  }
  await _run(
    'bootstrap',
    steamcmd,
    ['+quit'],
    dir: dir,
    out: out,
    scrub: _Scrubber(user: '', secrets: []),
    scanFor: [],
  );
}

class _Scrubber {
  _Scrubber({required this.user, required this.secrets});
  final String user;
  final List<String> secrets;

  String call(String line) {
    var result = line;
    for (final s in secrets) {
      if (s.isNotEmpty) result = result.replaceAll(s, '***');
    }
    if (user.isNotEmpty) result = result.replaceAll(user, '<user>');
    return result;
  }
}

class _RunResult {
  _RunResult(this.exitCode, this.killed);
  final int? exitCode;
  final bool killed;
}

/// Runs SteamCMD with stdin closed at once, as the console-mode daemon runs
/// it (the service-mode daemon passes NUL; both read end-of-file). Not through
/// `cmd /c ... < NUL`: cmd would re-parse `&`, `|` or `^` in a password.
/// Records every output line with its offset from the start, kills
/// the tree after [limit], then scans [dir] for [scanFor].
Future<_RunResult> _run(
  String name,
  String steamcmd,
  List<String> arguments, {
  required String dir,
  required String out,
  required _Scrubber scrub,
  required List<String> scanFor,
  Duration limit = runLimit,
}) async {
  stdout.writeln('\n== $name: steamcmd ${arguments.map(scrub.call).join(' ')}');
  final started = DateTime.now();
  final process = await Process.start(
    steamcmd,
    arguments,
    workingDirectory: dir,
  );
  await process.stdin.close();
  final transcript = <String>[];
  void record(String stream, String line) {
    final at = DateTime.now().difference(started).inMilliseconds / 1000;
    final clean = scrub(line);
    final entry = '[${at.toStringAsFixed(1).padLeft(6)}s $stream] $clean';
    transcript.add(entry);
    stdout.writeln(entry);
  }

  final done = <Future<void>>[
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((l) => record('out', l)),
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((l) => record('err', l)),
  ];
  // SteamCMD's stdout reaches a pipe only at exit, so also watch its own log
  // files and record when each new line first appears on disk ('log' lines):
  // that shows whether a log is a live signal while the run waits.
  final watched = {
    for (final name in [
      'connection_log.txt',
      'console_log.txt',
      'content_log.txt',
    ])
      '$dir${Platform.pathSeparator}logs${Platform.pathSeparator}$name': -1,
  };
  void poll() {
    for (final path in watched.keys) {
      final List<int> bytes;
      try {
        bytes = File(path).readAsBytesSync();
      } on FileSystemException {
        continue;
      }
      final seen = watched[path]!;
      // The first look only notes the size: earlier runs wrote that part.
      if (seen >= 0 && bytes.length > seen) {
        final text = utf8.decode(bytes.sublist(seen), allowMalformed: true);
        for (final line in const LineSplitter().convert(text)) {
          if (line.isNotEmpty) record('log', line);
        }
      }
      watched[path] = bytes.length;
    }
  }

  poll();
  final watcher = Timer.periodic(
    const Duration(milliseconds: 250),
    (_) => poll(),
  );
  var killed = false;
  int? exitCode;
  try {
    exitCode = await process.exitCode.timeout(limit);
  } on TimeoutException {
    killed = true;
    await Process.run('taskkill', ['/T', '/F', '/PID', '${process.pid}']);
    exitCode = await process.exitCode;
  }
  watcher.cancel();
  poll();
  await Future.wait(done);
  final seconds = DateTime.now().difference(started).inMilliseconds / 1000;

  final hits = _scan(dir, scanFor);
  final report = StringBuffer()
    ..writeln('scenario: $name')
    ..writeln('started: ${started.toIso8601String()}')
    ..writeln('arguments: ${arguments.map(scrub.call).join(' ')}')
    ..writeln('stdin: closed (end-of-file)')
    ..writeln('duration_seconds: $seconds')
    ..writeln('exit_code: $exitCode')
    ..writeln('killed_after_${limit.inMinutes}_minutes: $killed')
    ..writeln('files_scanned: ${hits.scanned}')
    ..writeln('files_holding_a_secret:')
    ..writeAll(hits.files.map((f) => '  - $f\n'))
    ..writeln('transcript:')
    ..writeAll(transcript.map((l) => '  $l\n'));
  final file = File('$out${Platform.pathSeparator}$name.txt');
  file.writeAsStringSync(report.toString());
  stdout.writeln(
    '\n== $name: exit $exitCode, killed $killed, ${seconds}s; '
    '${hits.files.length} of ${hits.scanned} files hold a secret; '
    'report: ${file.path}',
  );
  return _RunResult(exitCode, killed);
}

class _ScanResult {
  _ScanResult(this.scanned, this.files);
  final int scanned;
  final List<String> files;
}

_ScanResult _scan(String dir, List<String> secrets) {
  final needles = [
    for (final s in secrets)
      if (s.isNotEmpty) ...[
        utf8.encode(s),
        [
          for (final unit in s.codeUnits) ...[unit & 0xff, unit >> 8],
        ],
      ],
  ];
  var scanned = 0;
  final files = <String>[];
  for (final entity in Directory(
    dir,
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    scanned++;
    if (needles.isEmpty) continue;
    final List<int> bytes;
    try {
      bytes = entity.readAsBytesSync();
    } on FileSystemException {
      files.add('${entity.path} (unreadable)');
      continue;
    }
    if (needles.any((n) => _contains(bytes, n))) {
      files.add(entity.path.substring(dir.length));
    }
  }
  return _ScanResult(scanned, files);
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
