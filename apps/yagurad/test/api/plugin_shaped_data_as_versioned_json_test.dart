import 'dart:convert';
import 'dart:io';

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

  test('malformed_json', () async {
    final env = TestEnv()..installValheim();
    final api = await ApiHarness.start(env);
    final instance = await api.createValheim();

    final error = await failureOf(
      api.instances.updateSettings(
        pb.UpdateSettingsRequest(
          instanceId: instance.id,
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
