@Tags(['windows'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/admin/named_pipe.dart';
import 'package:yagurad/src/firewall/rule_names.dart';

import '../support/admin_support.dart';
import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/firewall_support.dart';
import '../support/temp_support.dart';

// Design D11: a host runs one Yagura service, and the service manages the
// group `Yagura`. The admin channel check is a safety net for a second daemon
// that got there anyway: it manages nothing only when a trusted Yagura daemon
// holds the channel, and manages the group in every other case.
void main() {
  test('a_trusted_daemon_holding_the_channel_keeps_the_rules', () async {
    final pipe = testPipeName();
    final firewall = FakeFirewall();

    // The service holds the channel and its rules.
    final env = TestEnv();
    env.installValheim();
    final first = await startFirewalled(env, firewall, pipe: pipe);
    final mine = await createInstalled(first);
    final before = Map.of(firewall.rules.map((k, v) => MapEntry(k, '$v')));
    expect(firewall.rule(ruleOf(mine.id, 'game', 'udp')), 'udp/2456');
    expect(before.containsKey(apiRuleName), isTrue);
    firewall.calls.clear();

    // A second daemon finds the name taken by a Yagura daemon it trusts.
    final otherEnv = TestEnv();
    otherEnv.installValheim();
    final second = await startFirewalled(
      otherEnv,
      firewall,
      pipe: pipe,
      port: apiPort + 1,
      adminProbe: () => NamedPipeConnector(name: pipe, verifier: (_) => true),
    );

    expect(second.adminChannelOk, isFalse);
    expect(second.firewall, isNull);
    final notices = second.startupNotices.where((n) => n.step == 'firewall');
    expect(notices.single.message, contains('another Yagura daemon'));
    // It reconciled nothing, at startup or after.
    final theirs = await createInstalled(second);
    expect(firewall.calls, isEmpty);
    expect(firewall.rule(ruleOf(mine.id, 'game', 'udp')), 'udp/2456');
    expect(firewall.rule(ruleOf(theirs.id, 'game', 'udp')), isNull);
    expect(firewall.rule(apiRuleName), 'tcp/$apiPort');

    final api = await ApiHarness.start(otherEnv, daemon: second);
    final health = await api.system.getHealth(pb.GetHealthRequest());
    expect(health.firewallOk, isFalse);
    expect(second.instances.get(theirs.id).firewallStatus, 'disabled');
  });

  test('an_untrusted_squatter_does_not_stop_the_management', () async {
    final pipe = testPipeName();
    final firewall = FakeFirewall();
    // Some process, not a Yagura daemon, took the pipe name.
    final squatter = NamedPipeListener(name: pipe, sddl: currentUserPipeSddl());
    await squatter.open();
    addTearDown(squatter.close);

    final env = TestEnv();
    env.installValheim();
    // The real trust check: the holder is not LocalSystem, so not trusted.
    final daemon = await startFirewalled(
      env,
      firewall,
      pipe: pipe,
      adminProbe: () => NamedPipeConnector(name: pipe),
    );

    expect(daemon.adminChannelOk, isFalse);
    expect(daemon.firewall, isNotNull);
    expect(
      daemon.startupNotices.map((n) => n.step),
      contains('admin_channel_squatted'),
    );
    expect(daemon.startupNotices.where((n) => n.step == 'firewall'), isEmpty);
    // It manages the rules: the API port rule exists, and so do instances'.
    expect(firewall.rule(apiRuleName), 'tcp/$apiPort');
    final instance = await createInstalled(daemon);
    expect(firewall.rule(ruleOf(instance.id, 'game', 'udp')), 'udp/2456');
  });

  test('the_admin_channel_answers_only_once_startup_has_finished', () async {
    final pipe = testPipeName();
    final firewall = FakeFirewall()..gate = Completer<void>();
    final env = TestEnv();
    env.installValheim();

    // The startup reconcile hangs on the gate; the pipe is open already.
    final starting = startFirewalled(
      env,
      firewall,
      pipe: pipe,
      adminStartupWait: const Duration(seconds: 20),
    );
    final connector = NamedPipeConnector(name: pipe, verifier: (_) => true);
    // The pipe is open once the startup reconcile is under way (it is the
    // step after the channel opens). Ask now: the request is held.
    while (firewall.calls.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final answered = <CliResult>[];
    final asked = runYagurad(['status'], connector).then(answered.add);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(answered, isEmpty, reason: 'ready is after the first reconcile');

    firewall.gate!.complete();
    final daemon = await starting;
    await asked;
    expect(answered.single.code, 0, reason: '${answered.single}');
    expect(answered.single.out, contains('api_port_rule'));
    expect(daemon.adminChannelOk, isTrue);
  });

  test('a_request_during_a_slow_start_is_refused_and_does_nothing', () async {
    final pipe = testPipeName();
    final firewall = FakeFirewall()..gate = Completer<void>();
    final env = TestEnv();
    env.installValheim();
    final root = createCanonicalTempSync('yagurad_root_');
    addTearDown(() => root.deleteSync(recursive: true));
    final starting = startFirewalled(
      env,
      firewall,
      pipe: pipe,
      adminStartupWait: const Duration(milliseconds: 300),
    );
    while (firewall.calls.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final connector = NamedPipeConnector(name: pipe, verifier: (_) => true);

    final added = await runYagurad(['roots', 'add', root.path], connector);
    final status = await runYagurad(['status'], connector);

    expect(added.code, isNot(0));
    expect(added.err, contains('daemon_starting'));
    expect(status.err, contains('daemon_starting'));

    // The refused request left no trace: the root was not added later.
    firewall.gate!.complete();
    final daemon = await starting;
    final list = await runYagurad(['roots', 'list'], connector);
    expect(list.code, 0, reason: '$list');
    expect(list.out, isNot(contains(root.path)));
    expect(daemon.adminChannelOk, isTrue);
  });
}
