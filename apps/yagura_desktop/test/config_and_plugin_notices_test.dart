import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/ui/home_page.dart';
import 'package:yagura_desktop/src/ui/instance_list.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';

Widget _page() => const Column(
  children: [
    SizedBox(height: 200, child: InstanceListView(daemonId: kDevDaemonId)),
    Expanded(
      child: InstanceDetail(daemonId: kDevDaemonId, instanceId: 'i1'),
    ),
  ],
);

Harness _harness(Instance instance) {
  final daemon = FakeDaemon(instances: [instance]);
  daemon.plugins['testgame'] = PluginDetail(
    summary: PluginSummary(id: 'testgame', name: 'Test Game'),
    settingsSchema: JsonDocument(
      json: jsonEncode({
        'maxPlayers': {
          'type': 'integer',
          'label': 'Max players',
          'min': 1,
          'max': 127,
        },
      }),
      schemaVersion: 7,
    ),
  );
  return Harness(daemon: daemon);
}

void main() {
  testWidgets('external_edit_shown', (tester) async {
    final harness = _harness(makeInstance(id: 'i1', name: 'Alpha'));
    await pumpApp(tester, harness, _page());
    expect(find.byKey(const ValueKey('notice:external_edit:i1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('action:start:i1')));
    await settle(tester);
    harness.daemon.emitOperation(
      'op-1',
      finished(
        1,
        Operation(
          id: 'op-1',
          instanceId: 'i1',
          kind: 'start',
          status: OperationStatus.OPERATION_STATUS_SUCCEEDED,
          warnings: [
            'external_edit: serverDZ.cfg maxPlayers was changed by hand to '
                '"60"; it is set to "40"',
          ],
        ),
      ),
    );
    await settle(tester);

    // The notice names the file, the key and the old and new values.
    final notice = find.byKey(const ValueKey('notice:external_edit:i1'));
    expect(notice, findsOneWidget);
    for (final part in ['serverDZ.cfg', 'maxPlayers', '60', '40']) {
      expect(
        find.descendant(of: notice, matching: find.textContaining(part)),
        findsOneWidget,
        reason: part,
      );
    }
  });

  testWidgets('settings_invalid_after_a_reload', (tester) async {
    final harness = _harness(
      makeInstance(
        id: 'i1',
        name: 'Alpha',
        state: InstanceState.INSTANCE_STATE_ERROR,
        settings: const {'maxPlayers': 200},
      )..settingsInvalid = true,
    );
    await pumpApp(tester, harness, _page());
    harness.daemon.emitNotice(
      InstanceNotice(
        instanceId: 'i1',
        kind: 'settings_invalid',
        message: 'maxPlayers: must be at most 127',
      ),
    );
    await settle(tester);

    // The instance shows the flag naming the field.
    final notice = find.byKey(const ValueKey('notice:settings_invalid:i1'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(of: notice, matching: find.textContaining('maxPlayers')),
      findsOneWidget,
    );

    // Its start action is disabled.
    final start = tester.widget<IconButton>(
      find.byKey(const ValueKey('action:start:i1')),
    );
    expect(start.onPressed, isNull);

    // The settings form highlights the field.
    expect(find.text('must be at most 127'), findsOneWidget);
  });
}
