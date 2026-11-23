import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/ui/operations_panel.dart';
import 'package:yagura_desktop/src/ui/prompt_dialog.dart';
import 'package:yagura_desktop/src/ui/steam_accounts_view.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';

Widget _page() => const Column(
  children: [
    PromptListener(daemonId: kDevDaemonId),
    Expanded(child: SteamAccountsView(daemonId: kDevDaemonId)),
    SizedBox(height: 200, child: OperationsPanel(daemonId: kDevDaemonId)),
  ],
);

Prompt _prompt(
  String kind, {
  Duration expiresIn = const Duration(minutes: 5),
}) => Prompt(
  id: 'p1',
  kind: kind,
  steamAccount: 'srvadmin',
  expiresAt: Timestamp.fromDateTime(DateTime.now().add(expiresIn)),
);

/// Dialogs animate and the countdown of a prompt ticks, so these tests pump by
/// hand instead of waiting for the tree to settle.
Future<void> _pumpDialog(WidgetTester tester) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('steam_guard_prompt', (tester) async {
    final harness = Harness();
    await pumpApp(tester, harness, _page());

    harness.daemon.raisePrompt(_prompt('authenticator'), operationId: 'op-7');
    await _pumpDialog(tester);

    // The dialog names the account and asks for the code.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('srvadmin'),
      ),
      findsWidgets,
    );
    await tester.enterText(find.byKey(const ValueKey('prompt:code')), '12345');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prompt:submit')));
    await _pumpDialog(tester);

    // The code goes to that operation, and the dialog is gone.
    final answer = harness.daemon.promptResponses.single;
    expect(answer.operationId, 'op-7');
    expect(answer.promptId, 'p1');
    expect(answer.value, '12345');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('mobile_approval_prompt', (tester) async {
    final harness = Harness();
    await pumpApp(tester, harness, _page());

    harness.daemon.raisePrompt(
      _prompt('mobile_approval', expiresIn: const Duration(minutes: 2)),
      operationId: 'op-7',
    );
    await _pumpDialog(tester);

    // A notice with the account and the time left, and no code field.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('srvadmin'),
      ),
      findsWidgets,
    );
    expect(find.textContaining(RegExp(r'\d+:\d\d left')), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt:code')), findsNothing);
    expect(find.byKey(const ValueKey('prompt:submit')), findsNothing);

    // Cancelling cancels the operation, and the dialog goes.
    await tester.tap(find.byKey(const ValueKey('prompt:cancel')));
    await _pumpDialog(tester);
    expect(harness.daemon.calls, contains('CancelOperation:op-7'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('prompt_from_another_device_s_operation', (tester) async {
    final harness = Harness();
    await pumpApp(tester, harness, _page());

    // Another device started the operation: this client never watched it.
    harness.daemon.raisePrompt(_prompt('email'), operationId: 'op-9');
    await _pumpDialog(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt:code')), findsOneWidget);
    expect(harness.daemon.calls, isNot(contains('WatchOperation:op-9')));
  });

  testWidgets('prompt_answered_elsewhere', (tester) async {
    final harness = Harness();
    await pumpApp(tester, harness, _page());

    harness.daemon.raisePrompt(_prompt('authenticator'), operationId: 'op-7');
    await _pumpDialog(tester);
    expect(find.byKey(const ValueKey('prompt:code')), findsOneWidget);

    harness.daemon.resolvePrompt('p1', byDeviceId: 'laptop');
    await _pumpDialog(tester);

    // The dialog closes and says the other device answered.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('answered on another device'), findsOneWidget);
    expect(harness.daemon.promptResponses, isEmpty);
  });

  testWidgets('code_rejected', (tester) async {
    final harness = Harness();
    await pumpApp(tester, harness, _page());

    await tester.enterText(
      find.byKey(const ValueKey('steam:username')),
      'srvadmin',
    );
    await tester.enterText(
      find.byKey(const ValueKey('steam:password')),
      'a-password',
    );
    await tester.tap(find.byKey(const ValueKey('steam:add')));
    await settle(tester);
    expect(harness.daemon.calls, contains('WatchOperation:op-1'));

    harness.daemon.raisePrompt(_prompt('authenticator'), operationId: 'op-1');
    await _pumpDialog(tester);
    await tester.enterText(find.byKey(const ValueKey('prompt:code')), '99999');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prompt:submit')));
    await _pumpDialog(tester);

    // The daemon rejects the code and fails the operation.
    harness.daemon.emitOperation(
      'op-1',
      finished(
        1,
        Operation(
          id: 'op-1',
          kind: 'add_steam_account',
          status: OperationStatus.OPERATION_STATUS_FAILED,
          resultReason: 'steam_guard_invalid',
          resultMessage: 'Steam did not accept the code',
        ),
      ),
    );
    await _pumpDialog(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('Steam did not accept the code'), findsOneWidget);

    // The operation offers adding the account again.
    await tester.tap(find.byKey(const ValueKey('operation:retry:op-1')));
    await _pumpDialog(tester);
    expect(find.byKey(const ValueKey('steam:add-dialog')), findsOneWidget);
  });
}
