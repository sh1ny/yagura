import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_world.dart';

/// Opens the pairing dialog, enters [pairingString] and [deviceName] and
/// submits.
Future<void> pairThroughTheUi(
  WidgetTester tester,
  String pairingString, {
  String deviceName = 'my-laptop',
}) async {
  await tester.tap(find.byKey(const ValueKey('action:pair')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('pair:string')),
    pairingString,
  );
  await tester.enterText(find.byKey(const ValueKey('pair:name')), deviceName);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('pair:submit')));
  await settleAll(tester);
}

/// The text of the pairing dialog's error line, or null when there is none.
String? pairingError(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('pair:error'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}
