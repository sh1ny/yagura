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
// On Windows every run also writes the window station and desktop it runs on
// (`Station\Desktop`) to `desktop.txt` next to the executable, if it can.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../desktop_name.dart';

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

  final delay = Duration(
    milliseconds: int.tryParse(env['FAKE_STEAMCMD_DELAY_MS'] ?? '') ?? 5,
  );
  Future<void> say(String line) async {
    stdout.writeln(line);
    await stdout.flush();
    await Future<void>.delayed(delay);
  }

  if (appId == null) {
    for (final line in File('$here/output/selfupdate.txt').readAsLinesSync()) {
      await say(line);
    }
    if (!quit) await _waitForInput(stdinClosed);
    return;
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
  exit(exitWith);
}

/// Without `+quit` SteamCMD sits at its prompt until stdin ends.
Future<void> _waitForInput(bool stdinClosed) async {
  stdout.writeln('Steam>');
  if (stdinClosed) exit(0);
  await Future<void>.delayed(const Duration(days: 1));
}
