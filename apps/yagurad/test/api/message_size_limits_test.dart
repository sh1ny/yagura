import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';

void main() {
  test('oversized_request', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final instance = await api.createValheim();
    final before = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: instance.id),
    );
    final huge = '{"serverName":"${'x' * (10 * 1024 * 1024)}"}';

    final error = await failureOf(
      api.instances.updateSettings(
        pb.UpdateSettingsRequest(
          instanceId: instance.id,
          expectedRevision: Int64(1),
          settings: pb.JsonDocument(json: huge),
        ),
      ),
    );

    expect(error.code, StatusCode.resourceExhausted);
    expect(errorDetailOf(error)?.reason, 'message_too_large');
    final after = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: instance.id),
    );
    expect(after, before, reason: 'nothing was saved');
    // The server is still serving.
    expect((await api.system.getInfo(pb.GetInfoRequest())).apiVersion, '1.0');
  });

  test('paged_backlog', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final instance = await api.createValheim();
    // 5,000 lines of about 600 bytes do not fit one 1 MiB batch.
    final text = 'x' * 600;
    await eventually(
      () => logSourcesOf(api.daemon, instance.id).isNotEmpty,
      reason: 'the instance log source is attached',
    );
    final file = File(p.join(instance.directory, 'logs', 'server.log'))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(
      [for (var i = 0; i < 5000; i++) '$i $text\n'].join(),
    );
    await api.daemon.logs.pollNow(instance.id);

    final batches = await api.logs
        .backlog(pb.BacklogRequest(instanceId: instance.id, lines: 5000))
        .toList();

    expect(batches.length, greaterThan(1), reason: 'it spans several messages');
    final lines = [for (final b in batches) ...b.entries];
    expect(lines, hasLength(5000));
    expect(
      [for (final l in lines) l.text.split(' ').first],
      [for (var i = 0; i < 5000; i++) '$i'],
      reason: 'in order, no line split between messages',
    );
    expect(lines.every((l) => l.text.length > 600), isTrue);
    expect(
      batches.every((b) => b.writeToBuffer().length <= 1024 * 1024 + 4096),
      isTrue,
    );
  });
}
