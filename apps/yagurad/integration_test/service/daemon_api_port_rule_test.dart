@Timeout(Duration(minutes: 8))
library;

import 'package:test/test.dart';
import 'package:yagurad/src/firewall/rule_names.dart';

import '../../test/support/firewall_elevated_support.dart';
import '../../test/support/service_rig.dart';

// The API port rule of design D11 with the real service and the real Windows
// Firewall. (An unavailable firewall cannot be made on a real host: the
// Windows Firewall service is protected and refuses to stop. That scenario is
// `firewall_unavailable_at_service_install` in
// test/firewall/api_port_rule_install_test.dart, with the fake firewall.)
// These rows install a throwaway service and change firewall rules,
// so they run only in the manual `elevated` workflow.

Future<ServiceRig> rigWithoutInstances() async {
  final rig = await ServiceRig.create(instances: 0);
  // The daemon of a service owns the rule; leave none behind.
  addTearDown(removeYaguraGroup);
  return rig;
}

Future<bool> apiRuleAllows(int port) async =>
    await describeRule(apiRuleName) ==
    '$apiRuleName|Yagura|True|Inbound|Allow|TCP|$port';

void main() {
  test('fresh_host_reachable_after_install', tags: ['elevated'], () async {
    final rig = await rigWithoutInstances();
    await removeYaguraGroup();

    final install = await rig.install();

    // An inbound TCP rule for the bind port, in the group, from the install.
    expect(await apiRuleAllows(rig.port), isTrue, reason: '${install.stdout}');
    expect('${install.stdout}', isNot(contains('warning')));
    // And the daemon agrees.
    expect(await rig.daemonStatus(), contains('api_port_rule: present'));
  });

  test('port_changed', tags: ['elevated'], () async {
    final rig = await rigWithoutInstances();
    await removeYaguraGroup();
    await rig.install();
    expect(await apiRuleAllows(rig.port), isTrue);

    final other = rig.port + 1;
    final configure = await rig.service([
      'configure',
      '--bind',
      '127.0.0.1:$other',
    ]);
    expect(configure.exitCode, 0, reason: '${configure.stderr}');
    await rig.restart();

    await eventually(
      () => apiRuleAllows(other),
      reason: 'the rule to follow the new port',
    );
    // No owned rule allows the old port.
    final ports = await groupPorts();
    expect(
      ports.entries.where((e) => e.value.split(',').contains('${rig.port}')),
      isEmpty,
      reason: '$ports',
    );
  });
}
