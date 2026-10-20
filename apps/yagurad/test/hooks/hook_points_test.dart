import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('hook_not_exported', () async {
    final env = TestEnv();
    // hooks.js exports only onPreStart; the install runs onPostInstall.
    env.installValheim(hooks: 'exports.onPreStart = () => ({args: ["-x"]});');
    final daemon = await env.start();
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final events = await daemon.operations.watch(op.id).toList();

    final finished = (events.last as FinishedEvent).operation;
    expect(finished.status, OperationStatus.succeeded);
    expect(finished.warnings, isEmpty);
    // No hook ran, so nothing was logged and nothing was reported.
    expect(events.whereType<LogEvent>(), isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('pre_start_hook_adds_arguments', () async {
    final env = TestEnv();
    env.installValheim(
      hooks:
          'exports.onPreStart = () => ({args: ["-freezecheck"], '
          'env: {SteamAppId: "221100"}});',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded);
    final launch = env.process.launches.single;
    // Appended after the manifest's arguments.
    expect(launch.args.last, '-freezecheck');
    expect(launch.args, containsAllInOrder(['-name', 'Friends', '-public']));
    expect(launch.env, containsPair('SteamAppId', '221100'));
  });

  test('migration_hook_result_applied', () async {
    final env = TestEnv();
    // The hook reports the versions it was called with in the server name and
    // hands the secret placeholder back as it received it.
    env.installValheim(
      hooks:
          'exports.migrateSettings = function (ctx) {'
          ' const settings = Object.assign({}, ctx.settings);'
          ' settings.serverName = ctx.fromVersion + ">" + ctx.toVersion;'
          ' return {settings: settings}; };',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    env.editValheim('version: 0.1.0', 'version: 0.2.0');
    await daemon.instances.reloadPlugins();
    final migration = daemon.operations
        .listForInstance(instance.id)
        .singleWhere((op) => op.kind.wireName == 'migrate_settings');
    final done = await daemon.operations.whenDone(migration.id);

    expect(done.status, OperationStatus.succeeded);
    final after = daemon.instances.get(instance.id);
    expect(after.settings, containsPair('serverName', '0.1.0>0.2.0'));
    expect(after.pluginVersion, '0.2.0');
    expect(after.revision, instance.revision + 1);
    expect(after.state, InstanceState.stopped);
    final file = jsonDecode(
      File(p.join(instance.directory, 'instance.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(file['plugin'], containsPair('version', '0.2.0'));
    expect(file['settings'], containsPair('serverName', '0.1.0>0.2.0'));
  });

  test('post_stop_hook_runs_after_the_server_stopped', () async {
    final env = TestEnv();
    // A hook cannot write; its file edit is applied by the daemon after the
    // server is gone.
    env.installValheim(
      hooks:
          'exports.onPostStop = () => ({files: [{path: "stopped.json", '
          'format: "json", patch: {stopped: true}}]});',
    );
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    final file = File(p.join(instance.directory, 'stopped.json'))
      ..writeAsStringSync('{}');
    final server = env.process.servers.single;

    final done = await runStop(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded);
    expect(await server.exitCode, 0);
    expect(file.readAsStringSync(), contains('true'));
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('cancelled_stop_still_finishes_with_the_instance_stopped', () async {
    final env = TestEnv();
    env.installValheim(hooks: 'exports.onPostStop = () => ({});');
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    final gate = Completer<void>();
    env.process.stopGate = gate.future;

    final op = daemon.instances.stop(instance.id);
    await eventually(() => env.process.stops.isNotEmpty, reason: 'the stop');
    daemon.operations.cancel(op.id);
    gate.complete();
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.cancelled);
    final after = daemon.instances.get(instance.id);
    expect(after.state, InstanceState.stopped);
    expect(after.pid, 0);
  });
}
