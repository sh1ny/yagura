import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/daemon_support.dart';
import '../support/steam_support.dart';

SteamAppRequest requestFor(TestEnv env) => SteamAppRequest(
  appId: valheimAppId,
  installDirectory: p.join(env.root.path, 'server'),
);

/// Whether a process with [pid] still exists (this also signals it, which is
/// what the tests would do next anyway).
bool alive(int pid) => Process.killPid(pid);

/// Starts a long-running process whose executable lies in [directory], like a
/// SteamCMD that outlived its daemon; it is ended at tear-down.
Future<Process> startStray(String directory) async {
  Directory(directory).createSync(recursive: true);
  final source = Platform.isWindows
      ? p.join(Platform.environment['SystemRoot']!, 'System32', 'ping.exe')
      : '/bin/bash';
  final copy = p.join(
    directory,
    Platform.isWindows ? 'steamcmd.exe' : 'steamcmd',
  );
  File(source).copySync(copy);
  // On Linux a copy of bash waits on its stdin, which stays open. Not a
  // copy of sleep: a multicall coreutils (uutils on Ubuntu 26.04) does not
  // run under another name.
  final process = await Process.start(
    copy,
    Platform.isWindows ? ['-n', '300', '127.0.0.1'] : ['-c', 'read -t 300'],
  );
  addTearDown(() {
    process.kill(ProcessSignal.sigkill);
  });
  if (!Platform.isWindows) {
    await eventually(() {
      try {
        return Link('/proc/${process.pid}/exe').targetSync() ==
            File(copy).resolveSymbolicLinksSync();
      } on FileSystemException {
        return false;
      }
    }, reason: 'the stray runs the copy');
  }
  return process;
}

void main() {
  test('stalled_download', () async {
    final env = TestEnv();
    // Wide enough for the fake SteamCMD to start and reach 25 % under a
    // loaded full run, so the stall measured is the one after that progress.
    final steam = SteamHarness(
      env,
      noProgressTimeout: const Duration(seconds: 3),
      fakeEnvironment: {'FAKE_STEAMCMD_STALL_AFTER': '11'},
    );

    final started = DateTime.now();
    await expectLater(
      steam.service.installApp(
        requestFor(env),
        RecordingReporter(),
        CancelToken(),
      ),
      throwsA(
        isA<YaguraException>()
            .having((e) => e.reason, 'reason', 'steam_stalled')
            .having((e) => e.details['percent'], 'percent', 25)
            .having((e) => e.details['bytesDone'], 'bytesDone', 1250)
            .having((e) => e.details['bytesTotal'], 'bytesTotal', 5000)
            .having((e) => e.message, 'message', contains('1250')),
      ),
    );

    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 15)),
    );
    final pid = steam.appRuns().single['pid']! as int;
    await eventually(() => !alive(pid), reason: 'SteamCMD terminated');
  });

  test('total_time_cap', () async {
    final env = TestEnv();
    final steam = SteamHarness(
      env,
      totalTimeout: const Duration(seconds: 1),
      fakeEnvironment: {'FAKE_STEAMCMD_LOOP': '1'},
    );

    await expectLater(
      steam.service.installApp(
        requestFor(env),
        RecordingReporter(),
        CancelToken(),
      ),
      failsWith('steam_stalled', messageHas: ['in total']),
    );

    final pid = steam.appRuns().single['pid']! as int;
    await eventually(() => !alive(pid), reason: 'SteamCMD terminated');
  });

  test('cancel_terminates_steamcmd', () async {
    final env = TestEnv();
    final steam = SteamHarness(
      env,
      fakeEnvironment: {'FAKE_STEAMCMD_STALL_AFTER': '11'},
    );
    final cancel = CancelToken();
    final reporter = RecordingReporter();

    final run = steam.service.installApp(requestFor(env), reporter, cancel);
    await eventually(() => reporter.progresses.isNotEmpty, reason: 'progress');
    cancel.cancel();

    await expectLater(run, throwsA(isA<OperationCancelled>()));
    final pid = steam.appRuns().single['pid']! as int;
    await eventually(() => !alive(pid), reason: 'SteamCMD terminated');
  });

  test('stray_steamcmd_after_a_crash', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(env);
    final stray = await startStray(steam.installation);

    final daemon = await env.start(steamService: steam.service);

    await stray.exitCode.timeout(const Duration(seconds: 10));
    expect(daemon.startupNotices, isEmpty);
    expect(
      steam.log,
      contains(allOf(contains('${stray.pid}'), contains('terminated'))),
      reason: 'the termination is logged',
    );
  });

  test('stray_steamcmd_cannot_be_terminated', () async {
    final env = TestEnv();
    env.installValheim();
    final strays = FlakyStrayControl(failing: true);
    final steam = SteamHarness(
      env,
      strays: strays,
      sweepRetry: const Duration(milliseconds: 200),
    );
    final stray = await startStray(steam.installation);

    final daemon = await env.start(steamService: steam.service);

    // The listener still opens, with a notice.
    expect(daemon.startupNotices.map((n) => n.step), contains('steam_sweep'));
    final instance = await createValheim(daemon);
    final failed = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );
    expect(failed.status, OperationStatus.failed);
    expect(failed.resultReason, 'steamcmd_unavailable');
    expect(steam.launcher.started, isEmpty, reason: 'no SteamCMD started');
    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);

    // A retried sweep succeeds, and installs run again.
    strays.failing = false;
    await stray.exitCode.timeout(const Duration(seconds: 10));
    await eventually(
      () => steam.log.any((line) => line.contains('available again')),
      reason: 'the retried sweep',
    );
    final again = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );
    expect(
      again.status,
      OperationStatus.succeeded,
      reason: again.resultMessage,
    );
    expect(steam.appRuns(), hasLength(1));
  });
}
