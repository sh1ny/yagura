import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';

pb.UpdateSettingsRequest save(
  pb.Instance instance, {
  required int revision,
  String name = 'Renamed',
  bool? autostart,
}) => pb.UpdateSettingsRequest(
  instanceId: instance.id,
  expectedRevision: Int64(revision),
  settings: pb.JsonDocument(json: '{"serverName":"$name"}'),
  autostart: autostart,
);

/// The `revision` metadata of the `ErrorDetail` of a failed call.
Future<String?> conflictRevision(Future<Object?> call) async {
  final detail = errorDetailOf(await failureOf(call));
  return detail?.metadata['revision'];
}

void main() {
  test('two_clients_edit_the_same_instance', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final created = await api.createValheim();
    expect(created.revision.toInt(), 1);

    final a = await api.instances.updateSettings(
      save(created, revision: 1, name: 'FromA'),
    );
    expect(a.revision.toInt(), 2);

    final b = api.instances.updateSettings(
      save(created, revision: 1, name: 'FromB'),
    );
    await expectLater(
      b,
      failsWithStatus(StatusCode.failedPrecondition, 'revision_conflict'),
    );
    expect(
      await conflictRevision(
        api.instances.updateSettings(save(created, revision: 1)),
      ),
      '2',
    );

    final now = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: created.id),
    );
    expect(now.revision.toInt(), 2);
    expect(now.settings.json, contains('FromA'));
    expect(now.settings.json, isNot(contains('FromB')));
  });

  test('runtime_state_does_not_change_the_revision', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start();
    final api = await ApiHarness.start(env, daemon: daemon);
    final created = await api.createValheim();
    final installed = daemon.instances.install(created.id);
    await daemon.operations.whenDone(installed.id);
    final started = daemon.instances.start(created.id);
    await daemon.operations.whenDone(started.id);
    env.process.servers.single.exit(1);
    await eventually(
      () =>
          env.process.launches.length == 2 &&
          daemon.instances.get(created.id).state == InstanceState.running,
      reason: 'the daemon to restart the crashed server',
    );

    expect(daemon.instances.get(created.id).revision, 1);
    final saved = await api.instances.updateSettings(
      save(created, revision: 1),
    );
    expect(saved.revision.toInt(), 2);
  });

  test('autostart_unchanged_when_omitted', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final created = await api.createValheim();
    final off = await api.instances.updateSettings(
      save(created, revision: 1, autostart: false),
    );
    expect(off.autostart, isFalse);
    expect(off.revision.toInt(), 2);

    final saved = await api.instances.updateSettings(
      save(created, revision: 2, name: 'Again'),
    );

    expect(saved.autostart, isFalse);
    expect(saved.revision.toInt(), 3);
  });

  test('current_revision_accepted', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final api = await ApiHarness.start(env, daemon: daemon);
    final created = await api.createValheim();

    final saved = await api.instances.updateSettings(
      save(created, revision: 1),
    );
    expect(saved.revision.toInt(), 2);
    expect(saved.settings.json, contains('Renamed'));

    final withSecret = await api.instances.setSecret(
      pb.SetSecretRequest(
        instanceId: created.id,
        expectedRevision: Int64(2),
        key: 'password',
        value: 'hunter2',
      ),
    );
    expect(withSecret.revision.toInt(), 3);

    final cleared = await api.instances.deleteSecret(
      pb.DeleteSecretRequest(
        instanceId: created.id,
        expectedRevision: Int64(3),
        key: 'password',
      ),
    );
    expect(cleared.revision.toInt(), 4);

    // The revision is stored: a restarted daemon reads it back.
    await env.kill(daemon);
    final restarted = await env.start();
    expect(restarted.instances.get(created.id).revision, 4);

    // A stale secret change fails and leaves the value alone.
    final again = await ApiHarness.start(env, daemon: restarted);
    await expectLater(
      again.instances.setSecret(
        pb.SetSecretRequest(
          instanceId: created.id,
          expectedRevision: Int64(3),
          key: 'password',
          value: 'late',
        ),
      ),
      failsWithStatus(StatusCode.failedPrecondition, 'revision_conflict'),
    );
    expect(restarted.instances.get(created.id).revision, 4);
  });

  test('restore_from_a_stale_view', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start(
      snapshots: DirectorySnapshotter(root: p.join(env.data, 'snapshots')),
    );
    final api = await ApiHarness.start(env, daemon: daemon);
    final created = await api.createValheim();
    final installed = daemon.instances.install(created.id);
    await daemon.operations.whenDone(installed.id);
    final save0 = File(p.join(created.directory, 'save', 'world.db'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('world v1');
    final update = daemon.instances.update(created.id);
    await daemon.operations.whenDone(update.id);
    final snapshot = daemon.instances.listSnapshots(created.id).single;
    save0.writeAsStringSync('world v2');

    // Another client saved settings: the revision is 2.
    await api.instances.updateSettings(save(created, revision: 1));
    final operationsBefore = daemon.operations
        .listForInstance(created.id)
        .length;

    final stale = api.instances.restoreSnapshot(
      pb.RestoreSnapshotRequest(
        instanceId: created.id,
        snapshotId: snapshot.id,
        expectedRevision: Int64(1),
      ),
    );
    await expectLater(
      stale,
      failsWithStatus(StatusCode.failedPrecondition, 'revision_conflict'),
    );
    expect(
      daemon.operations.listForInstance(created.id),
      hasLength(operationsBefore),
    );
    expect(save0.readAsStringSync(), 'world v2');

    // An accepted restore increments the revision with its operation, so a
    // second restore with the same revision conflicts.
    final accepted = await api.instances.restoreSnapshot(
      pb.RestoreSnapshotRequest(
        instanceId: created.id,
        snapshotId: snapshot.id,
        expectedRevision: Int64(2),
      ),
    );
    await daemon.operations.whenDone(accepted.id);
    expect(daemon.instances.get(created.id).revision, 3);
    await expectLater(
      api.instances.restoreSnapshot(
        pb.RestoreSnapshotRequest(
          instanceId: created.id,
          snapshotId: snapshot.id,
          expectedRevision: Int64(2),
        ),
      ),
      failsWithStatus(StatusCode.failedPrecondition, 'revision_conflict'),
    );
  });

  test('revision_missing', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final api = await ApiHarness.start(env, daemon: daemon);
    final created = await api.createValheim();
    Matcher missing() =>
        failsWithStatus(StatusCode.invalidArgument, 'revision_required');

    await expectLater(
      api.instances.updateSettings(save(created, revision: 0)),
      missing(),
    );
    await expectLater(
      api.instances.setSecret(
        pb.SetSecretRequest(
          instanceId: created.id,
          key: 'password',
          value: 'hunter2',
        ),
      ),
      missing(),
    );
    await expectLater(
      api.instances.deleteSecret(
        pb.DeleteSecretRequest(instanceId: created.id, key: 'password'),
      ),
      missing(),
    );
    await expectLater(
      api.instances.restoreSnapshot(
        pb.RestoreSnapshotRequest(instanceId: created.id, snapshotId: 'x'),
      ),
      missing(),
    );
    await expectLater(
      api.instances.deleteInstance(
        pb.DeleteInstanceRequest(instanceId: created.id),
      ),
      missing(),
    );

    final Instance now = daemon.instances.get(created.id);
    expect(now.revision, 1);
    expect(now.settings['password'], {'secret': true, 'set': false});
    expect(daemon.operations.listForInstance(created.id), isEmpty);
  });
}
