@Timeout(Duration(minutes: 12))
library;

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../../test/support/account_support.dart';
import '../../test/support/elevated_support.dart';
import '../../test/support/firewall_elevated_support.dart';
import '../../test/support/service_client.dart';
import '../../test/support/service_rig.dart';

// The agent's M2 exit criteria (openspec/roadmap.md, task 12.6) end to end:
// "A game server runs as `yagura-srv`, and its ports are open in the firewall
// only while its instance exists" and "A revoked device's next call fails",
// with the real service, its account, the real Windows Firewall and a paired
// client. The test-map rows prove the parts; this runs them as one. It installs a throwaway service, creates accounts and changes
// firewall rules, so it runs only in the manual `elevated` workflow, on its
// runner, never on a developer's desktop.

const _firstLogon = Duration(minutes: 5);

void main() {
  test('server_account_ports_and_revocation', tags: ['elevated'], () async {
    final rig = await ServiceRig.create(instances: 1);
    addTearDown(removeYaguraGroup);
    await rig.install();
    await rig.whenServersAttached(1, timeout: _firstLogon);

    // The server the service started runs as the game-server account.
    final pid = rig.runningServers().values.single;
    expect(await processOwnerSid(pid), await accountSid('yagura-srv'));

    final client = await ServiceClient.pair(rig);
    final instance = (await client.instances.listInstances(
      pb.ListInstancesRequest(),
    )).instances.single;
    final prefix = 'Yagura/${instance.id}/';

    // Its ports are open while it exists: running...
    final open = await groupRuleNames(prefix);
    expect(open, isNotEmpty, reason: 'no rule under $prefix');
    expect(
      (await groupPorts()).entries
          .where((e) => e.key.startsWith(prefix))
          .map((e) => e.value),
      contains('2456'),
    );

    // ...and stopped.
    await client.succeeded(
      await client.instances.stop(pb.LifecycleRequest(instanceId: instance.id)),
    );
    expect(await groupRuleNames(prefix), unorderedEquals(open));

    // Deleted: its rules go, and nothing else of the group changes.
    final others = (await groupRuleNames('Yagura/'))
        .where((name) => !name.startsWith(prefix))
        .toList();
    await client.succeeded(
      await client.instances.deleteInstance(
        pb.DeleteInstanceRequest(
          instanceId: instance.id,
          // The revision this client last read (concurrent edits, M2).
          expectedRevision: (await client.instances.getInstance(
            pb.GetInstanceRequest(instanceId: instance.id),
          )).revision,
        ),
      ),
    );
    await eventually(
      () async => (await groupRuleNames(prefix)).isEmpty,
      reason: 'the rules under $prefix to go',
    );
    expect(await groupRuleNames('Yagura/'), unorderedEquals(others));

    // A revoked device's next call fails.
    final revoked = await runCommand(rig.bundleExecutable, [
      'devices',
      'revoke',
      'elevated-test',
    ], timeout: const Duration(seconds: 30));
    expect(revoked.exitCode, 0, reason: '${revoked.stdout}${revoked.stderr}');
    await expectLater(
      client.instances.listInstances(pb.ListInstancesRequest()),
      throwsA(isA<GrpcError>()),
    );
  });
}
