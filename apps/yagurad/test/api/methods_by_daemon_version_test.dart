import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/reflection.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';

/// The cells of the M1 row of "Methods by daemon version" in
/// `docs/protocol.md`: the services served and the methods not implemented.
({String served, String missing}) m1Row() {
  final text = File('../../docs/protocol.md').readAsStringSync();
  final start = text.indexOf('## Methods by daemon version');
  expect(start, isNonNegative, reason: 'the section exists');
  final row = text
      .substring(start)
      .split('\n')
      .firstWhere((line) => line.startsWith('| M1 '));
  final cells = row.split('|').map((c) => c.trim()).toList();
  // ['', version, served, missing, '']
  return (served: cells[2], missing: cells[3]);
}

Set<String> backticked(String text) => {
  for (final m in RegExp('`([^`]+)`').allMatches(text)) m[1]!,
};

/// Calls [method] with an empty request and says whether the daemon answered
/// `UNIMPLEMENTED` / `not_implemented`. A call that gets any other answer
/// (a message, another error) or none within a second is implemented.
Future<bool> isNotImplemented(ApiHarness api, String method) async {
  final channel = api.connect();
  final call = channel.createCall(
    ClientMethod<List<int>, List<int>>(method, (r) => r, (r) => r),
    Stream.value(const <int>[]),
    CallOptions(),
  );
  final answer = Completer<bool>();
  final subscription = call.response.listen(
    (_) {
      if (!answer.isCompleted) answer.complete(false);
    },
    onError: (Object e) {
      if (answer.isCompleted) return;
      answer.complete(
        e is GrpcError &&
            e.code == StatusCode.unimplemented &&
            errorDetailOf(e)?.reason == 'not_implemented',
      );
    },
    onDone: () {
      if (!answer.isCompleted) answer.complete(false);
    },
  );
  final result = await answer.future.timeout(
    const Duration(seconds: 1),
    onTimeout: () => false,
  );
  await subscription.cancel();
  await channel.terminate();
  return result;
}

void main() {
  test('m1_row_matches_the_server', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final index = DescriptorIndex(pb.yaguraDescriptorSet);
    final services = [
      for (final s in index.services)
        if (s.startsWith('yagura.v1.')) s.substring('yagura.v1.'.length),
    ];

    // The services the row says are served (the first words of each
    // backticked name, with the stubs in parentheses).
    final row = m1Row();
    final served = backticked(row.served);
    final reflected = await api.channel
        .createCall(
          ClientMethod<pb.ServerReflectionRequest, pb.ServerReflectionResponse>(
            '/grpc.reflection.v1.ServerReflection/ServerReflectionInfo',
            (r) => r.writeToBuffer(),
            pb.ServerReflectionResponse.fromBuffer,
          ),
          Stream.value(pb.ServerReflectionRequest(listServices: '')),
          CallOptions(),
        )
        .response
        .first;
    final registered = {
      for (final s in reflected.listServicesResponse.service)
        if (s.name.startsWith('yagura.v1.'))
          s.name.substring('yagura.v1.'.length),
    };
    expect(
      registered,
      served,
      reason: 'the services in the row are the services registered',
    );
    expect(
      registered,
      unorderedEquals(services),
      reason: 'every service of the contract is registered, as a stub or not',
    );

    // The methods the row says are not implemented.
    final stubs = [
      for (final name in ['Pairing', 'Steam', 'Mods', 'Rcon', 'Firewall'])
        ...index.methods['yagura.v1.$name']!.map((m) => '$name.$m'),
    ];
    expect(
      row.missing,
      contains('Every method of the stub services'),
      reason: 'the row names the stub services as a whole',
    );
    // The first sentence of the cell lists the not-implemented methods
    // (`Service.Method`, then bare method names of the same service); the
    // next one says what SetSecret and DeleteSecret do instead.
    final sentences = row.missing.split('. ');
    final listed = <String>{};
    String? service;
    for (final token in backticked(sentences.first)) {
      if (token.contains('.')) {
        service = token.split('.').first;
        listed.add(token);
      } else if (RegExp(r'^[A-Z]\w+$').hasMatch(token) && service != null) {
        listed.add('$service.$token');
      }
    }
    final documented = {...listed, ...stubs};
    expect(
      sentences.skip(1).join('. '),
      allOf(contains('SetSecret'), contains('secret_store_unavailable')),
      reason: 'the row says what the secret methods do',
    );

    // What the server really does.
    final unimplemented = <String>{};
    for (final service in services) {
      for (final method in index.methods['yagura.v1.$service']!) {
        if (await isNotImplemented(api, '/yagura.v1.$service/$method')) {
          unimplemented.add('$service.$method');
        }
      }
    }

    expect(
      unimplemented,
      documented,
      reason:
          'the methods answering not_implemented are exactly those the M1 row '
          'lists',
    );
  });
}
