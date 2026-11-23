import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/instances_api.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/api_support.dart';
import '../support/content_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';

import 'package:yagurad/src/mods/mod_check_schedule.dart';

/// What a `WatchInstances` subscriber has received so far.
class Watcher {
  Watcher(Stream<pb.InstanceEvent> stream) {
    subscription = stream.listen(
      events.add,
      onError: (Object e) => error = e,
      onDone: () => done = true,
    );
    addTearDown(subscription.cancel);
  }

  final events = <pb.InstanceEvent>[];
  late final StreamSubscription<pb.InstanceEvent> subscription;
  Object? error;
  var done = false;

  Future<void> until(
    bool Function(List<pb.InstanceEvent> events) test, {
    String? reason,
  }) async {
    await eventually(() => error != null || test(events), reason: reason);
    if (error != null) fail('the stream failed: $error');
  }

  Iterable<pb.InstanceEvent> get changes => events.where((e) => e.hasChanged());
}

pb.WatchInstancesRequest watchRequest() => pb.WatchInstancesRequest();

/// Renames the instance in the daemon. The stream tests generate many
/// changes at once, so they skip the revision check that a client's
/// concurrent saves would trip.
Future<void> rename(Daemon daemon, String instanceId, String name) async {
  final instance = daemon.instances.get(instanceId);
  daemon.instances.updateSettings(
    UpdateSettingsRequest(
      instanceId: instanceId,
      settings: {...instance.settings, 'serverName': name},
    ),
  );
}

void main() {
  test('mod_update_count_delta', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.item(vppMod, title: 'VPP');
    final a = await rig.instance(name: 'Alpha');
    await rig.setMods(a, [ModSpec(cfMod), ModSpec(vppMod)]);
    await rig.apply(a);
    rig.workshop.items[cfMod]!.timeUpdated = 1700500000;
    rig.workshop.items[vppMod]!.timeUpdated = 1700500000;

    // The daemon starts again; its first scheduled check finds both.
    await rig.restart(
      schedule: const ModCheckSchedule(
        first: Duration(milliseconds: 600),
        interval: Duration(hours: 1),
        jitter: Duration.zero,
      ),
    );
    final watcher = Watcher(rig.grpc.instances.watchInstances(watchRequest()));
    await watcher.until((e) => e.isNotEmpty);
    expect(
      watcher.events.first.snapshot.instances.single.modsUpdateAvailable,
      0,
    );

    await watcher.until(
      (e) => e.any((x) => x.hasChanged() && x.changed.modsUpdateAvailable == 2),
      reason: 'a delta with the update count',
    );
    final delta = watcher.changes.firstWhere(
      (e) => e.changed.modsUpdateAvailable == 2,
    );
    expect(delta.changed.id, a.id);
    expect(delta.changed.settingsOmitted, isTrue);
  });

  test('snapshot_then_deltas', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start();
    final a = await createInstalled(daemon, name: 'Alpha');
    await createInstalled(daemon, name: 'Beta', ports: {'game': 3456});
    final api = await ApiHarness.start(env, daemon: daemon);

    final watcher = Watcher(api.instances.watchInstances(watchRequest()));
    await watcher.until((e) => e.isNotEmpty, reason: 'the snapshot');
    // Another client starts instance A.
    final operation = await api.instances.start(
      pb.LifecycleRequest(instanceId: a.id),
    );
    expect(operation.id, isNotEmpty);
    await watcher.until(
      (e) => e.any(
        (x) =>
            x.hasChanged() &&
            x.changed.state == pb.InstanceState.INSTANCE_STATE_RUNNING,
      ),
      reason: 'A running',
    );

    expect(watcher.events.first.hasSnapshot(), isTrue);
    expect(
      watcher.events.first.snapshot.instances.map((i) => i.name),
      unorderedEquals(['Alpha', 'Beta']),
      reason: 'the full instance list first',
    );
    final states = [
      for (final e in watcher.changes.where((e) => e.changed.id == a.id))
        e.changed.state,
    ];
    expect(
      states,
      containsAllInOrder([
        pb.InstanceState.INSTANCE_STATE_STARTING,
        pb.InstanceState.INSTANCE_STATE_RUNNING,
      ]),
    );
  });

  test('state_only_delta', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start();
    final a = await createInstalled(daemon, name: 'Alpha');
    final api = await ApiHarness.start(env, daemon: daemon);
    final watcher = Watcher(api.instances.watchInstances(watchRequest()));
    await watcher.until((e) => e.isNotEmpty);
    expect(
      watcher.events.first.snapshot.instances.single.hasSettings(),
      isTrue,
      reason: 'the snapshot carries settings',
    );

    // M1 has no health data, so the state changes while settings do not.
    await api.instances.start(pb.LifecycleRequest(instanceId: a.id));
    await watcher.until(
      (e) => e.any(
        (x) =>
            x.hasChanged() &&
            x.changed.state == pb.InstanceState.INSTANCE_STATE_RUNNING,
      ),
    );

    for (final delta in watcher.changes) {
      expect(delta.changed.settingsOmitted, isTrue);
      expect(delta.changed.hasSettings(), isFalse);
    }

    // A settings change carries the new document.
    await rename(daemon, a.id, 'Renamed');
    await watcher.until(
      (e) => e.any((x) => x.hasChanged() && x.changed.hasSettings()),
      reason: 'a delta with settings',
    );
    final withSettings = watcher.changes.firstWhere(
      (e) => e.changed.hasSettings(),
    );
    expect(withSettings.changed.settingsOmitted, isFalse);
    expect(withSettings.changed.settings.json, contains('Renamed'));
  });

  test('slow_subscriber', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start();
    final a = await createInstalled(daemon, name: 'Alpha');
    final api = await ApiHarness.start(env, daemon: daemon);
    final slow = Watcher(
      pb.InstancesClient(api.connect()).watchInstances(watchRequest()),
    );
    await slow.until((e) => e.isNotEmpty);

    // It stops reading while far more than 1,000 events are produced (some
    // fill the transport's buffers before any queue in the daemon), sent 20
    // at a time so a slow CI disk stays inside the timeout; the last rename
    // is sent alone, so it is the final state.
    slow.subscription.pause();
    for (var i = 0; i < 1800; i += 20) {
      await Future.wait([
        for (var j = i; j < i + 20; j++) rename(daemon, a.id, 'Name$j'),
      ]);
    }
    await rename(daemon, a.id, 'NameFinal');
    final beforeResume = slow.events.length;
    slow.subscription.resume();
    await slow.until(
      (e) => e.any((x) => x.hasResyncRequired()),
      reason: 'resync_required',
    );
    await slow.until(
      (e) => e
          .skipWhile((x) => !x.hasResyncRequired())
          .any((x) => x.hasSnapshot()),
      reason: 'a fresh snapshot after resync_required',
    );

    final events = slow.events;
    final resync = events.indexWhere((e) => e.hasResyncRequired());
    expect(events[resync + 1].hasSnapshot(), isTrue);
    // Events that arrived after the drop follow the snapshot, so the
    // subscriber ends on the current state.
    await slow.until(
      (e) =>
          e.last.hasChanged() &&
          e.last.changed.settings.json.contains('NameFinal'),
      reason: 'the last state',
    );
    expect(
      events.length - beforeResume,
      lessThan(1500),
      reason: 'the backlog was dropped, not delivered',
    );
    // Live deltas continue after the snapshot.
    await rename(daemon, a.id, 'Last');
    await slow.until(
      (e) =>
          e.last.hasChanged() && e.last.changed.settings.json.contains('Last'),
      reason: 'a live delta after the resync',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('slow_subscriber_by_bytes', () async {
    final env = TestEnv()..installValheim();
    final daemon = await env.start();
    final a = await createInstalled(daemon, name: 'Alpha');
    // A byte bound far below the 8 MiB default, so a few hundred events
    // cross it before the event count does.
    final api = await ApiHarness.start(
      env,
      daemon: daemon,
      watchLimits: const WatchLimits(maxBytes: 100 * 1024),
    );
    final slow = Watcher(
      pb.InstancesClient(api.connect()).watchInstances(watchRequest()),
    );
    await slow.until((e) => e.isNotEmpty);

    slow.subscription.pause();
    for (var i = 0; i < 600; i++) {
      await rename(daemon, a.id, 'Name$i');
    }
    slow.subscription.resume();

    await slow.until(
      (e) => e.any((x) => x.hasResyncRequired()),
      reason: 'resync_required',
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('too_many_subscribers', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(
      env,
      watchLimits: const WatchLimits(maxSubscribers: 2),
    );
    final first = Watcher(api.instances.watchInstances(watchRequest()));
    final second = Watcher(api.instances.watchInstances(watchRequest()));
    await first.until((e) => e.isNotEmpty);
    await second.until((e) => e.isNotEmpty);

    final third = Watcher(api.instances.watchInstances(watchRequest()));
    await eventually(() => third.error != null || third.done);

    expect(third.error, isA<GrpcError>());
    expect((third.error! as GrpcError).code, StatusCode.resourceExhausted);
    expect(
      errorDetailOf(third.error! as GrpcError)?.reason,
      'too_many_subscribers',
    );

    // A slot frees up when a subscriber leaves.
    await first.subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final fourth = Watcher(api.instances.watchInstances(watchRequest()));
    await fourth.until((e) => e.isNotEmpty);
  });
}
