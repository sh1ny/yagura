import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/firewall_support.dart';

/// Valheim with a port of purpose `rcon` added, closed by its declaration.
void installWithRcon(TestEnv env) {
  env.installValheim();
  env.editValheim(
    '    purpose: query\n',
    '    purpose: query\n'
        '  - name: rcon\n'
        '    default: 2460\n'
        '    protocol: tcp\n'
        '    purpose: rcon\n',
  );
}

/// The admin's per-instance choice: `ports.rcon.exposed: true`.
Instance exposeRcon(Daemon daemon, Instance instance, {bool exposed = true}) =>
    daemon.instances.updateSettings(
      UpdateSettingsRequest(
        instanceId: instance.id,
        settings: instance.settings,
        exposure: {'rcon': exposed},
      ),
    );

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
    installWithRcon(env);
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createValheim(daemon);
    exposeRcon(daemon, instance);

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
    installWithRcon(env);
    final firewall = FakeFirewall()..unavailable = 'the service is stopped';
    final daemon = await startFirewalled(env, firewall);

    final instance = await createValheim(daemon);
    exposeRcon(daemon, instance);
    final op = daemon.instances.install(instance.id);
    await daemon.operations.whenDone(op.id);

    // The setting is saved, no rule exists, the instance says why.
    final saved = daemon.instances.get(instance.id);
    expect(saved.ports.last.exposed, isTrue);
    expect(firewall.ownedNames, isEmpty);
    expect(saved.firewallStatus, 'degraded');
  });

  test('rcon_exposure_survives_other_settings_and_can_be_closed', () async {
    final env = TestEnv();
    installWithRcon(env);
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createValheim(daemon);
    final saved = exposeRcon(daemon, instance);

    // Saving settings again, with no exposure given, keeps the choice.
    final again = daemon.instances.updateSettings(
      UpdateSettingsRequest(instanceId: saved.id, settings: saved.settings),
    );
    expect(again.ports.last.exposed, isTrue);

    final closed = exposeRcon(daemon, again, exposed: false);
    expect(closed.ports.last.exposed, isFalse);
  });

  test('rcon_exposed_through_the_update_settings_call', () async {
    final env = TestEnv();
    installWithRcon(env);
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final harness = await ApiHarness.start(env, daemon: daemon);
    final instance = await harness.createValheim();

    final updated = await harness.instances.updateSettings(
      pb.UpdateSettingsRequest(
        instanceId: instance.id,
        expectedRevision: instance.revision,
        settings: pb.JsonDocument(json: '{"serverName":"Friends"}'),
        ports: [pb.Port(name: 'rcon', number: 2460, exposed: true)],
      ),
    );

    expect(updated.ports.last.exposed, isTrue);
    await daemon.operations.whenDone(daemon.instances.install(instance.id).id);
    expect(firewall.rule(ruleOf(instance.id, 'rcon', 'tcp')), 'tcp/2460');
  });
}
