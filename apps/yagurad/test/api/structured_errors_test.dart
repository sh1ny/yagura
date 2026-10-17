import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';

void main() {
  test('field_violation_detail', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final instance = await api.createValheim();

    final error = await failureOf(
      api.instances.updateSettings(
        pb.UpdateSettingsRequest(
          instanceId: instance.id,
          settings: pb.JsonDocument(
            json: '{"serverName":"","worldName":"not valid!"}',
          ),
        ),
      ),
    );

    expect(error.code, StatusCode.invalidArgument);
    final detail = errorDetailOf(error)!;
    expect(detail.reason, 'settings_invalid');
    final fields = {
      for (final v in detail.fieldViolations) v.field_1: v.description,
    };
    expect(fields.keys, unorderedEquals(['serverName', 'worldName']));
    expect(fields.values, everyElement(isNotEmpty));
  });

  test('unexpected_internal_failure', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    // A closed database makes the next query throw something the API does not
    // know: a bug, as far as the client is concerned.
    await api.daemon.close();

    final error = await failureOf(
      api.operations.listOperations(pb.ListOperationsRequest()),
    );

    expect(error.code, StatusCode.internal);
    final detail = errorDetailOf(error)!;
    expect(detail.reason, 'internal_error');
    expect(detail.incidentId, matches(RegExp(r'^inc-[0-9a-f]{12}$')));
    expect(
      api.logLines.where((l) => l.contains(detail.incidentId)),
      isNotEmpty,
      reason: 'the daemon log carries the incident id',
    );
    expect(
      api.logLines.firstWhere((l) => l.contains(detail.incidentId)),
      contains('#0'),
      reason: 'with the stack trace',
    );
    expect(error.message, isNot(contains('SqliteException')));
  });

  test('malformed_request_message', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final raw = ClientMethod<List<int>, List<int>>(
      '/yagura.v1.Instances/GetInstance',
      (List<int> bytes) => bytes,
      (List<int> bytes) => bytes,
    );

    // A string field announces two bytes and carries one.
    final error = await failureOf(
      ResponseFuture<List<int>>(
        api.channel.createCall<List<int>, List<int>>(
          raw,
          Stream<List<int>>.value(const [0x0a, 0x02, 0x61]),
          CallOptions(),
        ),
      ),
    );

    final detail = errorDetailOf(error);
    expect(detail, isNotNull, reason: 'every non-OK status has a detail');
    expect(detail!.reason, 'internal_error');
    expect(error.message, isNot(contains('Protocol message')));
  });
}
