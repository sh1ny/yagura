import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/ui/mods_view.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';

Harness _harness({List<Mod> mods = const []}) {
  final daemon = FakeDaemon(
    instances: [makeInstance(id: 'i1', name: 'Alpha', revision: 3)],
  )..mods = mods;
  daemon.plugins['testgame'] = PluginDetail(
    summary: PluginSummary(
      id: 'testgame',
      name: 'Test Game',
      supportsMods: true,
    ),
    modRoles: ['client', 'server'],
  );
  return Harness(daemon: daemon);
}

Future<void> _pump(WidgetTester tester, Harness harness) => pumpApp(
  tester,
  harness,
  ModsView(daemonId: kDevDaemonId, instance: harness.daemon.instances.single),
  size: const Size(1000, 2600),
);

Mod _mod(String id, String name, {String role = 'client', int at = 0}) => Mod(
  source: 'steam_workshop',
  itemId: id,
  name: name,
  role: role,
  position: at,
  status: 'staged',
);

Finder _row(String id) => find.byKey(ValueKey('mod:$id'));

void main() {
  testWidgets('mods_added_by_id', (tester) async {
    final harness = _harness();
    await _pump(tester, harness);

    final ids = [for (var i = 0; i < 12; i++) '${1559212036 + i}'];
    await tester.enterText(
      find.byKey(const ValueKey('mods:ids')),
      ids.join('\n'),
    );
    await tester.tap(find.byKey(const ValueKey('mods:add')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('mods:save')));
    await settle(tester);

    // SetMods carries the full ordered list against the loaded revision.
    final request = harness.daemon.modSets.single;
    expect(request.instanceId, 'i1');
    expect(request.expectedRevision.toInt(), 3);
    expect([for (final m in request.mods) m.itemId], ids);
    expect(request.mods.every((m) => m.source == 'steam_workshop'), isTrue);
    expect(request.mods.every((m) => m.role == 'client'), isTrue);

    // Once the daemon has their metadata the mods show with names, pending.
    for (final id in ids) {
      expect(
        find.descendant(of: _row(id), matching: find.text('Mod $id')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row(id), matching: find.text('pending')),
        findsOneWidget,
      );
    }
  });

  testWidgets('key_conflict_shown', (tester) async {
    final harness = _harness(
      mods: [
        _mod('111', 'Community Framework'),
        _mod('222', 'Other Mod', at: 1)..warnings.add('key_conflict:CF.bikey'),
      ],
    );
    await _pump(tester, harness);

    expect(
      find.descendant(
        of: _row('222'),
        matching: find.textContaining('CF.bikey'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row('111'),
        matching: find.textContaining('CF.bikey'),
      ),
      findsNothing,
    );
  });

  testWidgets('concurrent_edit', (tester) async {
    final harness = _harness(mods: [_mod('111', 'Community Framework')]);
    await _pump(tester, harness);

    // This admin adds 333 and has not saved.
    await tester.enterText(find.byKey(const ValueKey('mods:ids')), '333');
    await tester.tap(find.byKey(const ValueKey('mods:add')));
    await settle(tester);

    // Another device saves a change first.
    harness.daemon.mods = [
      _mod('111', 'Community Framework'),
      _mod('444', 'Theirs', at: 1),
    ];
    harness.daemon.emitChanged(
      harness.daemon.instances.single.deepCopy()
        ..revision = harness.daemon.instances.single.revision + 1,
    );
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('mods:save')));
    await settle(tester);

    // Saving is refused; the list is reloaded and the unsaved change stays.
    expect(harness.daemon.modSets.single.expectedRevision.toInt(), 3);
    expect(find.byKey(const ValueKey('mods:conflict')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mods:conflict')),
        matching: find.textContaining('333'),
      ),
      findsOneWidget,
    );
    expect(harness.daemon.calls.where((c) => c == 'ListMods:i1').length, 2);
    expect(_row('333'), findsOneWidget);

    // Saving again goes against the revision just loaded.
    await tester.tap(find.byKey(const ValueKey('mods:save')));
    await settle(tester);
    expect(harness.daemon.modSets.last.expectedRevision.toInt(), 4);
    expect(find.byKey(const ValueKey('mods:conflict')), findsNothing);
  });
}
