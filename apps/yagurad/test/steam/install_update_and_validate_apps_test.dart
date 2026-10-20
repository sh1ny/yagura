import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/steam_support.dart';

void main() {
  test('update_reports_progress', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(
      env,
      fakeEnvironment: {'FAKE_STEAMCMD_DELAY_MS': '40'},
    );
    final daemon = await env.start(steamService: steam.service);
    final instance = await createInstalled(daemon);

    final op = daemon.instances.update(instance.id);
    final events = await daemon.operations.watch(op.id).toList();

    final progress = [
      for (final e in events.whereType<ProgressEvent>())
        if (e.step == 'download' && e.bytesTotal > 0) e,
    ];
    expect(progress.map((e) => e.bytesDone), [0, 1250, 2500, 3750, 5000]);
    expect(progress.map((e) => e.percent), [0, 25, 50, 75, 100]);
    expect(progress.every((e) => e.bytesTotal == 5000), isTrue);
    for (var i = 1; i < progress.length; i++) {
      expect(
        progress[i].at.difference(progress[i - 1].at),
        lessThan(const Duration(seconds: 2)),
      );
    }
    final finished = events.last as FinishedEvent;
    expect(finished.operation.status, OperationStatus.succeeded);
  });

  test('two_instances_of_one_app_installed_at_once', () async {
    final env = TestEnv();
    env.installValheim();
    final hold = File(p.join(env.root.path, 'hold'))..writeAsStringSync('');
    final steam = SteamHarness(
      env,
      fakeEnvironment: {'FAKE_STEAMCMD_HOLD_FILE': hold.path},
    );
    final daemon = await env.start(steamService: steam.service);
    final first = await createValheim(daemon, name: 'One');
    final second = await createValheim(
      daemon,
      name: 'Two',
      ports: {'game': 2556},
    );

    final op1 = daemon.instances.install(first.id);
    await eventually(() => steam.appRuns().isNotEmpty, reason: 'first run');
    final op2 = daemon.instances.install(second.id);
    await eventually(
      () =>
          daemon.operations.get(op2.id)!.currentStep == 'waiting_for_steamcmd',
      reason: 'second waits for SteamCMD',
    );
    expect(steam.appRuns(), hasLength(1), reason: 'one run at a time');
    hold.deleteSync();

    final done1 = await daemon.operations.whenDone(op1.id);
    final done2 = await daemon.operations.whenDone(op2.id);

    expect(
      done1.status,
      OperationStatus.succeeded,
      reason: done1.resultMessage,
    );
    expect(
      done2.status,
      OperationStatus.succeeded,
      reason: done2.resultMessage,
    );
    expect(done1.endedAt!.isAfter(done2.endedAt!), isFalse);
    for (final instance in [first, second]) {
      final dir = p.join(instance.directory, 'server');
      expect(File(p.join(dir, 'app_$valheimAppId.bin')).existsSync(), isTrue);
    }
    final runs = steam.appRuns();
    expect(runs, hasLength(2));
    expect(runs[0]['pid'], isNot(runs[1]['pid']));
  });

  test('not_enough_disk_space', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(env, freeBytes: 1500);
    steam.state.recordSize(valheimAppId, 1000);
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final done = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'insufficient_disk');
    expect(
      done.resultMessage,
      allOf(contains(r'V:\'), contains('1500'), contains('2000')),
    );
    expect(steam.runs(), isEmpty, reason: 'nothing was downloaded');
  });

  test('first_install_without_a_known_size', () async {
    final env = TestEnv();
    env.installValheim(from: '  size_hint_bytes: 1500000000', to: '');
    final steam = SteamHarness(env, freeBytes: 10);
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final done = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(done.warnings, contains('disk_check_skipped'));
    expect(steam.state.lastKnownSize(valheimAppId), greaterThan(4000));
  });

  test('size_hint_is_used_until_a_size_is_known', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(env, freeBytes: 2999999999);
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final failed = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );
    expect(failed.resultReason, 'insufficient_disk');
    expect(failed.resultMessage, contains('3000000000'));

    steam.free = 3000000000;
    final ok = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );
    expect(ok.status, OperationStatus.succeeded, reason: ok.resultMessage);
    expect(ok.warnings, isNot(contains('disk_check_skipped')));
  });

  test('last_known_size_wins_over_the_hint', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(env, freeBytes: 20000);
    steam.state.recordSize(valheimAppId, 1000);
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final done = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
  });
}
