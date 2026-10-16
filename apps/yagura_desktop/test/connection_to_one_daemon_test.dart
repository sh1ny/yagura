import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/connection.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/ui/connection_banner.dart';
import 'package:yagura_desktop/src/ui/instance_list.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';

void main() {
  testWidgets('daemon_restarted', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(
        instances: [
          makeInstance(
            id: 'i1',
            name: 'Alpha',
            state: InstanceState.INSTANCE_STATE_RUNNING,
          ),
        ],
      ),
    );
    await pumpApp(
      tester,
      harness,
      const Column(
        children: [
          ConnectionBanner(daemonId: kDevDaemonId),
          Expanded(child: InstanceListView(daemonId: kDevDaemonId)),
        ],
      ),
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
    expect(find.textContaining('Connected'), findsOneWidget);

    // The daemon goes away: the client says so and keeps the last state.
    harness.daemon.kill();
    await settle(tester);
    expect(find.textContaining('Reconnecting'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
    expect(harness.delay.requested, [const Duration(seconds: 1)]);

    // Still down on the first retry: the next delay doubles.
    harness.delay.release();
    await settle(tester);
    expect(find.textContaining('Reconnecting'), findsOneWidget);
    expect(harness.delay.requested.last, const Duration(seconds: 2));

    // It comes back with the instance stopped (it changed while we were away).
    harness.daemon.restart(
      instances: [
        makeInstance(
          id: 'i1',
          name: 'Alpha',
          state: InstanceState.INSTANCE_STATE_STOPPED,
        ),
      ],
    );
    harness.delay.release();
    await settle(tester);

    expect(find.textContaining('Connected'), findsOneWidget);
    expect(find.text('stopped'), findsOneWidget);
    expect(find.text('running'), findsNothing);
    // A fresh snapshot: WatchInstances was opened again; no new connection
    // object was needed.
    expect(
      harness.daemon.calls.where((c) => c == 'WatchInstances'),
      hasLength(2),
    );
    expect(harness.connection.status, isA<Connected>());
  });

  test('backoff_doubles_from_one_to_thirty_seconds', () {
    expect(
      [for (var i = 0; i < 8; i++) backoffDelay(i).inSeconds],
      [1, 2, 4, 8, 16, 30, 30, 30],
    );
  });

  testWidgets('a_successful_reconnect_restarts_the_backoff', (tester) async {
    final harness = Harness();
    await pumpApp(
      tester,
      harness,
      const ConnectionBanner(daemonId: kDevDaemonId),
    );
    for (var round = 0; round < 2; round++) {
      harness.daemon.kill();
      await settle(tester);
      harness.daemon.restart();
      harness.delay.release();
      await settle(tester);
    }
    expect(harness.delay.requested, [
      const Duration(seconds: 1),
      const Duration(seconds: 1),
    ]);
  });

  testWidgets('operation_streams_resume_after_the_daemon_restarts', (
    tester,
  ) async {
    final harness = Harness(
      daemon: FakeDaemon(
        instances: [makeInstance(id: 'i1', name: 'Alpha')],
      ),
    );
    await pumpApp(
      tester,
      harness,
      const InstanceListView(daemonId: kDevDaemonId),
    );
    await harness.connection.startInstance(
      makeInstance(id: 'i1', name: 'Alpha'),
    );
    harness.daemon.emitOperation('op-1', stepStarted(1, 'spawn'));
    harness.daemon.emitOperation('op-1', stepStarted(2, 'health'));
    await settle(tester);

    harness.daemon.kill();
    await settle(tester);
    harness.daemon.restart();
    while (harness.delay.pending > 0) {
      harness.delay.release();
      await settle(tester);
    }

    // The follow is re-opened after the last sequence the client saw.
    expect(harness.daemon.watchOperationResumes, [0, 2]);
    harness.daemon.emitOperation('op-1', stepStarted(3, 'done'));
    await settle(tester);
    final state = (await harness.connection.operationsStream.first).single;
    expect(state.steps, ['spawn', 'health', 'done']);
  });
}
