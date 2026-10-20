import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/operations/cancel_token.dart';
import 'package:yagurad/src/operations/prompt_broker.dart';
import 'package:yagurad/src/platform/disk_space.dart';
import 'package:yagurad/src/steam/steam.dart';

import 'daemon_support.dart';

/// The fake SteamCMD (`test/fixtures/fake_steamcmd/`).
final fakeSteamCmdScript = p.absolute(
  'test',
  'fixtures',
  'fake_steamcmd',
  'fake_steamcmd.dart',
);

/// App id of the Valheim fixture.
const valheimAppId = 896660;

/// Wraps a launcher and remembers what was started.
class SpyLauncher implements SteamProcessLauncher {
  SpyLauncher([SteamProcessLauncher? inner])
    : _inner = inner ?? SteamProcessLauncher();

  final SteamProcessLauncher _inner;
  final started = <List<String>>[];

  @override
  Future<SteamProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) {
    started.add([executable, ...arguments]);
    return _inner.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  @override
  Future<void> close() => _inner.close();
}

/// A stray control whose terminations can be made to fail.
class FlakyStrayControl implements StrayProcessControl {
  FlakyStrayControl({this.failing = false});

  final _real = StrayProcessControl();
  bool failing;
  final terminated = <StrayProcess>[];

  @override
  Future<List<StrayProcess>> find(String directory) => _real.find(directory);

  @override
  Future<bool> terminate(StrayProcess process) async {
    if (failing) return false;
    final ok = await _real.terminate(process);
    if (ok) terminated.add(process);
    return ok;
  }
}

/// A SteamCMD service wired to the fake SteamCMD inside a [TestEnv]'s data
/// directory, with everything slow or external injectable.
class SteamHarness {
  SteamHarness(
    this.env, {
    Map<String, String> fakeEnvironment = const {},
    Duration noProgressTimeout = const Duration(seconds: 30),
    Duration totalTimeout = const Duration(minutes: 5),
    Duration sweepRetry = const Duration(minutes: 5),
    Duration pollInterval = const Duration(milliseconds: 50),
    SteamCmdBootstrap? bootstrap,
    StrayProcessControl? strays,
    int freeBytes = 1 << 40,
    bool ready = true,
    // The fake writes its logs and holds its output back until it exits, like
    // SteamCMD (design D15).
    bool realOutput = false,
    Duration? codeWait,
    Duration? mobileWait,
    Duration? loginSilence,
    Duration? loginCap,
  }) : _fakeEnvironment = {
         'FAKE_STEAMCMD_RECORD': p.join(env.root.path, 'fake_steamcmd.jsonl'),
         'FAKE_STEAMCMD_LOGIN_SCRIPT': p.join(
           env.root.path,
           'login_script.json',
         ),
         if (realOutput) 'FAKE_STEAMCMD_REAL_OUTPUT': '1',
         ...fakeEnvironment,
       },
       free = freeBytes {
    script = LoginScript(_fakeEnvironment['FAKE_STEAMCMD_LOGIN_SCRIPT']!)
      ..rules([]);
    if (ready) markReady();
    launcher = SpyLauncher();
    service = SteamCmdService(
      steamcmdRoot: root,
      bootstrap: bootstrap,
      command: (_) =>
          SteamCmdCommand(Platform.resolvedExecutable, [fakeSteamCmdScript]),
      launcher: launcher,
      strays: strays,
      diskSpace: (path) async => DiskSpace(volume: 'V:\\', freeBytes: free),
      state: state,
      environment: _fakeEnvironment,
      noProgressTimeout: noProgressTimeout,
      totalTimeout: totalTimeout,
      sweepRetry: sweepRetry,
      pollInterval: pollInterval,
      codeWait: codeWait ?? const Duration(minutes: 15),
      mobileWait: mobileWait ?? const Duration(minutes: 2),
      loginSilence: loginSilence ?? const Duration(seconds: 60),
      loginCap: loginCap ?? const Duration(minutes: 10),
      log: log.add,
    );
    addTearDown(service.close);
  }

  final TestEnv env;
  final Map<String, String> _fakeEnvironment;

  /// What the fake answers to `+login` (see its header).
  late final LoginScript script;

  /// Free bytes the probe reports; change it between runs.
  int free;
  late final SpyLauncher launcher;
  final state = MemorySteamState();
  late final SteamCmdService service;

  /// What the service logged.
  final log = <String>[];

  String get root => p.join(env.data, 'steamcmd');
  String get installation => p.join(root, 'anonymous');

  /// Pretends the installation was bootstrapped already.
  void markReady() {
    Directory(installation).createSync(recursive: true);
    state.markReady(SteamCmdService.anonymousInstallation);
  }

  /// Every run the fake SteamCMD recorded, oldest first.
  List<Map<String, Object?>> runs() {
    final file = File(_fakeEnvironment['FAKE_STEAMCMD_RECORD']!);
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
    ];
  }

  /// The runs that installed an app (not the self-update).
  List<Map<String, Object?>> appRuns() => [
    for (final run in runs())
      if (run['appId'] != null) run,
  ];
}

/// The login script of the fake SteamCMD: a JSON file read at every run, so a
/// test can change the answers between runs.
class LoginScript {
  LoginScript(this.path);

  final String path;

  /// Replaces the rules (see the fake's header).
  void rules(List<Map<String, Object?>> rules) =>
      File(path).writeAsStringSync(jsonEncode({'rules': rules}));
}

/// A bootstrap that only creates the installation directory, so tests of
/// accounts do not unpack an archive for each one.
class DirectoryBootstrap extends SteamCmdBootstrap {
  DirectoryBootstrap();

  @override
  Future<void> install(
    ConfinedFs fs,
    String installation, {
    CancelToken? cancel,
    SteamProcessLauncher? launcher,
  }) async => fs.createDirectory(installation);
}

/// A reporter that records everything a Steam run reports.
class RecordingReporter implements SteamRunReporter {
  final steps = <String>[];
  final progresses = <SteamProgress>[];
  final logs = <String>[];
  final warnings = <String>[];
  final times = <DateTime>[];
  var _step = '';

  @override
  void step(String name) {
    _step = name;
    steps.add(name);
  }

  @override
  void progress({double percent = -1, int bytesDone = 0, int bytesTotal = 0}) {
    progresses.add(
      SteamProgress(
        step: _step,
        percent: percent,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      ),
    );
    times.add(DateTime.now());
  }

  @override
  void log(String text) => logs.add(text);

  @override
  void warn(String warning) => warnings.add(warning);

  /// The prompts the run raised; nobody answers them.
  final prompts = PromptBroker();

  @override
  PromptTicket prompt(PromptSpec spec) =>
      prompts.raise(spec, const PromptSubject(operationId: 'recording'));
}

/// A minimal tar archive (ustar) of [files], so a test can serve something
/// `tar -xf` unpacks on every platform.
List<int> tarArchive(Map<String, List<int>> files) {
  final out = BytesBuilder();
  for (final entry in files.entries) {
    final header = List<int>.filled(512, 0);
    void put(int offset, String text) =>
        header.setRange(offset, offset + text.length, ascii.encode(text));
    put(0, entry.key);
    put(100, '0000755\u0000');
    put(108, '0000000\u0000');
    put(116, '0000000\u0000');
    put(124, '${entry.value.length.toRadixString(8).padLeft(11, '0')}\u0000');
    put(
      136,
      '${(DateTime.now().millisecondsSinceEpoch ~/ 1000).toRadixString(8).padLeft(11, '0')}\u0000',
    );
    put(148, '        ');
    header[156] = 0x30; // regular file
    put(257, 'ustar\u000000');
    final checksum = header.fold<int>(0, (a, b) => a + b);
    put(148, '${checksum.toRadixString(8).padLeft(6, '0')}\u0000 ');
    out
      ..add(header)
      ..add(entry.value)
      ..add(List.filled((512 - entry.value.length % 512) % 512, 0));
  }
  out.add(List.filled(1024, 0));
  return out.toBytes();
}

/// A local server that answers every request with [status] and [body]; stands
/// in for Valve's download server.
Future<HttpServer> serveArchive({
  int status = HttpStatus.ok,
  List<int> body = const [],
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    request.response.statusCode = status;
    request.response.add(body);
    await request.response.close();
  });
  return server;
}
