import 'dart:async';

import 'package:test/test.dart';
import 'package:yagurad/src/firewall/api_port_rule.dart';
import 'package:yagurad/src/platform/acl_writer.dart';
import 'package:yagurad/src/firewall/rule_names.dart';
import 'package:yagurad/src/service/service_control.dart';

import '../support/daemon_support.dart';
import '../support/firewall_support.dart';
import '../support/service_support.dart';

const instanceRule = 'Yagura/inst-0123456789ab/game/udp';

// `service install` and `service uninstall` and the API port rule, against
// the fake firewall. The same behaviour against the real firewall and the real
// service is the `elevated` rows in integration_test/service/.
void main() {
  late FakeFirewall firewall;
  late InstallerRig rig;

  setUp(() {
    firewall = FakeFirewall();
    rig = InstallerRig()..apiRule = FirewallApiPortRule(firewall);
  });

  test('install_creates_the_rule_for_the_bind_port', () async {
    await rig.installer.install(bind: '0.0.0.0:8443');

    expect(firewall.rule(apiRuleName), 'tcp/8443');
    expect(rig.control.calls, ['install', 'start']);
    // The command says it made the rule, before the service starts, so a row
    // can tell this from the daemon's own reconcile.
    expect(
      rig.output,
      contains('firewall rule $apiRuleName allows tcp port 8443'),
    );
  });

  test('install_leaves_the_instance_rules_alone', () async {
    firewall.add(instanceRule, port: '2456');
    firewall.add('Valheim manual', port: '2456');

    await rig.installer.install();

    expect(firewall.rule(apiRuleName), 'tcp/7443');
    expect(firewall.rule(instanceRule), 'udp/2456');
    expect(firewall.rule('Valheim manual'), 'udp/2456');
  });

  test('firewall_unavailable_at_service_install', () async {
    firewall.unavailable = 'the service is stopped';

    await rig.installer.install();

    // Installed and running; the command says the rule is missing.
    expect(rig.control.calls, ['install', 'start']);
    expect(rig.control.status('yagurad'), ServiceStatus.running);
    expect(rig.output, contains('warning'));
    expect(rig.output, contains(apiRuleName));
    expect(rig.output, contains('firewall_unavailable'));
    expect(rig.output, contains('the service is stopped'));
    expect(firewall.rules, isEmpty);

    // Once the firewall is back, the daemon's first reconcile (a service
    // start) makes the rule.
    firewall.unavailable = null;
    final env = TestEnv();
    env.installValheim();
    await startFirewalled(env, firewall, port: 7443);
    expect(firewall.rule(apiRuleName), 'tcp/7443');
  });

  test('install_warns_when_the_rule_cannot_be_set', () async {
    firewall.failing.add(apiRuleName);

    await rig.installer.install();

    expect(rig.control.calls, ['install', 'start']);
    expect(rig.control.status('yagurad'), ServiceStatus.running);
    expect(rig.output, contains('warning'));
    expect(rig.output, contains(apiRuleName));
    expect(rig.output, contains('firewall_unavailable'));
  });

  test('install_goes_on_when_the_firewall_does_not_answer', () async {
    // A script that hangs: the rule gives up at its own timeout.
    rig.apiRule = FirewallApiPortRule(
      firewall,
      timeout: const Duration(milliseconds: 200),
    );
    firewall.gate = Completer<void>();
    addTearDown(() => firewall.gate?.complete());

    await rig.installer.install().timeout(const Duration(seconds: 10));

    expect(rig.control.calls, ['install', 'start']);
    expect(rig.control.status('yagurad'), ServiceStatus.running);
    expect(rig.output, contains('firewall_unavailable'));
    expect(rig.output, contains('did not answer'));
  });

  test('install_goes_on_when_the_firewall_fails_in_any_way', () async {
    rig.apiRule = _BrokenRule();

    await rig.installer.install();

    expect(rig.control.status('yagurad'), ServiceStatus.running);
    expect(rig.output, contains('firewall_unavailable'));
    expect(rig.output, contains('cannot read the answer'));
  });

  test(
    'install_leaves_the_rule_to_the_service_that_holds_the_channel',
    () async {
      // Another service's daemon answers on the admin channel before this
      // service ever starts.
      rig.foreignDaemon = true;

      await rig.installer.install();

      expect(firewall.calls, isEmpty);
      expect(rig.output, contains('another Yagura service'));
      expect(rig.output, contains(apiRuleName));
      expect(rig.control.calls, ['install', 'start']);
    },
  );

  test(
    'uninstall_keeps_the_rule_of_the_service_that_holds_the_channel',
    () async {
      await rig.installer.install();
      expect(firewall.rule(apiRuleName), 'tcp/7443');
      firewall.calls.clear();
      // This service is stopped by the uninstall; another one answers.
      rig.foreignDaemon = true;

      await rig.installer.uninstall();

      expect(rig.control.status('yagurad'), ServiceStatus.notInstalled);
      expect(firewall.rule(apiRuleName), 'tcp/7443');
      expect(firewall.calls, isEmpty);
      expect(rig.output, contains('kept the firewall rule $apiRuleName'));
      expect(rig.output, contains('another Yagura service'));
    },
  );

  test('uninstall_does_not_use_a_root_that_is_no_longer_protected', () async {
    await rig.installer.install();
    firewall.calls.clear();
    // Someone replaced the folder: users can write in it now.
    rig.acl.overrides[rig.layout.root] = const EntrySecurity(
      isLink: false,
      sddl: 'O:BUD:P(A;OICI;FA;;;BU)',
    );

    await rig.installer.uninstall();

    // The service is removed; no PowerShell request was made.
    expect(rig.control.status('yagurad'), ServiceStatus.notInstalled);
    expect(firewall.calls, isEmpty);
    expect(firewall.rule(apiRuleName), 'tcp/7443');
    expect(rig.output, contains('warning'));
    expect(rig.output, contains('not the protected folder'));
  });

  test('uninstall_removes_the_rule_and_only_that', () async {
    await rig.installer.install();
    expect(firewall.rule(apiRuleName), 'tcp/7443');
    firewall.add(instanceRule, port: '2456');
    firewall.add('Valheim manual', port: '2456');
    firewall.add('Yagura/handmade', port: '7443', protocol: 'tcp');

    await rig.installer.uninstall();

    expect(firewall.rule(apiRuleName), isNull);
    expect(firewall.rule(instanceRule), 'udp/2456');
    expect(firewall.rule('Valheim manual'), 'udp/2456');
    expect(firewall.rule('Yagura/handmade'), 'tcp/7443');
  });

  test('uninstall_still_removes_the_service_without_a_firewall', () async {
    await rig.installer.install();
    expect(firewall.rule(apiRuleName), 'tcp/7443');
    firewall.unavailable = 'the service is stopped';

    await rig.installer.uninstall();

    expect(rig.control.status('yagurad'), ServiceStatus.notInstalled);
    expect(rig.output, contains('warning'));
    expect(rig.output, contains(apiRuleName));
    expect(rig.output, contains('firewall_unavailable'));
  });
}

/// A rule whose firewall fails with something other than
/// [FirewallUnavailable].
class _BrokenRule implements ApiPortRule {
  @override
  Future<void> ensure(int port) async =>
      throw const FormatException('cannot read the answer');

  @override
  Future<void> remove() async =>
      throw const FormatException('cannot read the answer');
}
