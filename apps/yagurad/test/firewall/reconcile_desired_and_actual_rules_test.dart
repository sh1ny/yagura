import 'dart:async';

import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/firewall/rule_names.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/firewall_support.dart';

void changePorts(Daemon daemon, String id, Map<String, int> ports) {
  final current = daemon.instances.get(id);
  daemon.instances.updateSettings(
    UpdateSettingsRequest(
      instanceId: id,
      settings: {'serverName': 'Friends'},
      ports: ports,
      expectedRevision: current.revision,
    ),
  );
}

void main() {
  test('port_change_on_a_stopped_instance', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createInstalled(daemon);
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');

    changePorts(daemon, instance.id, {'game': 2466});
    await daemon.firewall!.whenIdle;

    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2466');
    expect(firewall.rule(ruleOf(instance.id, 'query', 'udp')), 'udp/2467');
    expect(firewall.ownedPorts, isNot(contains('2456')));
    expect(firewall.ownedPorts, isNot(contains('2457')));
  });

  test('port_change_on_a_running_instance', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createRunning(daemon);

    changePorts(daemon, instance.id, {'game': 2466});
    await daemon.firewall!.whenIdle;

    // The server still listens on the ports it was launched with.
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
    expect(daemon.instances.get(instance.id).restartRequired, isTrue);

    final restart = daemon.instances.restart(instance.id);
    final done = await daemon.operations.whenDone(restart.id);
    expect(done.status, OperationStatus.succeeded);

    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2466');
    expect(firewall.rule(ruleOf(instance.id, 'query', 'udp')), 'udp/2467');
    expect(daemon.instances.get(instance.id).restartRequired, isFalse);
  });

  test('dev_mode_manages_no_rules', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    // A development daemon, even given a firewall, never touches it.
    final daemon = await env.start(firewall: firewall);
    final instance = await createInstalled(daemon);

    expect(daemon.firewall, isNull);
    expect(firewall.calls, isEmpty);
    expect(firewall.rules, isEmpty);
    expect(daemon.instances.get(instance.id).firewallStatus, 'disabled');

    final api = await ApiHarness.start(env, daemon: daemon);
    final health = await api.system.getHealth(pb.GetHealthRequest());
    expect(health.notBuilt, contains('firewall'));
  });

  test('reconcile_times_out', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(
      env,
      firewall,
      firewallTimeout: const Duration(milliseconds: 300),
    );
    final instance = await createInstalled(daemon);
    expect(firewall.ownedNames, hasLength(3));

    // The script hangs: the next reconcile fails at its timeout.
    firewall.gate = Completer<void>();
    changePorts(daemon, instance.id, {'game': 2466});
    final result = await daemon.firewall!.request().timeout(
      const Duration(seconds: 5),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('did not answer'));
    // Nothing was deleted, the instance says so, health agrees.
    expect(firewall.ownedNames, hasLength(3));
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
    expect(daemon.instances.get(instance.id).firewallStatus, 'degraded');
    expect(daemon.firewall!.ok, isFalse);

    // The next reconcile runs normally.
    firewall.gate!.complete();
    firewall.gate = null;
    final again = await daemon.firewall!.request();
    expect(again.ok, isTrue);
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2466');
    expect(daemon.instances.get(instance.id).firewallStatus, 'ok');
    expect(daemon.firewall!.ok, isTrue);
  });

  test('rules_follow_the_launched_ports_across_a_daemon_restart', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final first = await startFirewalled(env, firewall);
    final instance = await createRunning(first);
    final server = env.process.servers.single;
    changePorts(first, instance.id, {'game': 2466});
    await first.firewall!.whenIdle;
    await env.kill(first);
    env.process.survivors.add(server);

    // The new daemon re-attaches the server; the run record, not the saved
    // settings, says which ports it listens on.
    final second = await startFirewalled(env, firewall);

    expect(second.instances.get(instance.id).state, InstanceState.running);
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
    expect(firewall.rule(ruleOf(instance.id, 'query', 'udp')), 'udp/2457');
    final stop = second.instances.stop(instance.id);
    await second.operations.whenDone(stop.id);
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2466');
  });

  test('an_operation_waits_for_the_reconcile_but_only_so_long', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(
      env,
      firewall,
      firewallTimeout: const Duration(milliseconds: 300),
    );
    final instance = await createValheim(daemon);
    firewall.gate = Completer<void>();
    addTearDown(() => firewall.gate?.complete());

    final watch = Stopwatch()..start();
    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    // Two reconcile timeouts at most: the one in flight, then its own.
    expect(done.status, OperationStatus.succeeded);
    expect(done.warnings, contains('firewall_unavailable'));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('stop_and_delete_move_the_rules_and_say_when_they_cannot', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createRunning(daemon);
    firewall.unavailable = 'the service is stopped';

    final stop = daemon.instances.stop(instance.id);
    final stopped = await daemon.operations.whenDone(stop.id);
    expect(stopped.warnings, contains('firewall_unavailable'));
    expect(daemon.instances.get(instance.id).firewallStatus, 'degraded');

    firewall.unavailable = null;
    final delete = daemon.instances.delete(instance.id);
    final deleted = await daemon.operations.whenDone(delete.id);
    expect(deleted.warnings, isNot(contains('firewall_unavailable')));
    expect(firewall.ownedNames, [apiRuleName]);
  });

  test('a_failed_install_leaves_no_rules', () async {
    final env = TestEnv();
    env.installValheim();
    final firewall = FakeFirewall();
    final daemon = await startFirewalled(env, firewall);
    final instance = await createValheim(daemon);
    env.steam.failure = YaguraException('steamcmd_unavailable', 'no steam');

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);
    await daemon.firewall!.whenIdle;

    expect(done.status, OperationStatus.failed);
    expect(firewall.ownedNames, [apiRuleName]);
  });
}
