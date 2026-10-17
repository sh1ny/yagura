import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';

/// Asks the reflection service on [path] (the v1 or v1alpha name) for
/// [requests].
Future<List<pb.ServerReflectionResponse>> reflect(
  ApiHarness api,
  String service,
  List<pb.ServerReflectionRequest> requests,
) {
  final method =
      ClientMethod<pb.ServerReflectionRequest, pb.ServerReflectionResponse>(
        '/$service/ServerReflectionInfo',
        (r) => r.writeToBuffer(),
        pb.ServerReflectionResponse.fromBuffer,
      );
  return api.channel
      .createCall(method, Stream.fromIterable(requests), CallOptions())
      .response
      .toList();
}

void main() {
  group('System', () {
    test('GetInfo names the versions and dev mode', () async {
      final api = await ApiHarness.start(TestEnv());

      final info = await api.system.getInfo(pb.GetInfoRequest());

      expect(info.apiVersions, ['1.0']);
      expect(info.apiVersion, '1.0');
      expect(info.daemonVersion, isNotEmpty);
      expect(info.devMode, isTrue);
      expect(info.os, 'windows');
      expect(info.dataDir, isNotEmpty);
      expect(info.hasStartedAt(), isTrue);
    });

    test('GetHealth reports what this version does not build', () async {
      final api = await ApiHarness.start(TestEnv());

      final health = await api.system.getHealth(pb.GetHealthRequest());

      expect(health.databaseOk, isTrue);
      expect(health.notBuilt, unorderedEquals(['secret_store', 'firewall']));
      expect(health.leakedHookWorkers, 0);
      expect(health.hooksDegraded, isFalse);
    });

    test('ListAudit is not built', () async {
      final api = await ApiHarness.start(TestEnv());

      await expectLater(
        api.system.listAudit(pb.ListAuditRequest()),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
    });
  });

  group('Instances', () {
    test('SetSecret fails secret_store_unavailable', () async {
      final env = TestEnv()..installValheim();
      final api = await ApiHarness.start(env);
      final instance = await api.createValheim();

      await expectLater(
        api.instances.setSecret(
          pb.SetSecretRequest(
            instanceId: instance.id,
            key: 'password',
            value: 'hunter2',
          ),
        ),
        failsWithStatus(
          StatusCode.failedPrecondition,
          'secret_store_unavailable',
        ),
      );
      await expectLater(
        api.instances.deleteSecret(
          pb.DeleteSecretRequest(instanceId: instance.id, key: 'password'),
        ),
        failsWithStatus(
          StatusCode.failedPrecondition,
          'secret_store_unavailable',
        ),
      );
    });

    test('revision is always 0 and expected_revision is not checked', () async {
      final env = TestEnv()..installValheim();
      final api = await ApiHarness.start(env);
      final instance = await api.createValheim();
      expect(instance.revision.toInt(), 0);

      final updated = await api.instances.updateSettings(
        pb.UpdateSettingsRequest(
          instanceId: instance.id,
          expectedRevision: Int64(99),
          settings: pb.JsonDocument(json: '{"serverName":"Other"}'),
        ),
      );

      expect(updated.revision.toInt(), 0);
      expect(updated.settings.json, contains('Other'));
    });

    test('an unknown instance is NOT_FOUND instance_not_found', () async {
      final api = await ApiHarness.start(TestEnv());

      await expectLater(
        api.instances.getInstance(pb.GetInstanceRequest(instanceId: 'nope')),
        failsWithStatus(StatusCode.notFound, 'instance_not_found'),
      );
    });

    test('the other not-built methods fail not_implemented', () async {
      final env = TestEnv()..installValheim();
      final api = await ApiHarness.start(env);
      final instance = await api.createValheim();

      await expectLater(
        api.instances.importInstance(pb.ImportInstanceRequest()),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
      await expectLater(
        api.instances.applyConfig(pb.LifecycleRequest(instanceId: instance.id)),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
      await expectLater(
        api.operations.respondToPrompt(pb.RespondToPromptRequest()),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
    });
  });

  group('stub services', () {
    test('every method of every stub service is not_implemented', () async {
      final api = await ApiHarness.start(TestEnv());
      final channel = api.channel;

      await expectLater(
        pb.PairingClient(channel).listDevices(pb.ListDevicesRequest()),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
      await expectLater(
        pb.SteamClient(channel).listAccounts(pb.ListAccountsRequest()),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
      await expectLater(
        pb.RconClient(channel).execute(pb.ExecuteRequest()),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
      await expectLater(
        pb.RconClient(channel).console(Stream.empty()).toList(),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
      await expectLater(
        pb.FirewallClient(channel).listRules(pb.ListRulesRequest()),
        failsWithStatus(StatusCode.unimplemented, 'not_implemented'),
      );
    });
  });

  group('Logs.Follow', () {
    test('delivers new lines with their source', () async {
      final env = TestEnv()..installValheim();
      final api = await ApiHarness.start(env);
      final instance = await api.createValheim();
      await eventually(
        () => logSourcesOf(api.daemon, instance.id).isNotEmpty,
        reason: 'the log source is attached',
      );
      final batches = <pb.LogBatch>[];
      final subscription = api.logs
          .follow(pb.FollowRequest(instanceId: instance.id))
          .listen(batches.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final file = File(p.join(instance.directory, 'logs', 'server.log'))
        ..parent.createSync(recursive: true);
      file.writeAsStringSync('hello\nworld\n');
      await api.daemon.logs.pollNow(instance.id);
      await eventually(
        () => batches.expand((b) => b.entries).length >= 2,
        reason: 'two lines',
      );

      final entries = batches.expand((b) => b.entries).toList();
      expect([for (final e in entries) e.text], ['hello', 'world']);
      expect(entries.every((e) => e.source == 'server'), isTrue);
    });
  });

  group('reflection', () {
    test('lists every served service', () async {
      final env = TestEnv();
      final api = await ApiHarness.start(env);

      final responses = await reflect(
        api,
        'grpc.reflection.v1.ServerReflection',
        [pb.ServerReflectionRequest(listServices: '')],
      );

      final names = [
        for (final s in responses.single.listServicesResponse.service) s.name,
      ];
      expect(
        names,
        containsAll([
          'yagura.v1.System',
          'yagura.v1.Plugins',
          'yagura.v1.Instances',
          'yagura.v1.Operations',
          'yagura.v1.Logs',
          'yagura.v1.Pairing',
          'yagura.v1.Steam',
          'yagura.v1.Mods',
          'yagura.v1.Rcon',
          'yagura.v1.Firewall',
        ]),
      );
    });

    test('describes a service with its dependencies', () async {
      final api = await ApiHarness.start(TestEnv());

      final responses = await reflect(
        api,
        'grpc.reflection.v1.ServerReflection',
        [
          pb.ServerReflectionRequest(
            fileContainingSymbol: 'yagura.v1.Instances',
          ),
          pb.ServerReflectionRequest(
            fileContainingSymbol: 'yagura.v1.CreateInstanceRequest',
          ),
          pb.ServerReflectionRequest(fileContainingSymbol: 'yagura.v1.Nothing'),
        ],
      );

      final files = responses.first.fileDescriptorResponse.fileDescriptorProto;
      expect(files, isNotEmpty);
      expect(
        files.any(
          (f) => String.fromCharCodes(f).contains('yagura/v1/instances.proto'),
        ),
        isTrue,
      );
      expect(
        files.any(
          (f) => String.fromCharCodes(f).contains('yagura/v1/common.proto'),
        ),
        isTrue,
        reason: 'imports travel with the file',
      );
      expect(
        responses[1].fileDescriptorResponse.fileDescriptorProto,
        isNotEmpty,
      );
      expect(responses[2].hasErrorResponse(), isTrue);
      expect(responses[2].errorResponse.errorCode, StatusCode.notFound);
    });

    test('answers under the v1alpha name too', () async {
      final api = await ApiHarness.start(TestEnv());

      final responses = await reflect(
        api,
        'grpc.reflection.v1alpha.ServerReflection',
        [pb.ServerReflectionRequest(listServices: '')],
      );

      expect(
        responses.single.listServicesResponse.service.map((s) => s.name),
        contains('yagura.v1.Instances'),
      );
    });
  });
}
