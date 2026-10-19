@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/firewall/firewall_backend.dart';
import 'package:yagurad/src/firewall/firewall_reconciler.dart';
import 'package:yagurad/src/firewall/powershell_firewall.dart';
import 'package:yagurad/src/firewall/rule_names.dart';

import '../../test/support/firewall_elevated_support.dart';

// The reconcile script of design D11 against the real Windows Firewall. These
// rows create, change and delete rules, so they run only in the manual
// `elevated` workflow, never on a developer's desktop. Each row names its
// rules after an instance id of its own and removes exactly those.

// The runner's temp folder belongs to its administrator, as the data
// directory belongs to SYSTEM and Administrators in the service.
final backend = PowerShellFirewall(
  directory: p.join(Directory.systemTemp.path, 'yagurad_firewall_requests'),
);
const _timeout = Duration(seconds: 60);

DesiredRule desired(String id, String port, int number, {String? protocol}) =>
    DesiredRule(
      owner: id,
      portName: port,
      protocol: protocol ?? 'udp',
      port: number,
    );

String ruleOf(String id, String port, String protocol) =>
    buildRuleName(RuleName(owner: id, portName: port, protocol: protocol));

/// A cleanup for the rules of [id], run even when the row fails.
String ownRules(String id) {
  addTearDown(() => removeRules('Yagura/$id/'));
  return id;
}

/// Prints what the script says about its run as greppable lines:
/// `FIREWALL_SCRIPT_<RUN>_<PHASE>_MS` and `FIREWALL_SCRIPT_<RUN>_FALLBACKS`.
void printScript(String run, Map<String, Object?> diagnostics) {
  if (diagnostics['timings'] case final Map<Object?, Object?> timings) {
    for (final entry in timings.entries) {
      print(
        'FIREWALL_SCRIPT_${run}_${'${entry.key}'.toUpperCase()}_MS=${entry.value}',
      );
    }
  }
  print('FIREWALL_SCRIPT_${run}_FALLBACKS=${diagnostics['fallbacks']}');
  print('FIREWALL_SCRIPT_${run}_JOINED_BY_NAME=${diagnostics['joinedByName']}');
}

void main() {
  test('admins_own_rule_untouched', tags: ['elevated'], () async {
    final id = ownRules(freshInstanceId());
    final manual = freshRuleName('Valheim manual');
    await createRule(manual, port: 2456);
    final before = await describeRule(manual);
    expect(before, isNotNull);
    await backend.reconcile([desired(id, 'game', 2456)], timeout: _timeout);
    expect(
      await describeRule(ruleOf(id, 'game', 'udp')),
      '${ruleOf(id, 'game', 'udp')}|Yagura|True|Inbound|Allow|UDP|2456',
    );

    // The instance on 2456 is deleted: its rule goes, the admin's stays.
    final outcome = await backend.reconcile(const [], timeout: _timeout);

    expect(
      outcome.changes.map((c) => '$c'),
      contains('deleted ${ruleOf(id, 'game', 'udp')}'),
    );
    expect(await describeRule(ruleOf(id, 'game', 'udp')), isNull);
    expect(await describeRule(manual), before);
    expect(outcome.unmanaged, isNot(contains(manual)));
  });

  test('foreign_rule_inside_the_group', tags: ['elevated'], () async {
    final id = ownRules(freshInstanceId());
    final handmade = freshRuleName('Yagura handmade');
    await createRule(handmade, group: 'Yagura', port: 2456);
    // A rule whose name differs from an owned one only in case: the firewall
    // compares names without case, the daemon must not.
    final lookalike = 'yagura/$id/game/udp';
    await createRule(lookalike, group: 'Yagura', port: 3333);
    final handmadeBefore = await describeRule(handmade);
    final lookalikeBefore = await describeRule(lookalike);
    expect(handmadeBefore, isNotNull);
    expect(lookalikeBefore, isNotNull);

    final outcome = await backend.reconcile(const [], timeout: _timeout);

    expect(outcome.unmanaged, containsAll([handmade, lookalike]));
    expect(outcome.changes.map((c) => c.name), isNot(contains(handmade)));
    expect(outcome.changes.map((c) => c.name), isNot(contains(lookalike)));
    expect(await describeRule(handmade), handmadeBefore);
    expect(await describeRule(lookalike), lookalikeBefore);
    // The listing says the same: in the group, not the daemon's.
    final listed = {
      for (final r in await backend.list(timeout: _timeout)) r.name: r,
    };
    expect(listed[handmade]!.owned, isFalse);
    expect(listed[lookalike]!.owned, isFalse);
    expect(listed[handmade]!.port, '2456');
    expect(listed[handmade]!.protocol, 'udp');
  });

  test('rule_deleted_by_hand', tags: ['elevated'], () async {
    final id = ownRules(freshInstanceId());
    List<DesiredRule> wanted() => [desired(id, 'game', 2456)];
    final first = FirewallReconciler(
      backend: backend,
      desired: wanted,
      timeout: _timeout,
    );
    expect((await first.request()).ok, isTrue);
    final name = ruleOf(id, 'game', 'udp');
    expect(await describeRule(name), isNotNull);

    await removeRules(name);
    expect(await describeRule(name), isNull);

    // The daemon restarts: a new reconciler, its first run.
    final restarted = FirewallReconciler(
      backend: backend,
      desired: wanted,
      timeout: _timeout,
    );
    final result = await restarted.request();

    expect(result.ok, isTrue, reason: result.error);
    expect(
      {
        for (final c in result.changes)
          if (c.name == name) c.name: c.action,
      },
      {name: 'recreated'},
    );
    expect(
      await describeRule(name),
      '$name|Yagura|True|Inbound|Allow|UDP|2456',
    );
  });

  test('a_run_changes_a_port_and_a_protocol', tags: ['elevated'], () async {
    final id = ownRules(freshInstanceId());
    final udp = ruleOf(id, 'game', 'udp');
    final tcp = ruleOf(id, 'game', 'tcp');
    await backend.reconcile([desired(id, 'game', 2456)], timeout: _timeout);

    // The port changes: the rule is changed in place.
    final moved = await backend.reconcile([
      desired(id, 'game', 2466),
    ], timeout: _timeout);
    expect(moved.changes.map((c) => '$c'), ['updated $udp']);
    expect(await describeRule(udp), '$udp|Yagura|True|Inbound|Allow|UDP|2466');

    // The protocol is part of the rule's name (D11), so changing it is the
    // old rule going and a new one coming.
    final switched = await backend.reconcile([
      desired(id, 'game', 2466, protocol: 'tcp'),
    ], timeout: _timeout);
    expect(switched.changes.map((c) => '$c'), ['deleted $udp', 'created $tcp']);
    expect(await describeRule(udp), isNull);
    expect(await describeRule(tcp), '$tcp|Yagura|True|Inbound|Allow|TCP|2466');
  });

  test(
    'remove_deletes_only_the_named_owned_rules',
    tags: ['elevated'],
    () async {
      final id = ownRules(freshInstanceId());
      final handmade = freshRuleName('Yagura handmade');
      await createRule(handmade, group: 'Yagura', port: 2456);
      await backend.reconcile(
        [desired(id, 'game', 2456), desired(id, 'query', 2457)],
        timeout: _timeout,
        prune: false,
      );

      final changes = await backend.remove([
        ruleOf(id, 'game', 'udp'),
        handmade,
      ], timeout: _timeout);

      expect(
        {for (final c in changes) c.name: c.action},
        {ruleOf(id, 'game', 'udp'): 'deleted', handmade: 'failed'},
      );
      expect(await describeRule(ruleOf(id, 'game', 'udp')), isNull);
      expect(await describeRule(ruleOf(id, 'query', 'udp')), isNotNull);
      expect(await describeRule(handmade), isNotNull);
    },
  );

  // Design D11, task 10.2: one reconcile over 300 rules. Over 10 s the design
  // is revisited before the reconciler is wired to every trigger. The numbers
  // are printed for the workflow log and recorded in docs/milestones/m2.md.
  // The 300 rules are made by a separate process, not the reconciler, so a slow
  // create does not hide the runs measured, which use the real script.
  test('reconcile_300_rules_timing', tags: ['elevated'], () async {
    const long = Duration(minutes: 8);
    final id = freshInstanceId();
    List<DesiredRule> all() => [
      for (var i = 0; i < 300; i++)
        desired(id, 'p${i.toString().padLeft(3, '0')}', 20000 + i),
    ];

    final setup = await createRulesViaCmdlet(
      id: id,
      count: 300,
      firstPort: 20000,
    );
    print('FIREWALL_RECONCILE_300_SETUP_MS=${setup.inMilliseconds}');
    print('FIREWALL_NEW_AVG_MS=${setup.inMilliseconds / 300}');
    // Where the time goes, with the 300 rules present; before any expect, so
    // that it always prints.
    for (final line in await measureFirewall()) {
      print(line);
    }
    // The read side alone: the same read and join as a reconcile, no change.
    final listing = Stopwatch()..start();
    final listed = await backend.inspect(timeout: long);
    listing.stop();
    print('FIREWALL_RECONCILE_300_LIST_MS=${listing.elapsedMilliseconds}');
    printScript('LIST', PowerShellFirewall.diagnosticsOf(listed));

    // The measured run: 300 rules present, a few ports changed, a few rules
    // gone, a few new, the rest unchanged, as after an edit. The timeout is
    // long so that the number comes out even when it is over the budget.
    final next = all()
      ..removeRange(290, 300)
      ..replaceRange(0, 5, [
        for (var i = 0; i < 5; i++)
          desired(id, 'p${i.toString().padLeft(3, '0')}', 30000 + i),
      ])
      ..addAll([
        for (var i = 0; i < 5; i++) desired(id, 'n${i.toString()}', 40000 + i),
      ]);
    final watch = Stopwatch()..start();
    final outcome = await backend.reconcile(next, timeout: long);
    watch.stop();
    print('FIREWALL_RECONCILE_300_MS=${watch.elapsedMilliseconds}');
    printScript('EDIT', outcome.diagnostics);

    // And the run that changes nothing, the common one.
    final idle = Stopwatch()..start();
    final none = await backend.reconcile(next, timeout: long);
    idle.stop();
    print('FIREWALL_RECONCILE_300_IDLE_MS=${idle.elapsedMilliseconds}');
    printScript('IDLE', none.diagnostics);

    expect(await groupRuleNames('Yagura/$id/'), hasLength(295));
    final actions = <String, int>{};
    for (final c in outcome.changes) {
      actions[c.action] = (actions[c.action] ?? 0) + 1;
    }
    expect(actions, {'updated': 5, 'deleted': 10, 'created': 5});
    expect(none.changes, isEmpty);

    // D11: over 10 s, stop and revisit the design with the user.
    expect(
      watch.elapsedMilliseconds,
      lessThan(10000),
      reason: 'one reconcile over 300 rules took more than 10 s',
    );
  });
}
