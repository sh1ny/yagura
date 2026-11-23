import 'dart:async';
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/transport.dart';
import 'package:yagura_desktop/src/ui/home_page.dart';
import 'package:yagura_desktop/src/ui/operations_panel.dart';
import 'package:yagura_desktop/src/ui/prompt_dialog.dart';
import 'package:yagura_desktop/src/ui/steam_accounts_view.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';

Widget _page() => const Column(
  children: [
    PromptListener(daemonId: kDevDaemonId),
    Expanded(child: SteamAccountsView(daemonId: kDevDaemonId)),
    SizedBox(height: 120, child: OperationsPanel(daemonId: kDevDaemonId)),
  ],
);

SteamAccount _account(String status, {List<String> usedBy = const []}) =>
    SteamAccount(
      id: 'acct_1',
      username: 'srvadmin',
      status: status,
      usedByInstanceIds: usedBy,
    );

TextEditingController _controller(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!;

void main() {
  testWidgets('account_added_from_the_desktop', (tester) async {
    final harness = Harness();
    harness.daemon.addAccountGate = Completer<void>();
    await pumpApp(tester, harness, _page());

    await tester.enterText(
      find.byKey(const ValueKey('steam:username')),
      'srvadmin',
    );
    await tester.enterText(
      find.byKey(const ValueKey('steam:password')),
      'hunter2-secret',
    );
    await tester.tap(find.byKey(const ValueKey('steam:remember')));
    await tester.tap(find.byKey(const ValueKey('steam:add')));
    await settle(tester);

    // The call is in flight: the daemon has the password, the field is empty,
    // and the password is on screen nowhere.
    final request = harness.daemon.accountAdds.single;
    expect(request.username, 'srvadmin');
    expect(request.password, 'hunter2-secret');
    expect(request.rememberPassword, isTrue);
    expect(_controller(tester, 'steam:password').text, isEmpty);
    expect(find.text('hunter2-secret'), findsNothing);

    harness.daemon.addAccountGate!.complete();
    await settle(tester);

    // The Steam Guard prompt arrives and is answered.
    harness.daemon.raisePrompt(
      Prompt(id: 'p1', kind: 'authenticator', steamAccount: 'srvadmin'),
      operationId: 'op-1',
    );
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const ValueKey('prompt:code')), '12345');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prompt:submit')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // The operation succeeds and the account is listed as ready.
    harness.daemon.accounts = [_account('ready')];
    harness.daemon.emitOperation(
      'op-1',
      finished(
        1,
        Operation(
          id: 'op-1',
          kind: 'add_steam_account',
          status: OperationStatus.OPERATION_STATUS_SUCCEEDED,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('srvadmin'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
    expect(_controller(tester, 'steam:password').text, isEmpty);
  });

  testWidgets('account_needs_re_login', (tester) async {
    final harness = Harness();
    harness.daemon.accounts = [_account('reauth_required')];
    await pumpApp(tester, harness, _page());

    expect(find.text('needs re-login'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('steam:reauth:acct_1')));
    await tester.pumpAndSettle();

    // The password entry is for that account.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('srvadmin'),
      ),
      findsWidgets,
    );
    await tester.enterText(
      find.byKey(const ValueKey('reauth:password')),
      'new-secret',
    );
    await tester.tap(find.byKey(const ValueKey('reauth:submit')));
    // The operation's progress bar animates for good: settle by hand.
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    final request = harness.daemon.accountReauths.single;
    expect(request.accountId, 'acct_1');
    expect(request.password, 'new-secret');
    expect(find.text('new-secret'), findsNothing);
  });

  testWidgets('removal_refused', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(
        instances: [makeInstance(id: 'i1', name: 'Alpha')],
      ),
    );
    harness.daemon
      ..accounts = [
        _account('ready', usedBy: ['i1']),
      ]
      ..removeAccountFailure = const DaemonCallException(
        code: 9,
        reason: 'account_in_use',
        message: 'the account is in use',
      );
    await pumpApp(tester, harness, _page());

    await tester.tap(find.byKey(const ValueKey('steam:remove:acct_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('steam:remove:confirm')));
    await tester.pumpAndSettle();

    // The account stays and the message names the instance that uses it.
    expect(harness.daemon.calls, contains('RemoveAccount:acct_1'));
    expect(find.text('srvadmin'), findsOneWidget);
    expect(find.byKey(const ValueKey('steam:in-use:acct_1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('steam:in-use:acct_1')),
        matching: find.textContaining('Alpha'),
      ),
      findsOneWidget,
    );
  });

  // Not a test-map row: the picker that links an account to an instance.
  testWidgets('account_picker_links_an_account', (tester) async {
    final daemon = FakeDaemon(
      instances: [makeInstance(id: 'i1', name: 'Alpha', revision: 2)],
    )..accounts = [_account('ready')];
    daemon.plugins['testgame'] = PluginDetail(
      summary: PluginSummary(
        id: 'testgame',
        name: 'Test Game',
        steamLogin: 'account',
      ),
      settingsSchema: JsonDocument(json: jsonEncode({}), schemaVersion: 7),
    );
    final harness = Harness(daemon: daemon);
    await pumpApp(
      tester,
      harness,
      const InstanceDetail(daemonId: kDevDaemonId, instanceId: 'i1'),
    );

    await tester.tap(find.byKey(const ValueKey('instance:account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('srvadmin').last);
    await tester.pumpAndSettle();

    final update = harness.daemon.updates.single;
    expect(update.instanceId, 'i1');
    expect(update.expectedRevision, Int64(2));
    expect(update.hasSteamAccountId(), isTrue);
    expect(update.steamAccountId, 'acct_1');
  });
}
