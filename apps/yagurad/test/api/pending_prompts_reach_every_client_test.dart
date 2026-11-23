import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/operations/operations.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';
import '../support/secure_support.dart';
import '../support/steam_account_support.dart';
import '../support/steam_support.dart';

/// The events of a `WatchPrompts` call as they arrive.
class PromptWatch {
  PromptWatch(Stream<pb.PromptEvent> stream) {
    subscription = stream.listen(
      events.add,
      onError: (Object e) => error = e,
      onDone: () => done = true,
    );
    addTearDown(subscription.cancel);
  }

  final events = <pb.PromptEvent>[];
  late final StreamSubscription<pb.PromptEvent> subscription;
  Object? error;
  var done = false;

  Future<void> until(
    bool Function(List<pb.PromptEvent> events) test, {
    String? reason,
  }) async {
    await eventually(() => error != null || test(events), reason: reason);
    if (error != null) fail('the stream failed: $error');
  }
}

void main() {
  test('snapshot_then_raised_and_resolved', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(
      env,
      realOutput: true,
      bootstrap: DirectoryBootstrap(),
    );
    steam.script.rules([
      loginRule(3, 'code_accepted'),
      loginRule(2, 'email_code_asked'),
    ]);
    final clock = TestClock();
    final daemon = await env.start(
      serviceMode: true,
      secretProtector: FakeSecretProtector(serviceSid),
      clock: clock.call,
      steamService: steam.service,
    );
    final secure = await SecureHarness.start(env, daemon: daemon, clock: clock);
    final first = await secure.pair('first-phone');
    final second = await secure.pair('second-phone');

    // One prompt is pending when the first device subscribes.
    final pending = await first.steam.addAccount(
      pb.AddAccountRequest(username: 'one', password: testPassword),
    );
    await poll(() async {
      final op = await first.operations.getOperation(
        pb.GetOperationRequest(operationId: pending.id),
      );
      return op.hasPendingPrompt() ? op : null;
    }, 'the first prompt');
    final watch = PromptWatch(
      first.operations.watchPrompts(pb.WatchPromptsRequest()),
    );
    await watch.until((e) => e.isNotEmpty, reason: 'the snapshot');
    expect(watch.events.first.hasSnapshot(), isTrue);
    final snapshot = watch.events.first.snapshot.prompts.single;
    expect(snapshot.prompt.kind, 'email');
    expect(snapshot.prompt.steamAccount, 'one');
    expect(snapshot.operations.single.operationId, pending.id);
    expect(snapshot.operations.single.instanceId, isEmpty);
    expect(
      snapshot.operations.single.accountId,
      matches(RegExp(r'^acct_[0-9a-f]{12}$')),
    );

    // Another operation raises a prompt, which the second device answers.
    final other = await second.steam.addAccount(
      pb.AddAccountRequest(username: 'two', password: testPassword),
    );
    await watch.until((e) => e.length >= 2, reason: 'the raised prompt');
    final raised = watch.events[1].raised;
    expect(watch.events[1].hasRaised(), isTrue);
    expect(raised.operations.single.operationId, other.id);
    expect(raised.prompt.steamAccount, 'two');
    await second.operations.respondToPrompt(
      pb.RespondToPromptRequest(
        operationId: other.id,
        promptId: raised.prompt.id,
        value: 'ABCDE',
      ),
    );

    await watch.until((e) => e.length >= 3, reason: 'the resolution');
    final resolved = watch.events[2].resolved;
    expect(watch.events[2].hasResolved(), isTrue);
    expect(resolved.promptId, raised.prompt.id);
    expect(resolved.byDeviceId, second.deviceId);
    expect(resolved.outcome, 'answered');
    expect(second.deviceId, isNot(first.deviceId));
  });

  test('late_answer_refused', () async {
    final rig = await AccountRig.start();
    rig.steam.script.rules([
      loginRule(3, 'code_accepted'),
      loginRule(2, 'email_code_asked'),
    ]);
    final started = await rig.add('srvadmin');
    final waiting = await rig.waitForPrompt(started.id);

    await rig.respond(waiting, 'F3K9P');
    final late = await failureOf(rig.respond(waiting, 'LATE1'));

    expect(late.code, StatusCode.failedPrecondition);
    expect(errorDetailOf(late)?.reason, 'prompt_resolved');
    final done = await rig.finish(started.id);
    expect(
      done.status,
      pb.OperationStatus.OPERATION_STATUS_SUCCEEDED,
      reason: done.resultMessage,
    );
    expect(rig.loginArguments().last, [
      'srvadmin',
      testPassword,
      'F3K9P',
    ], reason: 'the first answer stands');
  });

  test('concurrent_answers_have_one_winner', () async {
    final rig = await AccountRig.start();
    rig.steam.script.rules([
      loginRule(3, 'code_accepted'),
      loginRule(2, 'email_code_asked'),
    ]);
    final started = await rig.add('srvadmin');
    final waiting = await rig.waitForPrompt(started.id);

    final results = await Future.wait([
      for (final code in ['AAAAA', 'BBBBB', 'CCCCC'])
        rig
            .respond(waiting, code)
            .then<Object>((_) => 'ok', onError: (Object e) => e),
    ]);

    expect(results.where((r) => r == 'ok'), hasLength(1));
    for (final r in results.where((r) => r != 'ok')) {
      expect(errorDetailOf(r as GrpcError)?.reason, 'prompt_resolved');
    }
    final done = await rig.finish(started.id);
    expect(done.status, pb.OperationStatus.OPERATION_STATUS_SUCCEEDED);
  });

  test('malformed_answer', () async {
    final rig = await AccountRig.start();
    rig.steam.script.rules([
      loginRule(3, 'code_accepted'),
      loginRule(2, 'email_code_asked'),
    ]);
    final started = await rig.add('srvadmin');
    final waiting = await rig.waitForPrompt(started.id);

    for (final bad in ['A' * 40, '', 'F3K9-P', 'F3K 9P']) {
      final error = await failureOf(rig.respond(waiting, bad));
      expect(error.code, StatusCode.invalidArgument, reason: '"$bad"');
      expect(errorDetailOf(error)?.reason, 'prompt_answer_invalid');
    }

    final still = await rig.operation(started.id);
    expect(
      still.status,
      pb.OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT,
      reason: 'the prompt stays pending',
    );
    expect(still.pendingPrompt.id, waiting.pendingPrompt.id);
    await rig.respond(waiting, 'F3K9P');
    final done = await rig.finish(started.id);
    expect(done.status, pb.OperationStatus.OPERATION_STATUS_SUCCEEDED);
  });

  test('slow_prompt_watcher', () async {
    final rig = await AccountRig.start();
    final slow = PromptWatch(
      rig.api.operations.watchPrompts(pb.WatchPromptsRequest()),
    );
    await slow.until((e) => e.isNotEmpty, reason: 'the snapshot');

    // It stops reading while far more than 256 events are produced (some fill
    // the transport's buffers before any queue in the daemon): every
    // operation raises a prompt and ends it at once.
    slow.subscription.pause();
    for (var i = 0; i < 900; i++) {
      rig.daemon.operations.enqueue(
        accountId: 'slow$i',
        kind: OperationKind.addSteamAccount,
        body: (ctx) async => ctx
            .raisePrompt(
              const PromptSpec(
                kind: 'email',
                message: 'code',
                steamAccount: 'nobody',
                wait: Duration(minutes: 1),
              ),
            )
            .close(PromptOutcome.cancelled),
      );
    }
    final live = rig.daemon.operations.enqueue(
      accountId: 'slowlast',
      kind: OperationKind.addSteamAccount,
      body: (ctx) async => ctx.raisePrompt(
        const PromptSpec(
          kind: 'email',
          message: 'code',
          steamAccount: 'last',
          wait: Duration(minutes: 5),
        ),
      ),
    );
    await rig.daemon.operations.whenDone(live.id);
    final before = slow.events.length;
    slow.subscription.resume();

    await slow.until(
      (e) => e.any((x) => x.hasResyncRequired()),
      reason: 'resync_required',
    );
    await slow.until(
      (e) => e
          .skipWhile((x) => !x.hasResyncRequired())
          .any((x) => x.hasSnapshot()),
      reason: 'a fresh snapshot after resync_required',
    );
    final events = slow.events;
    final resync = events.indexWhere((e) => e.hasResyncRequired());
    expect(events[resync + 1].hasSnapshot(), isTrue);
    expect(
      events.length - before,
      lessThan(1500),
      reason: 'the backlog was dropped, not delivered',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('too_many_prompt_watchers', () async {
    final rig = await AccountRig.start();
    final watches = <PromptWatch>[
      for (var i = 0; i < 32; i++)
        PromptWatch(rig.api.operations.watchPrompts(pb.WatchPromptsRequest())),
    ];
    for (final watch in watches) {
      await watch.until((e) => e.isNotEmpty, reason: 'a snapshot');
      expect(watch.events.first.hasSnapshot(), isTrue);
    }

    await expectLater(
      rig.api.operations.watchPrompts(pb.WatchPromptsRequest()).first,
      throwsA(
        isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.resourceExhausted)
            .having(
              (e) => errorDetailOf(e)?.reason,
              'reason',
              'too_many_subscribers',
            ),
      ),
    );

    // A watcher that goes away frees its place.
    await watches.first.subscription.cancel();
    await poll(() async {
      try {
        final first = await rig.api.operations
            .watchPrompts(pb.WatchPromptsRequest())
            .first;
        return first.hasSnapshot() ? first : null;
      } on GrpcError {
        return null;
      }
    }, 'a place to be free again');
  });
}
