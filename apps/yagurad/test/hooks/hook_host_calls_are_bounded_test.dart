import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/hooks/hooks.dart';

import 'hook_test_support.dart';

/// A worker the test controls: it finishes when [finish] is called and, when
/// [exitsOnKill] is false, ignores kill requests like a worker stuck in native
/// code.
class FakeWorker implements HookWorker {
  FakeWorker(this.request, {this.exitsOnKill = true});

  final HookWorkerRequest request;
  final bool exitsOnKill;
  final _result = Completer<Map<String, Object?>>();
  final _exited = Completer<void>();
  bool killed = false;

  @override
  Future<Map<String, Object?>> get result => _result.future;

  @override
  Future<void> get exited => _exited.future;

  @override
  void kill() {
    killed = true;
    if (exitsOnKill && !_exited.isCompleted) _exited.complete();
  }

  void finish() {
    if (!_result.isCompleted) {
      _result.complete({'status': 'ok', 'missing': false, 'resultJson': '{}'});
    }
    if (!_exited.isCompleted) _exited.complete();
  }

  void exit() {
    if (!_exited.isCompleted) _exited.complete();
  }
}

class FakeLauncher {
  final workers = <FakeWorker>[];
  bool exitsOnKill = true;

  Future<HookWorker> call(HookWorkerRequest request) async {
    final worker = FakeWorker(request, exitsOnKill: exitsOnKill);
    workers.add(worker);
    return worker;
  }
}

Future<void> pause([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('large_file_read_refused', () async {
    final instance = makeInstance();
    final log = File(p.join(instance.path, 'logs', 'server.log'))
      ..parent.createSync(recursive: true);
    log.openSync(mode: FileMode.write)
      ..truncateSync(100 * 1024 * 1024)
      ..closeSync();

    final host = HookHost();
    final result = await host.run(
      invocationFor(instance, '''
exports.onPreStart = function () {
  try {
    yagura.fs.readText('logs/server.log');
    return {args: ['read']};
  } catch (e) {
    return {args: [e.code, e.message]};
  }
};
'''),
    );

    expect(result.args, hasLength(2));
    expect(result.args![0], 'host_limit_exceeded');
    expect(result.args![1], contains('16 MiB'));
  });

  test('waiting_for_a_worker', () async {
    final launcher = FakeLauncher();
    final host = HookHost(launcher: launcher.call);
    HookInvocation invocation(Duration deadline) => invocationFor(
      makeInstance(),
      'ignored by the fake worker',
      deadline: deadline,
    );

    // Four hooks occupy every slot.
    final busy = [
      for (var i = 0; i < 4; i++)
        host.run(invocation(const Duration(seconds: 60))),
    ];
    await pause();
    expect(launcher.workers, hasLength(4));

    // The fifth asks for a 300 ms deadline and waits 480 ms for a slot, longer
    // than its deadline: the wait must not count against it.
    const deadline = Duration(milliseconds: 300);
    final fifth = host.run(invocation(deadline));
    await pause(480);
    expect(launcher.workers, hasLength(4), reason: 'fifth is still waiting');

    launcher.workers[0].finish();
    await pause();
    expect(launcher.workers, hasLength(5));
    expect(launcher.workers[4].request.deadline, deadline);

    // It then runs for 100 ms and succeeds: its deadline began at the start.
    await pause(100);
    launcher.workers[4].finish();
    expect((await fifth).ran, isTrue);

    for (final w in launcher.workers) {
      w.finish();
    }
    await Future.wait(busy);
  });

  test('timed_out_worker_keeps_its_slot', () async {
    final launcher = FakeLauncher()..exitsOnKill = false;
    final host = HookHost(
      launcher: launcher.call,
      watchdogGrace: const Duration(milliseconds: 50),
      leakGrace: const Duration(seconds: 30),
    );

    // The first worker misses its deadline and its isolate does not exit.
    await expectLater(
      host.run(
        invocationFor(
          makeInstance(),
          'ignored',
          deadline: const Duration(milliseconds: 50),
        ),
      ),
      throwsA(
        isA<YaguraException>().having(
          (e) => e.reason,
          'reason',
          'hook_timeout',
        ),
      ),
    );
    final stuck = launcher.workers.single;
    expect(stuck.killed, isTrue, reason: 'a kill was requested');
    expect(host.runningWorkers, 1, reason: 'its slot stays reserved');

    // Four calls: three run at once, the fourth waits.
    launcher.exitsOnKill = true;
    final calls = [
      for (var i = 0; i < 4; i++)
        host.run(
          invocationFor(
            makeInstance(),
            'ignored',
            deadline: const Duration(seconds: 60),
          ),
        ),
    ];
    await pause();
    expect(launcher.workers.length - 1, 3);
    expect(host.runningWorkers, 4);

    // The stuck isolate finally exits and the fourth call gets its slot.
    stuck.exit();
    await pause();
    expect(launcher.workers.length - 1, 4);

    for (final w in launcher.workers) {
      w.finish();
    }
    await Future.wait(calls);
  });

  test('directory_listing_within_limit', () async {
    final instance = makeInstance();
    for (var i = 0; i < 40; i++) {
      writeInstanceFile(instance, 'keys/key$i.bikey', 'x' * (i + 1));
    }

    final result = await HookHost().run(
      invocationFor(instance, '''
exports.onPreStart = function () {
  const entries = yagura.fs.list('keys');
  entries.sort((a, b) => a.name < b.name ? -1 : 1);
  return {args: [String(entries.length)].concat(entries.map(e => e.name + ':' + e.size))};
};
'''),
    );

    expect(result.args!.first, '40');
    expect(result.args, hasLength(41));
    expect(result.args, contains('key0.bikey:1'));
    expect(result.args, contains('key39.bikey:40'));
  });
}
