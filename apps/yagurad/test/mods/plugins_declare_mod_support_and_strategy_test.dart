import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart' show PluginStatus;
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/plugins/plugin_registry.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';

void main() {
  test('plugin_without_mod_support', () async {
    // The Valheim fixture declares no `mods` section.
    final env = TestEnv()..installValheim();
    final daemon = await env.start();
    final api = await ApiHarness.start(env, daemon: daemon);
    final instance = await createInstalled(daemon);
    final revision = daemon.instances.get(instance.id).revision;

    await expectLater(
      api.mods.setMods(
        pb.SetModsRequest(
          instanceId: instance.id,
          expectedRevision: Int64(revision),
          mods: [
            pb.ModRef(
              source: 'steam_workshop',
              itemId: '1559212036',
              role: 'client',
            ),
          ],
        ),
      ),
      failsWithStatus(StatusCode.failedPrecondition, 'mods_not_supported'),
    );

    await expectLater(
      api.mods.applyMods(pb.ApplyModsRequest(instanceId: instance.id)),
      failsWithStatus(StatusCode.failedPrecondition, 'mods_not_supported'),
    );
    expect(daemon.instances.get(instance.id).revision, revision);
    expect(
      (await api.mods.listMods(pb.ListModsRequest(instanceId: instance.id)))
          .mods,
      isEmpty,
    );
  });

  test('server_managed_mods', () async {
    final rig = await ModsRig.start(
      manifest: moddedValheimManifest(
        mods: serverManagedModsSection,
        launch: serverManagedModsLaunch,
      ),
    );
    final instance = await rig.instance();

    final listed = await rig.setMods(instance, [
      ModSpec('928708', role: 'server', source: 'server_managed'),
      ModSpec('929420', role: 'server', source: 'server_managed'),
    ]);

    // Nothing is looked up: the ids are the names.
    expect([for (final m in listed.mods) m.itemId], ['928708', '929420']);
    final done = await runStart(rig.daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(rig.launchArgs, contains('-mods=928708,929420'));
    // Nothing was downloaded, asked of the workshop or staged.
    expect(rig.steam.workshopRuns, isEmpty);
    expect(rig.workshop.requests, isEmpty);
    expect((await rig.list(instance)).mods.map((m) => m.status).toSet(), {
      'staged',
    });
  });

  test('server_managed_mods_refuse_a_workshop_source', () async {
    final rig = await ModsRig.start(
      manifest: moddedValheimManifest(
        mods: serverManagedModsSection,
        launch: serverManagedModsLaunch,
      ),
    );
    final instance = await rig.instance();

    await expectLater(
      rig.setMods(instance, [ModSpec('928708', role: 'server')]),
      failsWithStatus(StatusCode.invalidArgument, 'mod_invalid'),
    );
  });

  test('source_of_a_later_version', () async {
    final env = TestEnv();
    installModdedValheim(
      env,
      manifest: moddedValheimManifest(
        mods: workshopModsSection.replaceFirst(
          'source: steam_workshop',
          'source: url_archive',
        ),
      ),
    );
    final registry = PluginRegistry(
      pluginsDirectory: env.pluginsDir,
      hooks: HookHost(),
    );

    final results = await registry.load();

    final valheim = results.singleWhere((r) => r.id == 'valheim');
    expect(valheim.status, PluginStatus.rejected);
    final reason = valheim.reasons.single;
    expect(reason.code, 'unsupported_in_this_version');
    expect(reason.path, 'mods.source');
    expect(reason.message, contains('url_archive'));
    expect(registry.find('valheim'), isNull);
  });
}
