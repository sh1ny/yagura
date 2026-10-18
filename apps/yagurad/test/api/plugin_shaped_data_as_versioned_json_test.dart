import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../support/api_support.dart';
import '../support/daemon_support.dart';

void main() {
  test('stale_form_submission', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final instance = await api.createValheim();
    final shown = await api.plugins.getPlugin(
      pb.GetPluginRequest(pluginId: 'valheim'),
    );
    final staleVersion = shown.settingsSchema.schemaVersion;
    expect(staleVersion, isNonZero);

    // The plugin changes its settings schema and the daemon reloads it.
    final manifest = File(p.join(env.pluginsDir, 'valheim', 'plugin.yaml'));
    manifest.writeAsStringSync(
      manifest.readAsStringSync().replaceFirst(
        'default: Yagura Valheim',
        'default: Another Valheim',
      ),
    );
    await api.plugins.reloadPlugins(pb.ReloadPluginsRequest());
    final current = await api.plugins.getPlugin(
      pb.GetPluginRequest(pluginId: 'valheim'),
    );
    expect(current.settingsSchema.schemaVersion, isNot(staleVersion));
    final before = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: instance.id),
    );

    final error = await failureOf(
      api.instances.updateSettings(
        pb.UpdateSettingsRequest(
          instanceId: instance.id,
          expectedRevision: Int64(1),
          settings: pb.JsonDocument(
            json: '{"serverName":"Renamed"}',
            schemaVersion: staleVersion,
          ),
        ),
      ),
    );

    expect(error.code, StatusCode.failedPrecondition);
    final detail = errorDetailOf(error)!;
    expect(detail.reason, 'schema_version_mismatch');
    expect(
      detail.metadata['schema_version'],
      '${current.settingsSchema.schemaVersion}',
      reason: 'the detail names the current version',
    );
    final after = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: instance.id),
    );
    expect(after.settings.json, before.settings.json, reason: 'not saved');
  });

  test('reload_applies_the_plugin_selection', () async {
    final env = TestEnv()..installValheim();
    // A second plugin, a copy of Valheim under another id.
    final other = Directory(p.join(env.pluginsDir, 'other'))
      ..createSync(recursive: true);
    File(p.join(other.path, 'plugin.yaml')).writeAsStringSync(
      File(p.join(valheimFixture, 'plugin.yaml'))
          .readAsStringSync()
          .replaceFirst('id: valheim', 'id: other'),
    );
    final api = await ApiHarness.start(env);
    final instance = await api.instances.createInstance(
      pb.CreateInstanceRequest(
        pluginId: 'other',
        name: 'Other',
        settings: pb.JsonDocument(json: '{"serverName":"Other"}'),
      ),
    );
    await api.daemon.operations.whenDone(
      api.daemon.instances.install(instance.id).id,
    );

    // The other plugin is removed on disk; only valheim is reloaded.
    other.deleteSync(recursive: true);
    final response = await api.plugins.reloadPlugins(
      pb.ReloadPluginsRequest(pluginIds: ['valheim']),
    );

    expect([for (final r in response.results) r.pluginId], ['valheim']);
    expect(api.daemon.plugins.find('other'), isNotNull, reason: 'still loaded');
    final untouched = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: instance.id),
    );
    expect(untouched.state, pb.InstanceState.INSTANCE_STATE_STOPPED);

    // Naming it applies the removal.
    final named = await api.plugins.reloadPlugins(
      pb.ReloadPluginsRequest(pluginIds: ['other']),
    );
    expect(named.results.single.outcome, 'removed');
    expect(api.daemon.plugins.find('other'), isNull);
    final gone = await api.instances.getInstance(
      pb.GetInstanceRequest(instanceId: instance.id),
    );
    expect(gone.state, pb.InstanceState.INSTANCE_STATE_ERROR);
  });

  test('malformed_json', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final instance = await api.createValheim();

    final error = await failureOf(
      api.instances.updateSettings(
        pb.UpdateSettingsRequest(
          instanceId: instance.id,
          expectedRevision: Int64(1),
          settings: pb.JsonDocument(json: '{"serverName": "x",\n  oops}'),
        ),
      ),
    );

    expect(error.code, StatusCode.invalidArgument);
    final detail = errorDetailOf(error)!;
    expect(detail.reason, 'invalid_json');
    expect(
      detail.message,
      matches(RegExp(r'line 2, column \d+ \(offset \d+\)')),
      reason: 'the parse position',
    );
    expect(jsonDecode('{"ok":true}'), isNotNull);
  });
}
