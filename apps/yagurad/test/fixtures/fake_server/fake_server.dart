// A small game-server stand-in for the process tests (task 5.1). It logs to
// stdout, saves and exits on Ctrl+C, can ignore Ctrl+C, listens on a TCP
// port, and crashes on command.
//
//   --state-dir <dir>    where it writes pid.txt and saved.txt and looks for
//                        a `crash` command file (its content is the exit code)
//   --ignore-ctrl-c      log Ctrl+C but keep running
//   --exit-after-ms <n>  exit by itself after n ms ...
//   --exit-code <c>      ... with this code (default 0)
//   --listen <port>      accept TCP connections on 127.0.0.1:port
//   --flood-mb <n>       write n MiB of log lines before getting ready
//   --ready-delay-ms <n> wait before printing the ready line
//   --save-ms <n>        time Ctrl+C handling takes before it exits (default
//                        200); ctrlc.txt is written when Ctrl+C arrives
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  String? stateDir;
  var ignoreCtrlC = false;
  int? exitAfterMs;
  var exitCode = 0;
  int? listenPort;
  var floodMb = 0;
  var readyDelayMs = 0;
  var saveMs = 200;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--state-dir':
        stateDir = args[++i];
      case '--ignore-ctrl-c':
        ignoreCtrlC = true;
      case '--exit-after-ms':
        exitAfterMs = int.parse(args[++i]);
      case '--exit-code':
        exitCode = int.parse(args[++i]);
      case '--listen':
        listenPort = int.parse(args[++i]);
      case '--flood-mb':
        floodMb = int.parse(args[++i]);
      case '--ready-delay-ms':
        readyDelayMs = int.parse(args[++i]);
      case '--save-ms':
        saveMs = int.parse(args[++i]);
    }
  }

  void say(String line) {
    stdout.writeln(line);
  }

  if (stateDir != null) {
    Directory(stateDir).createSync(recursive: true);
    File('$stateDir/pid.txt').writeAsStringSync('$pid');
    File('$stateDir/cwd.txt').writeAsStringSync(Directory.current.path);
    File('$stateDir/args.txt').writeAsStringSync(args.join('\n'));
  }
  say('fake_server starting pid=$pid');

  var floodLine = 0;
  while (floodMb > 0 && floodLine < floodMb * 1024 * 1024 ~/ 100) {
    say('flood ${(floodLine++).toString().padLeft(8, '0')} ${'x' * 80}');
  }

  if (listenPort != null) {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      listenPort,
    );
    server.listen((socket) => socket.destroy());
  }

  ProcessSignal.sigint.watch().listen((_) async {
    if (ignoreCtrlC) {
      say('ctrl-c ignored');
      return;
    }
    say('ctrl-c received, saving');
    if (stateDir != null) {
      File('$stateDir/ctrlc.txt').writeAsStringSync('ctrl-c');
    }
    await Future<void>.delayed(Duration(milliseconds: saveMs));
    if (stateDir != null) {
      File('$stateDir/saved.txt').writeAsStringSync('saved');
    }
    say('saved, bye');
    await stdout.flush();
    exit(0);
  });

  if (exitAfterMs != null) {
    Timer(Duration(milliseconds: exitAfterMs), () async {
      say('exiting by itself with code $exitCode');
      await stdout.flush();
      exit(exitCode);
    });
  }

  await Future<void>.delayed(Duration(milliseconds: readyDelayMs));
  say('Game server connected');

  var tick = 0;
  Timer.periodic(const Duration(milliseconds: 100), (_) async {
    if (stateDir != null) {
      final command = File('$stateDir/crash');
      if (command.existsSync()) {
        final code = int.tryParse(command.readAsStringSync().trim()) ?? 1;
        say('crashing with code $code');
        await stdout.flush();
        exit(code);
      }
    }
    if (++tick % 10 == 0) say('tick $tick');
  });
}
