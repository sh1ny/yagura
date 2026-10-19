import 'package:test/test.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/firewall_support.dart';

/// Valheim with a port of purpose `rcon` added, exposed or not.
void installWithRcon(TestEnv env, {bool exposed = false}) {
  env.installValheim();
  env.editValheim(
    '    purpose: query\n',
    '    purpose: query\n'
        '  - name: rcon\n'
        '    default: 2460\n'
        '    protocol: tcp\n'
        '    purpose: rcon\n'
        '${exposed ? "    exposed: true\n" : ""}',
  );
}

void main() {
  test('default_rcon_not_exposed', () async {
    final env = TestEnv();
    installWithRcon(env);
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    await daemon.operations.whenDone(op.id);

    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
    expect(firewall.rule(ruleOf(instance.id, 'rcon', 'tcp')), isNull);
    expect(firewall.ownedPorts, isNot(contains('2460')));
    // The port itself is declared, only closed.
    final rcon = daemon.instances.get(instance.id).ports.last;
    expect((rcon.name, rcon.exposed), ('rcon', false));
  });

  test('admin_exposes_rcon', () async {
    final env = TestEnv();
    installWithRcon(env, exposed: true);
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(firewall.rule(ruleOf(instance.id, 'rcon', 'tcp')), 'tcp/2460');
    // The settings view marks the port as exposed.
    final rcon = daemon.instances.get(instance.id).ports.last;
    expect((rcon.name, rcon.exposed), ('rcon', true));
  });

  test('exposed_rcon_with_the_firewall_unavailable', () async {
    final env = TestEnv();
    installWithRcon(env, exposed: true);
    final firewall = FakeFirewall()..unavailable = 'the service is stopped';
    final daemon = await startFirewalled(env, firewall);

    final instance = await createValheim(daemon);
    final op = daemon.instances.install(instance.id);
    await daemon.operations.whenDone(op.id);

    // The setting is saved, no rule exists, the instance says why.
    final saved = daemon.instances.get(instance.id);
    expect(saved.ports.last.exposed, isTrue);
    expect(firewall.ownedNames, isEmpty);
    expect(saved.firewallStatus, 'degraded');
  });
}
