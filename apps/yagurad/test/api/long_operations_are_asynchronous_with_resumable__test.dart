import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/instances_api.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';

/// Starts an operation on [instanceId] whose body is [body].
pb.Operation startOperation(
  ApiHarness api,
  String instanceId,
  OperationBody body,
) => _view(
  api.daemon.operations.enqueue(
    instanceId: instanceId,
    kind: OperationKind.validate,
    body: body,
  ),
);

pb.Operation _view(Operation operation) =>
    pb.Operation(id: operation.id, instanceId: operation.instanceId);

/// The events of a `WatchOperation` call as they arrive.
class OperationWatch {
  OperationWatch(Stream<pb.OperationEvent> stream) {
    subscription = stream.listen(
      events.add,
      onError: (Object e) => error = e,
      onDone: () => done = true,
    );
    addTearDown(subscription.cancel);
  }

  final events = <pb.OperationEvent>[];
  late final StreamSubscription<pb.OperationEvent> subscription;
  Object? error;
  var done = false;

  Future<void> until(
    bool Function(List<pb.OperationEvent> events) test, {
    String? reason,
  }) async {
    await eventually(() => error != null || test(events), reason: reason);
    if (error != null) fail('the stream failed: $error');
  }

  Future<void> whenDone() async {
    await eventually(() => done || error != null, reason: 'the stream to end');
    if (error != null) fail('the stream failed: $error');
  }
}

/// Watches [id] on [channel] (the harness's own channel by default).
OperationWatch watch(
  ApiHarness api,
  String id, {
  int after = 0,
  ClientChannel? channel,
}) => OperationWatch(
  (channel == null ? api.operations : pb.OperationsClient(channel))
      .watchOperation(
        pb.WatchOperationRequest(operationId: id, afterSequence: Int64(after)),
      ),
);

Future<Daemon> daemonWithInstance(TestEnv env) async {
  env.installValheim();
  return env.start();
}

void main() {
  test('reconnect_without_losing_events', () async {
    final env = TestEnv();
    final daemon = await daemonWithInstance(env);
    final instance = await createValheim(daemon);
    final api = await ApiHarness.start(env, daemon: daemon);
    final gate = Completer<void>();
    final operation = startOperation(api, instance.id, (ctx) async {
      ctx.beginStep('work');
      for (var i = 1; i <= 16; i++) {
        ctx.log('line $i');
      }
      await gate.future;
      for (var i = 17; i <= 25; i++) {
        ctx.log('line $i');
      }
    });

    // The client sees the first events and loses its connection.
    final connection = api.connect();
    final first = watch(api, operation.id, channel: connection);
    await first.until((e) => e.length >= 17, reason: 'the first 17 events');
    final seen = first.events.take(17).last.sequence.toInt();
    expect(seen, 17);
    await connection.terminate();

    // Events pile up while it is away; it reconnects after event 17.
    gate.complete();
    await daemon.operations.whenDone(operation.id);
    final second = watch(api, operation.id, after: seen);
    await second.whenDone();

    final sequences = [for (final e in second.events) e.sequence.toInt()];
    expect(sequences.first, 18, reason: 'from event 18 onward');
    expect(sequences, [
      for (var i = 18; i < 18 + sequences.length; i++) i,
    ], reason: 'no gap');
    expect(
      [for (final e in second.events.where((e) => e.hasLog())) e.log.text],
      [for (var i = 17; i <= 25; i++) 'line $i'],
      reason: 'the events emitted while it was away, in order',
    );
    expect(second.events.last.hasFinished(), isTrue);
    expect(second.events.any((e) => e.hasEventsDropped()), isFalse);
  });

  test('missed_events_no_longer_retained', () async {
    final env = TestEnv();
    final daemon = await daemonWithInstance(env);
    final instance = await createValheim(daemon);
    final api = await ApiHarness.start(env, daemon: daemon);
    final gate = Completer<void>();
    final operation = startOperation(api, instance.id, (ctx) async {
      ctx.beginStep('work');
      for (var i = 1; i <= 2400; i++) {
        ctx.log('line $i');
      }
      await gate.future;
      ctx.log('live');
    });
    await eventually(
      () => daemon.operations.get(operation.id)!.lastSequence >= 2401,
      reason: 'the 2,400 events to be emitted',
    );

    final resumed = watch(api, operation.id, after: 10);
    await resumed.until(
      (e) => e.length >= 2002,
      reason: 'dropped marker, snapshot and the retained events',
    );
    gate.complete();
    await resumed.whenDone();

    final events = resumed.events;
    expect(events.first.hasEventsDropped(), isTrue);
    final dropped = events.first.eventsDropped;
    expect(dropped.fromSequence.toInt(), 11);
    expect(dropped.toSequence.toInt(), greaterThan(11));
    expect(events[1].hasSnapshot(), isTrue, reason: 'then the operation');
    expect(
      events[1].snapshot.status,
      pb.OperationStatus.OPERATION_STATUS_RUNNING,
    );
    expect(
      events[2].sequence.toInt(),
      dropped.toSequence.toInt() + 1,
      reason: 'retained events follow without a gap',
    );
    expect(
      events.any((e) => e.hasLog() && e.log.text == 'live'),
      isTrue,
      reason: 'then live events',
    );
    expect(events.last.hasFinished(), isTrue);
  });

  test('operation_pruned_from_history', () async {
    final env = TestEnv();
    final daemon = await daemonWithInstance(env);
    final instance = await createValheim(daemon);
    final operation = daemon.operations.enqueue(
      instanceId: instance.id,
      kind: OperationKind.validate,
      body: (ctx) async => ctx.log('done'),
    );
    await daemon.operations.whenDone(operation.id);
    await env.kill(daemon);

    // The daemon restarts a month later and prunes its history.
    final later = await env.start(
      clock: () => DateTime.now().add(const Duration(days: 31)),
    );
    final api = await ApiHarness.start(env, daemon: later);

    await expectLater(
      api.operations.watchOperation(
        pb.WatchOperationRequest(operationId: operation.id),
      ),
      emitsError(
        isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.notFound)
            .having(
              (e) => errorDetailOf(e)?.reason,
              'reason',
              'operation_expired',
            ),
      ),
    );
    // An id that never existed is a different error.
    await expectLater(
      api.operations.watchOperation(
        pb.WatchOperationRequest(operationId: 'nonsense'),
      ),
      emitsError(
        isA<GrpcError>().having(
          (e) => errorDetailOf(e)?.reason,
          'reason',
          'operation_not_found',
        ),
      ),
    );
  });

  test('stalled_watch_is_bounded', () async {
    final env = TestEnv();
    final daemon = await daemonWithInstance(env);
    final instance = await createValheim(daemon);
    // A byte bound far below the 8 MiB default, so a few hundred lines cross it.
    final api = await ApiHarness.start(
      env,
      daemon: daemon,
      watchLimits: const WatchLimits(maxBytes: 100 * 1024),
    );
    final gate = Completer<void>();
    final end = Completer<void>();
    final line = 'x' * 4096;
    final operation = startOperation(api, instance.id, (ctx) async {
      ctx.beginStep('work');
      ctx.log('first');
      await gate.future;
      // Asynchronous batches, so the transport sees them as they come.
      for (var batch = 0; batch < 20; batch++) {
        for (var i = 0; i < 25; i++) {
          ctx.log(line);
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await end.future;
    });

    final slow = watch(api, operation.id, channel: api.connect());
    await slow.until((e) => e.length >= 2, reason: 'the first events');
    slow.subscription.pause();
    gate.complete();
    await eventually(
      () => daemon.operations.get(operation.id)!.lastSequence >= 500,
      reason: 'the operation to emit its lines',
    );

    slow.subscription.resume();
    await eventually(
      () => slow.error != null || slow.done,
      reason: 'the stalled watch to end',
    );
    expect(slow.error, isA<GrpcError>());
    expect(errorDetailOf(slow.error! as GrpcError)?.reason, 'resync_required');
    expect(
      slow.events.length,
      lessThan(300),
      reason: 'the queued backlog was dropped, not delivered',
    );

    // It reconnects after the last event it read and still sees the end.
    final seen = slow.events.last.sequence.toInt();
    end.complete();
    final resumed = watch(api, operation.id, after: seen);
    await resumed.whenDone();
    expect(resumed.events.last.hasFinished(), isTrue);
    expect(resumed.events.first.sequence.toInt(), greaterThan(seen));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('resume_across_coalesced_progress', () async {
    final env = TestEnv();
    final daemon = await daemonWithInstance(env);
    final instance = await createValheim(daemon);
    final api = await ApiHarness.start(env, daemon: daemon);
    final away = Completer<void>();
    final end = Completer<void>();
    final operation = startOperation(api, instance.id, (ctx) async {
      ctx.beginStep('download');
      ctx.log('line 1');
      ctx.progress('download', percent: 10);
      await away.future;
      ctx.log('line 2');
      for (var percent = 20; percent <= 60; percent += 10) {
        ctx.progress('download', percent: percent.toDouble());
      }
      ctx.log('line 3');
      await end.future;
    });

    // The client has seen the first three events and disconnects.
    final connection = api.connect();
    final first = watch(api, operation.id, channel: connection);
    await first.until((e) => e.length >= 3, reason: 'the first three events');
    final seen = first.events.take(3).last.sequence.toInt();
    await connection.terminate();
    away.complete();
    await eventually(
      () => daemon.operations.get(operation.id)!.lastSequence >= seen + 7,
      reason: 'the events emitted while away',
    );

    final resumed = watch(api, operation.id, after: seen);
    await resumed.until(
      (e) => e.any((x) => x.hasLog() && x.log.text == 'line 3'),
    );
    end.complete();
    await resumed.whenDone();

    final events = resumed.events;
    expect(events.any((e) => e.hasEventsDropped()), isFalse);
    expect(
      [for (final e in events.where((e) => e.hasLog())) e.log.text],
      ['line 2', 'line 3'],
      reason: 'every retained non-progress event',
    );
    final progress = events.where((e) => e.hasProgress()).toList();
    expect(progress, hasLength(1), reason: 'coalesced to the latest');
    expect(progress.single.progress.percent, 60);
    expect(
      progress.single.sequence.toInt(),
      seen + 6,
      reason: 'the sequence of the last progress event',
    );
  });
}
