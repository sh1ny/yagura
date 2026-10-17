import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/log_buffer.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/ui/log_view.dart';

import 'support/fake_daemon.dart';

Future<LogViewController> _pumpLogs(
  WidgetTester tester,
  Harness harness,
) async {
  final controller = LogViewController(
    connection: harness.connection,
    instanceId: 'i1',
  );
  await pumpApp(
    tester,
    harness,
    LogView(daemonId: kDevDaemonId, instanceId: 'i1', controller: controller),
  );
  controller.start();
  addTearDown(controller.dispose);
  await settle(tester);
  return controller;
}

List<String> _lineTexts(LogViewController c) => [
  for (final item in c.items)
    if (item is LogLineItem) item.text,
];

void main() {
  testWidgets('follow_and_pause', (tester) async {
    final harness = Harness();
    harness.daemon.backlogBatches.add(logBatch([1, 2]));
    final controller = await _pumpLogs(tester, harness);
    expect(find.text('line 1'), findsOneWidget);
    expect(find.text('line 2'), findsOneWidget);

    harness.daemon.emitLog(logBatch([3]));
    await settle(tester);
    expect(find.text('line 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log:pause')));
    await settle(tester);
    harness.daemon.emitLog(logBatch([4, 5, 6]));
    await settle(tester);

    // Counted but not appended.
    expect(find.text('line 4'), findsNothing);
    expect(controller.heldLines, 3);
    expect(find.textContaining('3 new lines'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log:pause')));
    await settle(tester);
    expect(_lineTexts(controller), [
      'line 1',
      'line 2',
      'line 3',
      'line 4',
      'line 5',
      'line 6',
    ]);
    expect(find.text('line 6'), findsOneWidget);
    expect(controller.heldLines, 0);
  });

  testWidgets('a_line_in_both_backlog_and_follow_shows_once', (tester) async {
    final harness = Harness();
    final gate = harness.daemon.backlogGate = Completer<void>();
    harness.daemon.backlogBatches.add(logBatch([1, 2]));
    final controller = await _pumpLogs(tester, harness);

    // Line 2 reached the follower while the backlog was still loading.
    harness.daemon.emitLog(logBatch([2, 3]));
    await settle(tester);
    gate.complete();
    await settle(tester);

    expect(_lineTexts(controller), ['line 1', 'line 2', 'line 3']);
  });

  testWidgets('dropped_lines_marker', (tester) async {
    final harness = Harness();
    final controller = await _pumpLogs(tester, harness);

    harness.daemon.emitLog(logBatch([10, 11]));
    harness.daemon.emitLog(logBatch([60], dropped: 42));
    await settle(tester);

    expect(find.textContaining('42 lines skipped'), findsOneWidget);
    // The notice sits between the lines before and after the gap.
    expect(controller.items.map((i) => i.runtimeType), [
      LogLineItem,
      LogLineItem,
      DroppedNotice,
      LogLineItem,
    ]);
  });

  testWidgets('pause_longer_than_the_buffer', (tester) async {
    final harness = Harness();
    final controller = await _pumpLogs(tester, harness);

    await tester.tap(find.byKey(const ValueKey('log:pause')));
    await settle(tester);
    for (var start = 1; start <= 15000; start += 500) {
      harness.daemon.emitLog(
        logBatch(Iterable.generate(500, (i) => start + i)),
      );
    }
    await settle(tester);
    expect(find.text('line 1'), findsNothing);
    expect(controller.heldLines, 10000);

    await tester.tap(find.byKey(const ValueKey('log:pause')));
    await settle(tester);

    expect(find.textContaining('5000 lines skipped'), findsOneWidget);
    final items = controller.items;
    expect(items.first, isA<DroppedNotice>());
    expect((items.first as DroppedNotice).count, 5000);
    final texts = _lineTexts(controller);
    expect(texts, hasLength(10000));
    expect(texts.first, 'line 5001');
    expect(texts.last, 'line 15000');
    expect(texts, [for (var n = 5001; n <= 15000; n++) 'line $n']);
  });

  group('LogBuffer', () {
    test('holds_new_lines_while_paused_and_releases_them_in_order', () {
      final buffer = LogBuffer(maxHeld: 3)
        ..add(const LogLineItem(source: 's', text: 'a', sequence: 1))
        ..pause()
        ..add(const LogLineItem(source: 's', text: 'b', sequence: 2))
        ..add(const DroppedNotice(7))
        ..add(const LogLineItem(source: 's', text: 'c', sequence: 3));
      expect(buffer.items, hasLength(1));
      expect(buffer.heldLines, 2);
      buffer.resume();
      expect(buffer.items.map((i) => i.runtimeType), [
        LogLineItem,
        LogLineItem,
        DroppedNotice,
        LogLineItem,
      ]);
    });
  });

  testWidgets('search_filters_the_loaded_lines', (tester) async {
    final harness = Harness();
    harness.daemon.backlogBatches.add(logBatch([1, 2, 21, 22]));
    final controller = await _pumpLogs(tester, harness);

    controller.search = 'line 2';
    await settle(tester);
    expect(_lineTexts(controller), ['line 2', 'line 21', 'line 22']);
    expect(find.text('line 1'), findsNothing);

    controller.search = '';
    await settle(tester);
    expect(_lineTexts(controller), hasLength(4));
  });
}
