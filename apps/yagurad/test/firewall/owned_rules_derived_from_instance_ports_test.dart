import 'package:test/test.dart';
import 'package:yagurad/src/firewall/rule_names.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/firewall_support.dart';

void main() {
  test('rules_created_after_install', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(done.warnings, isNot(contains('firewall_unavailable')));
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
    expect(firewall.rule(ruleOf(instance.id, 'query', 'udp')), 'udp/2457');
    expect(daemon.instances.get(instance.id).firewallStatus, 'ok');
    expect(daemon.firewall!.ok, isTrue);
    // The daemon's own API port is kept next to them.
    expect(firewall.rule(apiRuleName), 'tcp/$apiPort');
    expect(firewall.ownedNames, hasLength(3));
  });

  test('not_installed_has_no_rules', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);

    final instance = await createValheim(daemon);
    await daemon.firewall!.request();

    expect(
      firewall.ownedNames.where((name) => name.contains(instance.id)),
      isEmpty,
    );
    expect(firewall.ownedNames, [apiRuleName]);
    expect(daemon.instances.get(instance.id).firewallStatus, 'ok');
  });

  test('firewall_service_unavailable', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall()..unavailable = 'the service is stopped';
    final daemon = await startFirewalled(env, firewall);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    // The operation continues, and says so.
    expect(done.status, OperationStatus.succeeded);
    expect(done.warnings, contains('firewall_unavailable'));
    expect(firewall.ownedNames, isEmpty);
    expect(daemon.instances.get(instance.id).firewallStatus, 'degraded');
    expect(daemon.firewall!.ok, isFalse);

    // Until a reconcile succeeds.
    firewall.unavailable = null;
    final result = await daemon.firewall!.request();
    expect(result.ok, isTrue);
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
    expect(daemon.instances.get(instance.id).firewallStatus, 'ok');
    expect(daemon.firewall!.ok, isTrue);
  });
}
