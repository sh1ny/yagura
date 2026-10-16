import 'package:fixnum/fixnum.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart';

void main() {
  test('Instance survives a binary round trip', () {
    final instance = Instance(
      id: 'inst-1',
      name: 'Valheim',
      pluginId: 'valheim',
      pluginVersion: '1.0.0',
      directory: r'C:\yagura\instances\valheim',
      state: InstanceState.INSTANCE_STATE_RUNNING,
      health: Health.HEALTH_OK,
      ports: [
        Port(
          name: 'game',
          number: 2456,
          protocol: Protocol.PROTOCOL_UDP,
          purpose: 'game',
        ),
      ],
      settings: JsonDocument(json: '{"world":"Dedicated"}', schemaVersion: 7),
      createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 17)),
      pid: 4242,
      revision: Int64(0),
      autostart: true,
    );

    final decoded = Instance.fromBuffer(instance.writeToBuffer());

    expect(decoded, instance);
    expect(decoded.ports.single.number, 2456);
    expect(decoded.settings.schemaVersion, 7);
    expect(decoded.createdAt.toDateTime(), DateTime.utc(2026, 10, 17));
  });
}
