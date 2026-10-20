import 'dart:async';

import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

/// The wire name of the operation a version change queues.
const migrateKind = 'migrate_settings';

/// Plugin `valheim` at 0.2.0, with `worldName` renamed `world`.
void renameWorldSetting(TestEnv env) {
  env.editValheim('version: 0.1.0', 'version: 0.2.0');
  env.editValheim('  worldName:', '  world:');
  env.editValheim('{{settings.worldName}}', '{{settings.world}}');
}

/// Plugin `valheim` at 0.2.0, whose `serverName` takes at least 12 characters
/// (its default is longer, so the manifest stays valid).
void lengthenServerName(TestEnv env) {
  env.editValheim('version: 0.1.0', 'version: 0.2.0');
  env.editValheim('min: 1', 'min: 12');
}

/// The migrations queued for [id] so far, oldest first.
List<Operation> migrationsOf(Daemon daemon, String id) => [
  for (final op in daemon.operations.listForInstance(id))
    if (op.kind.wireName == migrateKind) op,
];

/// Reloads the plugins and waits for the migration of [id] to end.
Future<Operation> reloadAndMigrate(Daemon daemon, String id) async {
  await daemon.instances.reloadPlugins();
  final migration = migrationsOf(daemon, id).last;
  return daemon.operations.whenDone(migration.id);
}

/// Hooks that rename `worldName` to `world`, and refuse the instance `Bad`.
const renameHook = '''
exports.migrateSettings = function (ctx) {
  if (ctx.settings.serverName === 'Bad') throw new Error('cannot migrate Bad');
  const settings = Object.assign({}, ctx.settings);
  settings.world = settings.worldName;
  delete settings.worldName;
  return { settings: settings };
};
''';

void main() {
  test('removed_setting_migrated', () async {
    final env = TestEnv();
    env.installValheim(hooks: renameHook);
    final daemon = await env.start();
    final created = await createValheim(
      daemon,
      settings: {'serverName': 'Friends', 'worldName': 'Alpha'},
    );
    await daemon.operations.whenDone(daemon.instances.install(created.id).id);
    final before = daemon.instances.get(created.id);

    renameWorldSetting(env);
    final done = await reloadAndMigrate(daemon, created.id);

    expect(done.status, OperationStatus.succeeded);
    final after = daemon.instances.get(created.id);
    expect(after.settings, containsPair('world', 'Alpha'));
    expect(after.settings, isNot(contains('worldName')));
    expect(after.pluginVersion, '0.2.0');
    expect(after.state, InstanceState.stopped);
    expect(after.settingsInvalid, isFalse);
    expect(after.revision, before.revision + 1);
  });

  test('running_instance_after_an_invalidating_reload', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    final notices = collectNotices(daemon, 'settings_invalid');

    lengthenServerName(env);
    final done = await reloadAndMigrate(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    final after = daemon.instances.get(instance.id);
    expect(after.state, InstanceState.running);
    expect(after.settingsInvalid, isTrue);
    expect(after.settings, containsPair('serverName', 'Friends'));
    expect(after.pluginVersion, '0.1.0');
    await eventually(() => notices.isNotEmpty, reason: 'the notice');
    expect(notices.single.message, contains('serverName'));
    // A later Start is refused; Stop is not.
    expect(
      () => daemon.instances.start(instance.id),
      failsWith('invalid_state', messageHas: ['settings_invalid']),
    );
    final stopped = await runStop(daemon, instance.id);
    expect(stopped.status, OperationStatus.succeeded);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('migration_hook_fails', () async {
    final env = TestEnv();
    env.installValheim(hooks: renameHook);
    final daemon = await env.start();
    Future<Instance> installed(String name, int port) async {
      final created = await createValheim(
        daemon,
        name: name,
        ports: {'game': port},
        settings: {'serverName': name, 'worldName': 'Alpha'},
      );
      await daemon.operations.whenDone(daemon.instances.install(created.id).id);
      return daemon.instances.get(created.id);
    }

    final bad = await installed('Bad', 2456);
    final good = await installed('Good', 2460);
    final notices = collectNotices(daemon, 'settings_invalid');

    renameWorldSetting(env);
    await daemon.instances.reloadPlugins();
    final badDone = await daemon.operations.whenDone(
      migrationsOf(daemon, bad.id).single.id,
    );
    final goodDone = await daemon.operations.whenDone(
      migrationsOf(daemon, good.id).single.id,
    );

    expect(badDone.status, OperationStatus.failed);
    expect(badDone.resultMessage, contains('cannot migrate Bad'));
    final after = daemon.instances.get(bad.id);
    expect(after.settings, containsPair('worldName', 'Alpha'));
    expect(after.settings, isNot(contains('world')));
    expect(after.pluginVersion, '0.1.0');
    expect(after.state, InstanceState.error);
    expect(after.stateReason, 'settings_invalid');
    await eventually(() => notices.isNotEmpty, reason: 'the notice');
    expect(notices.single.instanceId, bad.id);
    expect(notices.single.message, contains('cannot migrate Bad'));
    // The other instance was still processed.
    expect(goodDone.status, OperationStatus.succeeded);
    expect(
      daemon.instances.get(good.id).settings,
      containsPair('world', 'Alpha'),
    );
    expect(daemon.instances.get(good.id).pluginVersion, '0.2.0');
  });

  test('settings_no_longer_valid', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    final notices = collectNotices(daemon, 'settings_invalid');

    lengthenServerName(env);
    final done = await reloadAndMigrate(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    final after = daemon.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(after.stateReason, 'settings_invalid');
    await eventually(() => notices.isNotEmpty, reason: 'the notice');
    expect(notices.single.message, contains('serverName'));
    expect(
      () => daemon.instances.start(instance.id),
      failsWith('invalid_state'),
    );

    // A valid save records the loaded version, so the next reload does not
    // migrate those settings again.
    daemon.instances.updateSettings(
      UpdateSettingsRequest(
        instanceId: instance.id,
        settings: {'serverName': 'Friends of the server'},
      ),
    );
    final fixed = daemon.instances.get(instance.id);
    expect(fixed.state, InstanceState.stopped);
    expect(fixed.pluginVersion, '0.2.0');
    final migrations = migrationsOf(daemon, instance.id).length;
    await daemon.instances.reloadPlugins();
    expect(migrationsOf(daemon, instance.id), hasLength(migrations));
    expect(
      (await runStart(daemon, instance.id)).status,
      OperationStatus.succeeded,
    );
  });

  test('gate_refuses_operations_but_not_stop_and_delete', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    lengthenServerName(env);
    await reloadAndMigrate(daemon, instance.id);

    expect(
      () => daemon.instances.restart(instance.id),
      failsWith('invalid_state', messageHas: ['settings_invalid']),
    );
    expect(
      () => daemon.instances.update(instance.id),
      failsWith('invalid_state', messageHas: ['settings_invalid']),
    );
    // Stop and delete are exempt.
    expect(
      (await runStop(daemon, instance.id)).status,
      OperationStatus.succeeded,
    );
    final delete = daemon.instances.delete(instance.id);
    expect(
      (await daemon.operations.whenDone(delete.id)).status,
      OperationStatus.succeeded,
    );
    expect(daemon.instances.find(instance.id), isNull);
  });

  group('with a running operation holding the queue', () {
    /// An install held by the fake Steam service, and [queued] starts behind
    /// it.
    Future<(Daemon, Instance)> held(TestEnv env, {int queued = 10}) async {
      env.installValheim();
      final hold = env.steam.hold = Completer<void>();
      addTearDown(() {
        if (!hold.isCompleted) hold.complete();
      });
      final daemon = await env.start();
      final instance = await createValheim(daemon);
      daemon.instances.install(instance.id);
      await eventually(
        () => env.steam.runs.isNotEmpty,
        reason: 'the install to run',
      );
      for (var i = 0; i < queued; i++) {
        daemon.instances.start(instance.id);
      }
      return (daemon, instance);
    }

    test('migration_goes_to_the_queue_head_outside_the_bound', () async {
      final env = TestEnv();
      final (daemon, instance) = await held(env);
      expect(
        () => daemon.instances.start(instance.id),
        failsWith('queue_full'),
      );

      env.editValheim('version: 0.1.0', 'version: 0.2.0');
      await daemon.instances.reloadPlugins();

      final migration = migrationsOf(daemon, instance.id).single;
      expect(migration.status, OperationStatus.queued);
      expect(migration.queuePosition, 1);
      env.steam.hold!.complete();
      final done = await daemon.operations.whenDone(migration.id);
      expect(done.status, OperationStatus.succeeded);
      // It ran before any of the starts that were queued first.
      final firstStart = daemon.operations
          .listForInstance(instance.id)
          .firstWhere((op) => op.kind == OperationKind.start);
      await daemon.operations.whenDone(firstStart.id);
      final started = daemon.operations.get(firstStart.id)!;
      expect(done.endedAt!.isAfter(started.startedAt!), isFalse);
      expect(daemon.instances.get(instance.id).pluginVersion, '0.2.0');
    });

    test('repeat_reload_retargets_the_queued_migration', () async {
      final env = TestEnv();
      final (daemon, instance) = await held(env, queued: 1);

      env.editValheim('version: 0.1.0', 'version: 0.2.0');
      await daemon.instances.reloadPlugins();
      env.editValheim('version: 0.2.0', 'version: 0.3.0');
      await daemon.instances.reloadPlugins();

      final migration = migrationsOf(daemon, instance.id).single;
      env.steam.hold!.complete();
      final done = await daemon.operations.whenDone(migration.id);
      expect(done.status, OperationStatus.succeeded);
      expect(daemon.instances.get(instance.id).pluginVersion, '0.3.0');
      expect(migrationsOf(daemon, instance.id), hasLength(1));
    });
  });

  test('startup_reconciliation_queues_the_migration', () async {
    final env = TestEnv();
    env.installValheim(hooks: renameHook);
    final first = await env.start();
    final created = await createValheim(
      first,
      settings: {'serverName': 'Friends', 'worldName': 'Alpha'},
    );
    await env.kill(first);

    renameWorldSetting(env);
    final second = await env.start();

    final migration = migrationsOf(second, created.id).single;
    final done = await second.operations.whenDone(migration.id);
    expect(done.status, OperationStatus.succeeded);
    final after = second.instances.get(created.id);
    expect(after.settings, containsPair('world', 'Alpha'));
    expect(after.pluginVersion, '0.2.0');
  });
}
