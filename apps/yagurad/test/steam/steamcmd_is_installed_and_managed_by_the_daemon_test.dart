import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/platform/disk_space.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/daemon_support.dart';
import '../support/steam_account_support.dart';
import '../support/steam_support.dart';

void main() {
  test('first_install_bootstraps_steamcmd', () async {
    final env = TestEnv();
    env.installValheim();
    final server = await serveArchive(
      body: tarArchive({
        'steamcmd.exe': utf8.encode('MZ placeholder'),
        'steamcmd.sh': utf8.encode('#!/bin/sh'),
      }),
    );
    final steam = SteamHarness(
      env,
      ready: false,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
      ),
    );
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(
      File(p.join(steam.installation, 'steamcmd.exe')).existsSync(),
      isTrue,
      reason: 'the archive was unpacked into <data>/steamcmd/anonymous',
    );
    expect(steam.state.isReady('anonymous'), isTrue);
    // The self-update run and its check run (+quit alone) came before the
    // app run.
    final runs = steam.runs();
    expect(runs, hasLength(3));
    for (final run in runs.take(2)) {
      expect((run['args']! as List).last, '+quit');
      expect(run['appId'], isNull);
    }
    expect(runs.last['appId'], valheimAppId);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('a_lost_installation_is_bootstrapped_again', () async {
    final env = TestEnv();
    env.installValheim();
    final server = await serveArchive(
      body: tarArchive({'steamcmd.exe': utf8.encode('MZ placeholder')}),
    );
    // Ready in the database, but the directory was deleted (a manual fix, or
    // damage): ADR 0014 says it is bootstrapped again.
    final steam = SteamHarness(
      env,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
      ),
    );
    Directory(steam.installation).deleteSync(recursive: true);
    expect(steam.state.isReady('anonymous'), isTrue);

    await steam.service.installApp(
      SteamAppRequest(
        appId: valheimAppId,
        installDirectory: p.join(env.root.path, 'server'),
      ),
      RecordingReporter(),
      CancelToken(),
    );

    expect(
      File(p.join(steam.installation, 'steamcmd.exe')).existsSync(),
      isTrue,
      reason: 'the archive was unpacked again',
    );
    expect(steam.state.isReady('anonymous'), isTrue);
    // The self-update run, its check run and the app run.
    expect(steam.runs(), hasLength(3));
  });

  test('an_installation_that_cannot_start_is_not_ready', () async {
    final env = TestEnv();
    final steam = SteamHarness(env);
    final service = SteamCmdService(
      steamcmdRoot: steam.root,
      state: steam.state,
      launcher: _ThrowingLauncher(),
      diskSpace: (path) async => DiskSpace(volume: r'V:', freeBytes: 1 << 40),
      log: (_) {},
    );
    addTearDown(service.close);

    await expectLater(
      service.installApp(
        SteamAppRequest(
          appId: valheimAppId,
          installDirectory: p.join(env.root.path, 'server'),
        ),
        RecordingReporter(),
        CancelToken(),
      ),
      throwsA(isA<ProcessException>()),
    );

    expect(steam.state.isReady('anonymous'), isFalse);
  });

  test('account_installation_bootstrapped', () async {
    final env = TestEnv();
    final server = await serveArchive(
      body: tarArchive({
        'steamcmd.exe': utf8.encode('MZ placeholder'),
        'steamcmd.sh': utf8.encode('#!/bin/sh'),
      }),
    );
    final rig = await AccountRig.start(
      env: env,
      realOutput: false,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
      ),
    );
    rig.steam.script.rules([loginRule(2, 'code_accepted')]);

    final op = await rig.finish((await rig.add('srvadmin')).id);

    expect(op.status, pb.OperationStatus.OPERATION_STATUS_SUCCEEDED);
    final account = await rig.accountNamed('srvadmin');
    final dir = rig.installationOf(account.id);
    expect(account.id, matches(RegExp(r'^acct_[0-9a-f]{12}$')));
    expect(
      File(p.join(dir, 'steamcmd.exe')).existsSync(),
      isTrue,
      reason: 'a separate installation under <data>/steamcmd was unpacked',
    );
    expect(rig.steam.state.isReady(account.id), isTrue);
    // The self-update run, its check run and the login run all ran in it.
    final runs = rig.steam.runs();
    expect(runs, hasLength(3));
    for (final run in runs) {
      expect(p.equals(run['cwd']! as String, dir), isTrue);
    }
    // The anonymous installation is not touched.
    expect(Directory(rig.steam.installation).listSync(), isEmpty);
    expect(rig.accountInstallations(), [account.id]);
  });

  test('steamcmd_download_fails', () async {
    final env = TestEnv();
    env.installValheim();
    final server = await serveArchive(status: HttpStatus.serviceUnavailable);
    final steam = SteamHarness(
      env,
      ready: false,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
      ),
    );
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final done = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'steamcmd_unavailable');
    expect(done.resultMessage, contains('503'));
    expect(
      steam.state.isReady('anonymous'),
      isFalse,
      reason: 'no partial directory is marked ready',
    );
    expect(steam.launcher.started, isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);
  });

  test('steamcmd_download_network_error', () async {
    final env = TestEnv();
    final dead = await serveArchive();
    final port = dead.port;
    await dead.close(force: true);
    final steam = SteamHarness(
      env,
      ready: false,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:$port/steamcmd.tar'),
      ),
    );

    await expectLater(
      steam.service.installApp(
        SteamAppRequest(
          appId: valheimAppId,
          installDirectory: p.join(env.root.path, 'server'),
        ),
        RecordingReporter(),
        CancelToken(),
      ),
      failsWith(
        'steamcmd_unavailable',
        messageHas: ['could not be downloaded'],
      ),
    );
    expect(steam.state.isReady('anonymous'), isFalse);
  });

  group('a stalled download', () {
    /// A server that takes requests and answers none of them, or only the
    /// start of the answer.
    Future<(HttpServer, List<HttpRequest>)> stalledServer({
      bool sendHeaders = false,
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <HttpRequest>[];
      server.listen((request) async {
        requests.add(request);
        if (sendHeaders) {
          request.response.contentLength = 1 << 20;
          request.response.add(List.filled(512, 0));
          await request.response.flush();
        }
      });
      return (server, requests);
    }

    SteamAppRequest requestFor(TestEnv env) => SteamAppRequest(
      appId: valheimAppId,
      installDirectory: p.join(env.root.path, 'server'),
    );

    for (final sendHeaders in [false, true]) {
      test('cancel_ends_the_bootstrap_and_frees_the_queue_'
          '${sendHeaders ? 'body' : 'headers'}', () async {
        final env = TestEnv();
        final (server, requests) = await stalledServer(
          sendHeaders: sendHeaders,
        );
        final steam = SteamHarness(
          env,
          ready: false,
          bootstrap: SteamCmdBootstrap(
            source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
            idleTimeout: const Duration(minutes: 5),
          ),
        );
        final first = CancelToken();
        final second = CancelToken();
        final firstRun = steam.service.installApp(
          requestFor(env),
          RecordingReporter(),
          first,
        );
        final firstOutcome = expectLater(
          firstRun,
          throwsA(isA<OperationCancelled>()),
        );
        final secondRun = steam.service.installApp(
          requestFor(env),
          RecordingReporter(),
          second,
        );
        final secondOutcome = expectLater(
          secondRun,
          throwsA(isA<OperationCancelled>()),
        );
        await eventually(
          () => requests.length == 1,
          reason: 'the first install reaches the download',
        );

        first.cancel();
        await firstOutcome.timeout(const Duration(seconds: 10));

        // The queued install got the lock and reached the download too.
        await eventually(
          () => requests.length == 2,
          reason: 'the queued install runs once the first is cancelled',
        );
        second.cancel();
        await secondOutcome.timeout(const Duration(seconds: 10));
        expect(steam.state.isReady('anonymous'), isFalse);
        expect(Directory(steam.installation).existsSync(), isFalse);
        expect(steam.launcher.started, isEmpty);
      });

      test(
        'fails_after_the_idle_timeout_${sendHeaders ? 'body' : 'headers'}',
        () async {
          final env = TestEnv();
          final (server, _) = await stalledServer(sendHeaders: sendHeaders);
          final steam = SteamHarness(
            env,
            ready: false,
            bootstrap: SteamCmdBootstrap(
              source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
              idleTimeout: const Duration(milliseconds: 300),
            ),
          );

          await expectLater(
            steam.service
                .installApp(requestFor(env), RecordingReporter(), CancelToken())
                .timeout(const Duration(seconds: 10)),
            failsWith(
              'steamcmd_unavailable',
              messageHas: ['could not be downloaded', 'no data'],
            ),
          );
          expect(Directory(steam.installation).existsSync(), isFalse);
        },
      );
    }
  });

  test('a_failed_self_update_is_not_ready', () async {
    final env = TestEnv();
    var fetches = 0;
    final launcher = _ScriptedLauncher(exitCode: 8, lines: ['ERROR! boom']);
    final state = MemorySteamState();
    final service = SteamCmdService(
      state: state,
      steamcmdRoot: p.join(env.data, 'steamcmd'),
      bootstrap: SteamCmdBootstrap(
        fetch: (uri, destination, cancel) async {
          fetches++;
          destination.add(tarArchive({'steamcmd.exe': utf8.encode('MZ')}));
        },
      ),
      launcher: launcher,
      diskSpace: (path) async => DiskSpace(volume: r'V:\', freeBytes: 1 << 40),
      log: (_) {},
    );
    addTearDown(service.close);
    final installation = p.join(env.data, 'steamcmd', 'anonymous');
    final request = SteamAppRequest(
      appId: valheimAppId,
      installDirectory: p.join(env.root.path, 'server'),
    );

    await expectLater(
      service.installApp(request, RecordingReporter(), CancelToken()),
      failsWith(
        'steamcmd_unavailable',
        messageHas: ['exited with code 8', 'ERROR! boom'],
      ),
    );
    expect(
      launcher.started,
      hasLength(2),
      reason: 'the self-update run and the check run; no app_update was run',
    );
    expect(state.isReady('anonymous'), isFalse);
    expect(Directory(installation).existsSync(), isFalse);

    await expectLater(
      service.installApp(request, RecordingReporter(), CancelToken()),
      throwsA(isA<YaguraException>()),
    );
    expect(fetches, 2, reason: 'the next attempt downloads afresh');
  });

  // A fresh SteamCMD exits with code 7 after its self-update ("Update
  // complete, launching..."), observed with the real steamcmd.exe; only the
  // check run that follows must succeed.
  test('the_self_update_run_exit_code_is_not_judged', () async {
    final env = TestEnv();
    final launcher = _ScriptedLauncher(exitCodes: [7, 0, 8], lines: []);
    final state = MemorySteamState();
    final service = SteamCmdService(
      state: state,
      steamcmdRoot: p.join(env.data, 'steamcmd'),
      bootstrap: SteamCmdBootstrap(
        fetch: (uri, destination, cancel) async {
          destination.add(tarArchive({'steamcmd.exe': utf8.encode('MZ')}));
        },
      ),
      launcher: launcher,
      diskSpace: (path) async => DiskSpace(volume: r'V:\', freeBytes: 1 << 40),
      log: (_) {},
    );
    addTearDown(service.close);

    // The scripted app_update (third run) fails; the bootstrap must not.
    await expectLater(
      service.installApp(
        SteamAppRequest(
          appId: valheimAppId,
          installDirectory: p.join(env.root.path, 'server'),
        ),
        RecordingReporter(),
        CancelToken(),
      ),
      throwsA(
        isA<YaguraException>().having(
          (e) => e.reason,
          'reason',
          isNot('steamcmd_unavailable'),
        ),
      ),
    );
    expect(launcher.started[0].last, '+quit');
    expect(launcher.started[1].last, '+quit');
    expect(state.isReady('anonymous'), isTrue);
  });
}

/// A launcher whose every process prints [lines] and exits with [exitCode].
class _ScriptedLauncher implements SteamProcessLauncher {
  _ScriptedLauncher({
    int exitCode = 0,
    List<int>? exitCodes,
    required this.lines,
  }) : exitCodes = exitCodes ?? [exitCode];

  /// The exit code of each run in turn; the last one repeats.
  final List<int> exitCodes;
  final List<String> lines;
  final started = <List<String>>[];

  @override
  Future<SteamProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    started.add([executable, ...arguments]);
    final run = started.length - 1;
    return _ScriptedProcess(
      exitCodes[run < exitCodes.length ? run : exitCodes.length - 1],
      lines,
    );
  }

  @override
  Future<void> close() async {}
}

class _ScriptedProcess implements SteamProcess {
  _ScriptedProcess(this._exitCode, this._lines);

  final int _exitCode;
  final List<String> _lines;

  @override
  int get pid => 0;

  @override
  Stream<String> get lines => Stream.fromIterable(_lines);

  @override
  Future<int> get exitCode async => _exitCode;

  @override
  void kill() {}
}

/// A launcher whose SteamCMD cannot be started.
class _ThrowingLauncher implements SteamProcessLauncher {
  @override
  Future<SteamProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async => throw ProcessException(executable, arguments, 'no such file');

  @override
  Future<void> close() async {}
}
