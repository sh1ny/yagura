import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/ui/instance_list.dart';
import 'package:yagura_desktop/src/ui/operations_panel.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';

Widget _page() => const Column(
  children: [
    Expanded(child: InstanceListView(daemonId: kDevDaemonId)),
    SizedBox(height: 200, child: OperationsPanel(daemonId: kDevDaemonId)),
  ],
);

void main() {
  testWidgets('start_from_the_client', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(
        instances: [makeInstance(id: 'i1', name: 'Alpha')],
      ),
    );
    await pumpApp(tester, harness, _page());
    expect(find.text('stopped'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('action:start:i1')));
    await settle(tester);
    expect(harness.daemon.calls, contains('Start:i1'));
    expect(harness.daemon.calls, contains('WatchOperation:op-1'));

    // Steps show as they arrive.
    harness.daemon.emitOperation('op-1', stepStarted(1, 'apply_config'));
    await settle(tester);
    expect(find.text('apply_config'), findsOneWidget);
    harness.daemon.emitOperation('op-1', stepStarted(2, 'spawn'));
    harness.daemon.emitOperation('op-1', progress(3, 'spawn', 40));
    await settle(tester);
    expect(find.text('apply_config'), findsOneWidget);
    expect(find.text('spawn'), findsOneWidget);
    expect(find.textContaining('40%'), findsOneWidget);

    // The instance is running once the daemon reports it.
    expect(find.text('running'), findsNothing);
    harness.daemon.emitChanged(
      makeInstance(
        id: 'i1',
        name: 'Alpha',
        state: InstanceState.INSTANCE_STATE_RUNNING,
      ),
    );
    harness.daemon.emitOperation(
      'op-1',
      finished(
        4,
        Operation(
          id: 'op-1',
          instanceId: 'i1',
          kind: 'start',
          status: OperationStatus.OPERATION_STATUS_SUCCEEDED,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('running'), findsOneWidget);
    expect(find.textContaining('succeeded'), findsOneWidget);
  });

  testWidgets('install_and_stop_call_the_daemon', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(
        instances: [
          makeInstance(
            id: 'i1',
            name: 'Alpha',
            state: InstanceState.INSTANCE_STATE_NOT_INSTALLED,
          ),
          makeInstance(
            id: 'i2',
            name: 'Beta',
            state: InstanceState.INSTANCE_STATE_RUNNING,
          ),
        ],
      ),
    );
    await pumpApp(tester, harness, _page());

    await tester.tap(find.byKey(const ValueKey('action:install:i1')));
    await tester.tap(find.byKey(const ValueKey('action:stop:i2')));
    await settle(tester);
    expect(harness.daemon.calls, containsAll(['Install:i1', 'Stop:i2']));
  });

  testWidgets('delete_asks_for_the_name_before_removing_files', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(
        instances: [makeInstance(id: 'i1', name: 'Alpha', revision: 4)],
      ),
    );
    await pumpApp(tester, harness, _page());

    await tester.tap(find.byKey(const ValueKey('action:delete:i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete:files')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delete:confirm')),
      'Alpha',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('delete:submit')));
    await settle(tester);

    final request = harness.daemon.deletes.single;
    expect(request.instanceId, 'i1');
    expect(request.deleteFiles, isTrue);
    expect(request.confirmName, 'Alpha');
    expect(request.expectedRevision.toInt(), 4);
  });

  testWidgets('create_sends_the_plugin_and_name', (tester) async {
    final daemon = FakeDaemon();
    daemon.plugins['testgame'] = PluginDetail(
      summary: PluginSummary(id: 'testgame', name: 'Test Game'),
      settingsSchema: JsonDocument(json: '{}', schemaVersion: 7),
    );
    final harness = Harness(daemon: daemon);
    await pumpApp(tester, harness, _page());

    await tester.tap(find.byKey(const ValueKey('action:create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create:plugin')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Game').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('create:name')), 'Gamma');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create:submit')));
    await settle(tester);

    final request = daemon.creates.single;
    expect(request.pluginId, 'testgame');
    expect(request.name, 'Gamma');
    expect(request.settings.schemaVersion, 7);
  });
}
