// A stand-in for SteamCMD that replays recorded output from `output/`. It only
// uses dart:core, dart:io and dart:async, so `dart fake_steamcmd.dart <args>`
// runs it anywhere.
//
// Like SteamCMD it takes `+commands` and stops at `+quit`; without `+quit` it
// would wait for input on stdin. What it does is set through the environment:
//
// FAKE_STEAMCMD_RECORD       file that gets one JSON line per run: the
//                            arguments, the pid and whether stdin was closed
// FAKE_STEAMCMD_TRANSCRIPT   output file to replay for `+app_update`
//                            (default update_ok.txt)
// FAKE_STEAMCMD_EXIT         exit code after the replay (default 0)
// FAKE_STEAMCMD_FIRST_TRANSCRIPT  replayed instead, with exit code
//                            FAKE_STEAMCMD_FIRST_EXIT (default 0), by the first
//                            `+app_update` run, the one that creates the file
//                            FAKE_STEAMCMD_FIRST_MARKER
// FAKE_STEAMCMD_DELAY_MS     pause between lines (default 5)
// FAKE_STEAMCMD_STALL_AFTER  print this many lines, then hang until killed
// FAKE_STEAMCMD_HOLD_FILE    after the first progress line, wait while this
//                            file exists
// FAKE_STEAMCMD_LOOP         keep repeating progress lines until killed
// FAKE_STEAMCMD_APP_BYTES    size of the app file written on success
//                            (default 4096)
//
// Workshop downloads (`+workshop_download_item <app> <item>`, any number):
// like SteamCMD the content lands in
// `<root>/steamapps/workshop/content/<app>/<item>/`, where <root> is the
// `+force_install_dir` directory if one was given before the command and else
// the SteamCMD installation directory, modelled here by the working directory
// (a real SteamCMD uses its own folder; the fake lives in the source tree).
// Per item <id>:
// FAKE_STEAMCMD_ITEM_<id>           outcome: ok (default), failure, not_found,
//                            access_denied, no_connection, timeout, stall
//                            (hang after "Downloading item")
// FAKE_STEAMCMD_ITEM_<id>_SOURCE    directory copied into the item folder
//                            instead of the generated files
// FAKE_STEAMCMD_ITEM_<id>_BYTES     size of the generated addons/<id>.pbo
//                            (default 1024); the generated files are also
//                            meta.cpp and keys/<id>.bikey
// FAKE_STEAMCMD_ITEM_<id>_JUNCTION  directory a reparse point `linked` inside
//                            the item points to (a junction on Windows)
// FAKE_STEAMCMD_WORKSHOP_PROGRESS   print progress lines (modelled) per item
// FAKE_STEAMCMD_ECHO_ARGV           first output line echoes the arguments
//
// Login scripts: FAKE_STEAMCMD_LOGIN_SCRIPT names a JSON file
// `{"rules":[{"argc":N,"user":"name","lines":[...],"exit":N,"stall":true}],
// "default":{...}}`. The first rule whose `argc` (number of arguments after
// `+login`) and `user` (both optional) match prints its `lines`, then hangs
// (`stall`), exits with `exit`, or carries on if it has neither. A rule with
// `"scenario": "<name>"` plays that bundled transcript instead (see below).
//
// Login transcripts: FAKE_STEAMCMD_LOGIN=<name> replaces SteamCMD's reply to
// `+login <user> ...`. The lines are the spike's
// (docs/spikes/m3-steam-guard.md); those marked "modelled" use the unverified
// wording of steam/patterns.yaml:
//   email_code_asked    Guard email prompt, exit 5
//   code_accepted       `Steam Guard code provided.`, the OK line, exit 0
//   mobile_approved     the three mobile lines, FAKE_STEAMCMD_APPROVAL_DELAY_MS
//                       (default 100) of waiting, then the OK line, exit 0
//   mobile_never        the three mobile lines, then waits until killed
//   cached_ok           `Logging in using cached credentials.`, OK, exit 0
//   cached_missing      `Cached credentials not found.`, `password:`,
//                       `ERROR (Invalid Password)`, exit 5
//   wrong_password      modelled: `ERROR (Invalid Password)`, exit 5
//   rate_limit          modelled: `ERROR (Rate Limit Exceeded)`, exit 5
//   wrong_code          modelled: `ERROR (Invalid Login Auth Code)`, exit 5
//   authenticator_code  modelled: `Two-factor code:`, exit 5
// After an exit-0 transcript the run goes on with any `+app_update` or
// `+workshop_download_item` in the command line.
//
// SteamCMD's output timing (design D15): with FAKE_STEAMCMD_REAL_OUTPUT set
//  - stdout shows only the two banner lines at the start; every other line is
//    held back and written when the process exits (a killed run loses them);
//  - `logs/console_log.txt` (under the working directory) gets each line the
//    moment it is "printed", prefixed `[YYYY-MM-DD hh:mm:ss] `, progress lines
//    included;
//  - a mobile approval appends `[ts] Waiting for confirmation` to
//    `logs/connection_log.txt` every FAKE_STEAMCMD_WAITING_MS (default 5000),
//    the first at once.
// Without it every line goes to stdout at once and no log is written (what the
// install tests rely on). Independent of that switch:
// FAKE_STEAMCMD_ROTATE_LOGS  `rotate` renames each existing log to
//                            `<name>_prev.txt`, `truncate` empties it, at start
// FAKE_STEAMCMD_SILENT       neither exit nor write anything until killed
//
// On Windows every run also writes the window station and desktop it runs on
// (`Station\Desktop`) to `desktop.txt` next to the executable, if it can.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../desktop_name.dart';

const _bannerLines = [
  'Steam Console Client (c) Valve Corporation - version 1730000000',
  "-- type 'quit' to exit --",
];

/// Stdout and the live logs (see the header, "output timing").
class _Out {
  _Out({required this.realOutput});

  final bool realOutput;
  final _held = <String>[];
  var _bannerShown = false;

  static String _stamp() {
    final n = DateTime.now();
    String t(int v, [int w = 2]) => '$v'.padLeft(w, '0');
    return '[${t(n.year, 4)}-${t(n.month)}-${t(n.day)} '
        '${t(n.hour)}:${t(n.minute)}:${t(n.second)}] ';
  }

  /// Appends a timestamped line to `logs/<name>` and flushes it.
  void log(String name, String line) {
    if (!realOutput) return;
    File('${Directory.current.path}/logs/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '${_stamp()}$line\n',
        mode: FileMode.append,
        flush: true,
      );
  }

  /// The banner is the only stdout SteamCMD shows while it runs.
  Future<void> banner() async {
    if (!realOutput || _bannerShown) return;
    _bannerShown = true;
    for (final line in _bannerLines) {
      stdout.writeln(line);
      log('console_log.txt', line);
    }
    await stdout.flush();
  }

  /// One line SteamCMD "prints".
  Future<void> line(String line) async {
    if (!realOutput) {
      stdout.writeln(line);
      return stdout.flush();
    }
    await banner();
    if (_bannerLines.contains(line)) return;
    _held.add(line);
    log('console_log.txt', line);
  }

  /// The end of the process: the held lines reach stdout now.
  Future<void> quit(int code) async {
    _held.forEach(stdout.writeln);
    await stdout.flush();
    exit(code);
  }
}

late _Out _out;

void _rotateLogs(String mode) {
  for (final name in ['console_log', 'connection_log']) {
    final file = File('${Directory.current.path}/logs/$name.txt');
    if (!file.existsSync()) continue;
    if (mode == 'rotate') {
      file.renameSync('${file.parent.path}/${name}_prev.txt');
    } else {
      file.writeAsStringSync('');
    }
  }
}

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final here = File.fromUri(Platform.script).parent.path;

  // Closed stdin ends at once; an open pipe would block here.
  var stdinClosed = true;
  try {
    await stdin.drain<void>().timeout(const Duration(milliseconds: 150));
  } on TimeoutException {
    stdinClosed = false;
  } on Object {
    // A closed handle may report an error: still closed.
  }

  String? installDir;
  String? login;
  final loginArgs = <String>[];
  final workshop = <(String, String, String?)>[];
  int? appId;
  var validate = false;
  String? beta;
  var quit = false;
  for (var i = 0; i < args.length && !quit; i++) {
    switch (args[i]) {
      case '+force_install_dir':
        installDir = args[++i];
      case '+login':
        login = args[++i];
        loginArgs.clear();
        while (i + 1 < args.length && !args[i + 1].startsWith('+')) {
          loginArgs.add(args[++i]);
        }
      case '+workshop_download_item':
        workshop.add((args[++i], args[++i], installDir));
      case '+app_update':
        appId = int.parse(args[++i]);
        while (i + 1 < args.length && !args[i + 1].startsWith('+')) {
          final flag = args[++i];
          if (flag == 'validate') validate = true;
          if (flag == '-beta') beta = args[++i];
        }
      case '+quit':
        quit = true;
    }
  }

  // Only the compiled fixture records it: a run from source would write into
  // the source tree.
  final compiled = Platform.script.path.toLowerCase().endsWith('.exe');
  if (compiled) {
    if (currentDesktopName() case final desktop?) {
      try {
        File('$here/desktop.txt').writeAsStringSync(desktop);
      } on Object {
        // A folder it cannot write to: nothing to record.
      }
    }
  }

  final record = env['FAKE_STEAMCMD_RECORD'];
  if (record != null) {
    File(record).writeAsStringSync(
      '${jsonEncode({'pid': pid, 'args': args, 'stdinClosed': stdinClosed, 'cwd': Directory.current.path, 'login': login, 'appId': appId, 'validate': validate, 'beta': beta})}\n',
      mode: FileMode.append,
    );
  }

  if (env['FAKE_STEAMCMD_SILENT'] != null) {
    await Future<void>.delayed(const Duration(days: 1));
  }
  if (env['FAKE_STEAMCMD_ROTATE_LOGS'] case final mode?) _rotateLogs(mode);
  _out = _Out(realOutput: env['FAKE_STEAMCMD_REAL_OUTPUT'] != null);
  await _out.banner();

  final delay = Duration(
    milliseconds: int.tryParse(env['FAKE_STEAMCMD_DELAY_MS'] ?? '') ?? 5,
  );
  Future<void> say(String line) async {
    await _out.line(line);
    await Future<void>.delayed(delay);
  }

  if (env['FAKE_STEAMCMD_ECHO_ARGV'] != null) {
    await say('Command line: ${args.join(' ')}');
  }
  if (login != null) {
    final rule = env['FAKE_STEAMCMD_LOGIN_SCRIPT'] == null
        ? null
        : _loginRule(
            File(env['FAKE_STEAMCMD_LOGIN_SCRIPT']!),
            login,
            loginArgs.length + 1,
          );
    final scenario =
        (rule?['scenario'] as String?) ?? env['FAKE_STEAMCMD_LOGIN'];
    if (scenario != null) {
      final code = await _loginScenario(scenario, login, env, say);
      if (code != 0 || (appId == null && workshop.isEmpty)) {
        await _out.quit(code);
      }
    } else if (rule != null) {
      for (final line in (rule['lines'] as List<Object?>? ?? const [])) {
        await say('$line');
      }
      if (rule['stall'] == true) {
        await Future<void>.delayed(const Duration(days: 1));
      }
      if (rule['exit'] case final int code) await _out.quit(code);
    }
  }

  if (workshop.isNotEmpty) {
    await _workshop(workshop, login, env, say);
    final code = int.tryParse(env['FAKE_STEAMCMD_EXIT'] ?? '') ?? 0;
    if (!quit) await _waitForInput(stdinClosed);
    await _out.quit(code);
  }

  if (appId == null) {
    for (final line in File('$here/output/selfupdate.txt').readAsLinesSync()) {
      await say(line);
    }
    if (!quit) await _waitForInput(stdinClosed);
    await _out.quit(0);
  }

  var transcript = env['FAKE_STEAMCMD_TRANSCRIPT'] ?? 'update_ok.txt';
  int? firstExit;
  final firstMarker = env['FAKE_STEAMCMD_FIRST_MARKER'];
  if (env['FAKE_STEAMCMD_FIRST_TRANSCRIPT'] case final first?
      when firstMarker != null && !File(firstMarker).existsSync()) {
    File(firstMarker).writeAsStringSync('');
    transcript = first;
    firstExit = int.tryParse(env['FAKE_STEAMCMD_FIRST_EXIT'] ?? '') ?? 0;
  }
  final lines = File('$here/output/$transcript').readAsLinesSync();
  final stallAfter = int.tryParse(env['FAKE_STEAMCMD_STALL_AFTER'] ?? '');
  final holdFile = env['FAKE_STEAMCMD_HOLD_FILE'];
  var printed = 0;
  var held = false;
  for (final template in lines) {
    final line = template
        .replaceAll('{app_id}', '$appId')
        .replaceAll('{dir}', installDir ?? '');
    await say(line);
    printed++;
    if (stallAfter != null && printed >= stallAfter) {
      await Future<void>.delayed(const Duration(days: 1));
    }
    if (!held && holdFile != null && line.contains('progress:')) {
      held = true;
      while (File(holdFile).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }
  if (env['FAKE_STEAMCMD_LOOP'] != null) {
    for (var bytes = 0; ; bytes += 100) {
      await say(
        ' Update state (0x61) downloading, progress: 50.00 ($bytes / 99999)',
      );
    }
  }

  final exitWith =
      firstExit ?? int.tryParse(env['FAKE_STEAMCMD_EXIT'] ?? '') ?? 0;
  if (exitWith == 0 && installDir != null) {
    final bytes = int.tryParse(env['FAKE_STEAMCMD_APP_BYTES'] ?? '') ?? 4096;
    File('$installDir/steamapps/appmanifest_$appId.acf')
      ..createSync(recursive: true)
      ..writeAsStringSync('"AppState" { "appid" "$appId" }');
    File('$installDir/app_$appId.bin').writeAsBytesSync(List.filled(bytes, 7));
  }
  if (!quit) await _waitForInput(stdinClosed);
  await _out.quit(exitWith);
}

/// Without `+quit` SteamCMD sits at its prompt until stdin ends.
Future<void> _waitForInput(bool stdinClosed) async {
  await _out.line('Steam>');
  if (stdinClosed) await _out.quit(0);
  await Future<void>.delayed(const Duration(days: 1));
}

/// Replies to `+login` with the transcript [name] (see the header) and returns
/// the exit code.
Future<int> _loginScenario(
  String name,
  String user,
  Map<String, String> env,
  Future<void> Function(String) say,
) async {
  final loggedIn = "Logging in user '$user' [U:1:0] to Steam Public...OK";
  final attempt = "Logging in user '$user' [U:1:0] to Steam Public...";
  Future<void> all(Iterable<String> lines) async {
    for (final line in lines) {
      await say(line);
    }
  }

  switch (name) {
    case 'email_code_asked':
      await all([
        'This computer has not been authenticated for your account using '
            'Steam Guard.',
        'Please check your email for the message from Steam, and enter the '
            'Steam Guard',
        'Steam Guard code:ERROR (Account Logon Denied)',
      ]);
      _out.log(
        'connection_log.txt',
        'cannot call UpdateAuthSessionWithSteamGuardCode because we do not '
            'have a code available',
      );
      _out.log('connection_log.txt', "'Account Logon Denied'");
      return 5;
    case 'code_accepted':
      await all(['Steam Guard code provided.', loggedIn]);
      await say('Waiting for user info...OK');
      return 0;
    case 'mobile_approved' || 'mobile_never':
      await all([
        'This account is protected by a Steam Guard mobile authenticator.',
        'Please confirm the login in the Steam Mobile app on your phone.',
        'Waiting for confirmation...',
      ]);
      final every = Duration(
        milliseconds:
            int.tryParse(env['FAKE_STEAMCMD_WAITING_MS'] ?? '') ?? 5000,
      );
      final approval = name == 'mobile_never'
          ? null
          : Duration(
              milliseconds:
                  int.tryParse(env['FAKE_STEAMCMD_APPROVAL_DELAY_MS'] ?? '') ??
                  100,
            );
      final watch = Stopwatch()..start();
      while (approval == null || watch.elapsed < approval) {
        _out.log('connection_log.txt', 'Waiting for confirmation');
        final left = approval == null ? every : approval - watch.elapsed;
        await Future<void>.delayed(left < every ? left : every);
      }
      _out.log(
        'connection_log.txt',
        'PollAuthSessionStatus succeeded and has refresh token',
      );
      await all([loggedIn, 'Waiting for user info...OK']);
      return 0;
    case 'cached_ok':
      await all(['Logging in using cached credentials.', loggedIn]);
      return 0;
    case 'cached_missing':
      await all([
        'Logging in using cached credentials.',
        'Cached credentials not found.',
        'password:',
        'ERROR (Invalid Password)',
      ]);
      return 5;
    case 'wrong_password':
      await all([attempt, 'ERROR (Invalid Password)']);
      return 5;
    case 'rate_limit':
      await all([attempt, 'ERROR (Rate Limit Exceeded)']);
      return 5;
    case 'wrong_code':
      await all([
        'Steam Guard code provided.',
        'ERROR (Invalid Login Auth Code)',
      ]);
      return 5;
    case 'authenticator_code':
      await say('Two-factor code:');
      return 5;
  }
  throw ArgumentError('unknown login transcript: $name');
}

/// The first rule of a login script that matches, or its `default`.
Map<String, Object?>? _loginRule(File script, String user, int argc) {
  final json = jsonDecode(script.readAsStringSync()) as Map<String, Object?>;
  for (final rule in (json['rules'] as List<Object?>? ?? const [])) {
    final r = rule as Map<String, Object?>;
    if (r['argc'] case final int n when n != argc) continue;
    if (r['user'] case final String u when u != user) continue;
    return r;
  }
  return json['default'] as Map<String, Object?>?;
}

/// Runs the `+workshop_download_item` commands in order. The wording of the
/// `Downloading item` / `Success. Downloaded item` / `ERROR! Download item`
/// lines follows what SteamCMD prints; it is modelled from memory of real logs,
/// not recorded here, so the exact trailing text may differ.
Future<void> _workshop(
  List<(String, String, String?)> items,
  String? login,
  Map<String, String> env,
  Future<void> Function(String) say,
) async {
  for (final line in _bannerLines) {
    await say(line);
  }
  await say('Loading Steam API...OK');
  await say(
    login == null || login == 'anonymous'
        ? 'Connecting anonymously to Steam Public...OK'
        : "Logging in user '$login' to Steam Public...OK",
  );
  await say('Waiting for client config...OK');
  await say('Waiting for user info...OK');
  for (final (app, item, forced) in items) {
    final root = forced ?? Directory.current.path;
    final dir = Directory(
      [
        root,
        'steamapps',
        'workshop',
        'content',
        app,
        item,
      ].join(Platform.pathSeparator),
    );
    final outcome = env['FAKE_STEAMCMD_ITEM_$item'] ?? 'ok';
    await say('Downloading item $item ...');
    if (env['FAKE_STEAMCMD_WORKSHOP_PROGRESS'] != null) {
      for (final pct in ['0.00', '50.00', '100.00']) {
        await say(' Update state (0x61) downloading, progress: $pct');
      }
    }
    switch (outcome) {
      case 'stall':
        await Future<void>.delayed(const Duration(days: 1));
      case 'failure':
        await say('ERROR! Download item $item failed (Failure).');
      case 'not_found':
        await say('ERROR! Download item $item failed (File Not Found).');
      case 'access_denied':
        await say('ERROR! Download item $item failed (Access Denied).');
      case 'no_connection':
        await say('ERROR! Download item $item failed (No Connection).');
      case 'timeout':
        await say('ERROR! Download item $item failed (Timeout).');
      default:
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
        if (env['FAKE_STEAMCMD_ITEM_${item}_SOURCE'] case final source?) {
          _copy(Directory(source), dir);
        } else {
          final bytes =
              int.tryParse(env['FAKE_STEAMCMD_ITEM_${item}_BYTES'] ?? '') ??
              1024;
          File('${dir.path}/meta.cpp')
            ..createSync(recursive: true)
            ..writeAsStringSync('protocol = 1;\npublishedid = $item;\n');
          File('${dir.path}/keys/$item.bikey')
            ..createSync(recursive: true)
            ..writeAsBytesSync(List.filled(16, 3));
          File('${dir.path}/addons/$item.pbo')
            ..createSync(recursive: true)
            ..writeAsBytesSync(List.filled(bytes, 7));
        }
        if (env['FAKE_STEAMCMD_ITEM_${item}_JUNCTION'] case final target?) {
          Link('${dir.path}/linked').createSync(target);
        }
        var total = 0;
        for (final e in dir.listSync(recursive: true, followLinks: false)) {
          if (e is File) total += e.lengthSync();
        }
        await say(
          'Success. Downloaded item $item to "${dir.path}" ($total bytes)',
        );
    }
  }
}

void _copy(Directory from, Directory to) {
  for (final e in from.listSync(recursive: true, followLinks: false)) {
    final rel = e.path.substring(from.path.length);
    if (e is Directory) {
      Directory('${to.path}$rel').createSync(recursive: true);
    } else if (e is File) {
      File('${to.path}$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(e.readAsBytesSync());
    }
  }
}
