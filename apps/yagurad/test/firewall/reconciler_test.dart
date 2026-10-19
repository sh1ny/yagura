import 'dart:async';

import 'package:test/test.dart';
import 'package:yagurad/src/firewall/firewall_backend.dart';
import 'package:yagurad/src/firewall/firewall_reconciler.dart';

import '../support/firewall_support.dart';

const idA = 'inst-0123456789ab';
const idB = 'inst-ba9876543210';

DesiredRule rule(String owner, String name, int port, {String? protocol}) =>
    DesiredRule(
      owner: owner,
      portName: name,
      protocol: protocol ?? 'udp',
      port: port,
    );

void main() {
  late FakeFirewall firewall;
  late List<DesiredRule> desired;
  late FirewallReconciler reconciler;

  FirewallReconciler make({Duration timeout = const Duration(seconds: 2)}) =>
      FirewallReconciler(
        backend: firewall,
        desired: () => List.of(desired),
        timeout: timeout,
      );

  setUp(() {
    firewall = FakeFirewall();
    desired = [rule(idA, 'game', 2456), rule(idA, 'query', 2457)];
    reconciler = make();
  });

  test('requests_while_a_reconcile_runs_coalesce_into_one_more', () async {
    firewall.gate = Completer<void>();
    final first = reconciler.request();
    final later = [for (var i = 0; i < 5; i++) reconciler.request()];
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // One script at a time, the rest wait behind it.
    expect(firewall.calls, ['reconcile']);

    firewall.gate!.complete();
    final results = await Future.wait([first, ...later]);

    expect(firewall.calls, ['reconcile', 'reconcile']);
    expect(firewall.maxConcurrent, 1);
    for (final result in results.skip(1)) {
      expect(result, same(results[1]));
    }
    await reconciler.whenIdle;
  });

  test('the_pending_reconcile_reads_the_state_when_it_starts', () async {
    firewall.gate = Completer<void>();
    final first = reconciler.request();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = reconciler.request();

    desired = [rule(idA, 'game', 2466)];
    firewall.gate!.complete();
    await Future.wait([first, second]);

    expect(firewall.reconciles.first, hasLength(2));
    expect(firewall.reconciles.last.map((r) => '$r'), [
      '${ruleOf(idA, 'game', 'udp')} -> 2466',
    ]);
    expect(firewall.ownedNames, [ruleOf(idA, 'game', 'udp')]);
    expect(firewall.rule(ruleOf(idA, 'game', 'udp')), 'udp/2466');
  });

  test('creates_updates_and_deletes_are_reported', () async {
    final first = await reconciler.request();
    expect(first.ok, isTrue);
    expect(first.changes.map((c) => c.action).toSet(), {'recreated'});

    desired = [rule(idA, 'game', 2466), rule(idB, 'game', 2456)];
    final second = await reconciler.request();

    expect(
      {for (final c in second.changes) c.name: c.action},
      {
        ruleOf(idA, 'game', 'udp'): 'updated',
        ruleOf(idA, 'query', 'udp'): 'deleted',
        ruleOf(idB, 'game', 'udp'): 'created',
      },
    );
  });

  test('a_rule_that_disappeared_is_recreated_not_created', () async {
    await reconciler.request();
    firewall.rules.remove(ruleOf(idA, 'game', 'udp'));

    final result = await reconciler.request();

    expect(
      {for (final c in result.changes) c.name: c.action},
      {ruleOf(idA, 'game', 'udp'): 'recreated'},
    );
    expect(firewall.rule(ruleOf(idA, 'game', 'udp')), 'udp/2456');
  });

  test('both_protocols_are_two_rules', () async {
    desired = [
      rule(idA, 'game', 2456, protocol: 'udp'),
      rule(idA, 'game', 2456, protocol: 'tcp'),
    ];

    await reconciler.request();

    expect(firewall.rule(ruleOf(idA, 'game', 'udp')), 'udp/2456');
    expect(firewall.rule(ruleOf(idA, 'game', 'tcp')), 'tcp/2456');
  });

  test('a_failure_degrades_the_owners_and_deletes_nothing', () async {
    await reconciler.request();
    expect(reconciler.ok, isTrue);
    firewall.unavailable = 'the service is stopped';
    desired = [rule(idB, 'game', 2456)];

    final result = await reconciler.request();

    expect(result.ok, isFalse);
    expect(result.error, contains('the service is stopped'));
    expect(reconciler.ok, isFalse);
    expect(reconciler.isDegraded(idB), isTrue);
    expect(reconciler.isDegraded(idA), isFalse);
    expect(firewall.ownedNames, hasLength(2));

    firewall.unavailable = null;
    expect((await reconciler.request()).ok, isTrue);
    expect(reconciler.ok, isTrue);
    expect(reconciler.isDegraded(idB), isFalse);
  });

  test('a_rule_that_cannot_be_created_degrades_only_its_instance', () async {
    desired = [rule(idA, 'game', 2456), rule(idB, 'game', 2456)];
    firewall.failing.add(ruleOf(idB, 'game', 'udp'));

    final result = await reconciler.request();

    expect(result.ok, isFalse);
    expect(reconciler.isDegraded(idB), isTrue);
    expect(reconciler.isDegraded(idA), isFalse);
    expect(firewall.rule(ruleOf(idA, 'game', 'udp')), 'udp/2456');
  });

  test('a_rule_outside_the_scheme_is_reported_and_left_alone', () async {
    firewall.add('Yagura/handmade', port: '2456');
    firewall.add('Valheim manual', port: '2456');

    final result = await reconciler.request();

    expect(result.unmanaged, ['Yagura/handmade', 'Valheim manual']);
    expect(firewall.rule('Yagura/handmade'), 'udp/2456');
    expect(firewall.rule('Valheim manual'), 'udp/2456');
    desired = [];
    await reconciler.request();
    expect(firewall.rule('Yagura/handmade'), 'udp/2456');
  });

  test('an_operation_waits_at_most_twice_the_timeout', () async {
    reconciler = make(timeout: const Duration(milliseconds: 150));
    firewall.gate = Completer<void>();
    final running = reconciler.request();
    final watch = Stopwatch()..start();

    final result = await reconciler.requestAndWait();

    // The running one gives up at its timeout, then the operation's own run
    // gives up at its own: the call never takes longer than both.
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 250)),
    );
    expect(result.ok, isFalse);
    expect((await running).ok, isFalse);
    firewall.gate!.complete();
  });

  test('no_second_script_starts_while_a_timed_out_one_still_ends', () async {
    // The hung script outlives its timeout by 400 ms (the process is being
    // killed): the next run, queued behind it, must wait for it to end.
    reconciler = make(timeout: const Duration(milliseconds: 200));
    firewall.gate = Completer<void>();
    firewall.killDelay = const Duration(milliseconds: 400);
    final first = reconciler.request();
    final queued = reconciler.request();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // The first has timed out and is being killed; a new request still waits.
    firewall.gate = null;

    final results = await Future.wait([first, queued]);

    expect(results.first.ok, isFalse);
    expect(results.last.ok, isTrue);
    expect(firewall.maxConcurrent, 1);
    expect(firewall.calls, ['reconcile', 'reconcile']);
  });
}
