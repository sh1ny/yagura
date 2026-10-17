import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';

void main() {
  test('method_not_built_yet', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final instance = await api.createValheim();
    final before = await api.instances.listInstances(pb.ListInstancesRequest());

    await expectLater(
      api.instances.exportInstance(
        pb.ExportInstanceRequest(instanceId: instance.id),
      ),
      failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
    );

    final after = await api.instances.listInstances(pb.ListInstancesRequest());
    expect(after, before, reason: 'nothing changes');
  });

  test('service_not_built_yet', () async {
    final env = TestEnv();
    final api = await ApiHarness.start(env);
    final mods = pb.ModsClient(api.channel);

    final error = await failureOf(mods.listMods(pb.ListModsRequest()));

    expect(error.code, StatusCode.unimplemented);
    expect(errorDetailOf(error)!.reason, 'not_implemented');
  });
}
