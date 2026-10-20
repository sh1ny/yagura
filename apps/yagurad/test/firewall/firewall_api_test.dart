import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/firewall/rule_names.dart';

import '../support/daemon_support.dart';
import '../support/firewall_support.dart';
import '../support/secure_support.dart';

void main() {
  test('list_rules_reports_owned_unmanaged_and_missing_rules', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createInstalled(daemon);
    firewall.add('Yagura/handmade', port: '9999');
    firewall.rules.remove(ruleOf(instance.id, 'query', 'udp'));
    final harness = await SecureHarness.start(env, daemon: daemon);
    final device = await harness.pair('Laptop');
    final client = pb.FirewallClient(device.channel);

    final answer = await client.listRules(pb.ListRulesRequest());

    expect(answer.status, 'ok');
    final byName = {for (final r in answer.rules) r.name: r};
    final game = byName[ruleOf(instance.id, 'game', 'udp')]!;
    expect(
      (game.instanceId, game.portName, game.port, game.protocol),
      (instance.id, 'game', 2456, 'udp'),
    );
    expect((game.managed, game.present, game.inStep), (true, true, true));
    // Wanted but gone: listed as not present.
    final query = byName[ruleOf(instance.id, 'query', 'udp')]!;
    expect((query.managed, query.present, query.inStep), (true, false, false));
    // In the group, not ours.
    final foreign = byName['Yagura/handmade']!;
    expect((foreign.managed, foreign.present), (false, true));
    expect(byName[apiRuleName]!.port, apiPort);
  });

  test('list_rules_shows_the_actual_port_of_a_drifted_rule', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createInstalled(daemon);
    // Someone changed the rule by hand: it allows 9999, not 2456.
    final name = ruleOf(instance.id, 'game', 'udp');
    firewall.rules[name]!.port = '9999';
    final harness = await SecureHarness.start(env, daemon: daemon);
    final client = pb.FirewallClient((await harness.pair('Laptop')).channel);

    final answer = await client.listRules(pb.ListRulesRequest());

    final byName = {for (final r in answer.rules) r.name: r};
    final drifted = byName[name]!;
    expect((drifted.port, drifted.protocol), (9999, 'udp'));
    expect((drifted.present, drifted.inStep), (true, false));
    // The others are as wanted.
    final query = byName[ruleOf(instance.id, 'query', 'udp')]!;
    expect((query.present, query.inStep), (true, true));
    // After a reconcile all is in step.
    await client.reconcile(pb.ReconcileRequest());
    final later = await client.listRules(pb.ListRulesRequest());
    expect(later.rules.where((r) => r.managed && !r.inStep), isEmpty);
  });

  test('list_rules_says_when_the_firewall_is_unavailable', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall()..unavailable = 'the service is stopped';
    final daemon = await startFirewalled(env, firewall);
    final harness = await SecureHarness.start(env, daemon: daemon);
    final client = pb.FirewallClient((await harness.pair('Laptop')).channel);

    final answer = await client.listRules(pb.ListRulesRequest());

    expect(answer.status, 'firewall_unavailable');
    expect(answer.rules.where((r) => r.present), isEmpty);
  });

  test('reconcile_reports_each_change', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createInstalled(daemon);
    firewall.rules.remove(ruleOf(instance.id, 'game', 'udp'));
    final harness = await SecureHarness.start(env, daemon: daemon);
    final client = pb.FirewallClient((await harness.pair('Laptop')).channel);

    final answer = await client.reconcile(pb.ReconcileRequest());

    expect(
      {for (final c in answer.changes) c.name: c.action},
      {ruleOf(instance.id, 'game', 'udp'): 'recreated'},
    );
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
  });

  test('reconcile_fails_firewall_unavailable', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    firewall.unavailable = 'the service is stopped';
    final harness = await SecureHarness.start(env, daemon: daemon);
    final client = pb.FirewallClient((await harness.pair('Laptop')).channel);

    await expectLater(
      client.reconcile(pb.ReconcileRequest()),
      throwsA(
        isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.failedPrecondition)
            .having(reasonOf, 'reason', 'firewall_unavailable'),
      ),
    );
  });
}
