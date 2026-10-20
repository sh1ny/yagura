import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/content_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';

void main() {
  test('mods_staged_hook_edits_a_config', () async {
    // A binding writes `GeneralData.name`; the mods-staged hook and the
    // pre-start hook edit the same file.
    final rig = await ModsRig.start(
      manifest: moddedValheimManifest(
        extra: '''
bindings:
  - file: cfggameplay.json
    format: json
    key: GeneralData.name
    setting: serverName
    create: true
''',
      ),
      hooks: '''
exports.onModsStaged = function (ctx) {
  return {files: [{path: "cfggameplay.json", format: "json", patch: {
    GeneralData: {
      name: "from-mods-hook",
      title: "mods-hook",
      staged: ctx.mods.map((m) => m.stagedName).join(",")
    }
  }}]};
};
exports.onPreStart = function () {
  return {files: [{path: "cfggameplay.json", format: "json", patch: {
    GeneralData: {title: "pre-start-hook"}
  }}]};
};
''',
    );
    rig.item(cfMod, title: 'CF');
    rig.item(vppMod, title: 'VPP');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod), ModSpec(vppMod)]);

    final done = await runStart(rig.daemon, instance.id);

    // The start continued.
    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(rig.current(instance).state, InstanceState.running);
    final general =
        (jsonDecode(
              File(p.join(instance.directory, 'cfggameplay.json'))
                  .readAsStringSync(),
            ) as Map<String, Object?>)['GeneralData']
            as Map<String, Object?>;
    // Applied after the bindings (the binding wrote "Friends"), with the mods
    // already staged, and before the pre-start edits (which win).
    expect(general['name'], 'from-mods-hook');
    expect(general['staged'], '@CF,@VPP');
    expect(general['title'], 'pre-start-hook');
    // One pass: the file was written once, so the next start finds no hand
    // edit.
    await runStop(rig.daemon, instance.id);
    final second = await runStart(rig.daemon, instance.id);
    expect(
      second.warnings.where((w) => w.startsWith('external_edit')),
      isEmpty,
    );
  });

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
