import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';

const value = 'hunter2-never-leaves';

void main() {
  test('no_read_path_for_secrets', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final api = await ApiHarness.start(env, daemon: daemon);
    final created = await api.createValheim();
    await api.instances.setSecret(
      pb.SetSecretRequest(
        instanceId: created.id,
        expectedRevision: Int64(1),
        key: 'password',
        value: value,
      ),
    );

    final get = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: created.id),
    );
    final list = await api.instances.listInstances(pb.ListInstancesRequest());
    final watched = await take(
      api.instances.watchInstances(pb.WatchInstancesRequest()),
      1,
    );

    for (final read in [get, list, ...watched]) {
      expect(read.writeToJson(), isNot(contains(value)));
    }
    expect(
      get.settings.json,
      contains('"password":{"secret":true,"set":true}'),
    );
  });

  test('secret_store_fails_on_write', () async {
    final env = TestEnv()..installValheim();
    final protector = FlakySecretProtector(devSid);
    final daemon = await env.start(secretProtector: protector);
    final api = await ApiHarness.start(env, daemon: daemon);
    final created = await api.createValheim();
    await api.instances.setSecret(
      pb.SetSecretRequest(
        instanceId: created.id,
        expectedRevision: Int64(1),
        key: 'password',
        value: 'old',
      ),
    );
    protector.failWrites = true;

    await expectLater(
      api.instances.setSecret(
        pb.SetSecretRequest(
          instanceId: created.id,
          expectedRevision: Int64(2),
          key: 'password',
          value: 'new',
        ),
      ),
      failsWithStatus(
        StatusCode.failedPrecondition,
        'secret_store_unavailable',
      ),
    );

    final after = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: created.id),
    );
    expect(after.settings.json, contains('"set":true'));
  });
}
