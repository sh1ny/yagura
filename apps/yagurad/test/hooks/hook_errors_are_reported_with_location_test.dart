import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/plugins/plugin_registry.dart';

import '../support/daemon_support.dart';

void main() {
  test('syntax_error_at_load', () async {
    final env = TestEnv();
    env.installValheim(hooks: 'var a = 1;\nvar b = ;\n');
    final registry = PluginRegistry(
      pluginsDirectory: env.pluginsDir,
      hooks: HookHost(),
    );

    final results = await registry.load();

    final valheim = results.singleWhere((r) => r.id == 'valheim');
    expect(valheim.status, PluginStatus.rejected);
    expect(valheim.reasons, hasLength(1));
    expect(valheim.reasons.single.code, 'hook_syntax_error');
    expect(valheim.reasons.single.path, 'hooks.js');
    expect(valheim.reasons.single.line, 2);
    // No instance operation can run a rejected plugin's hooks.
    expect(registry.find('valheim'), isNull);
  });

  test('undecodable_hooks_file_is_rejected', () async {
    final env = TestEnv();
    env.installValheim(hooks: 'exports.onPreStart = () => ({});');
    File(p.join(env.pluginsDir, 'valheim', 'hooks.js'))
        .writeAsBytesSync([0x76, 0x61, 0x72, 0x20, 0xff, 0xfe, 0x3b]);
    final registry = PluginRegistry(
      pluginsDirectory: env.pluginsDir,
      hooks: HookHost(),
    );

    final results = await registry.load();

    final valheim = results.singleWhere((r) => r.id == 'valheim');
    expect(valheim.status, PluginStatus.rejected);
    expect(valheim.reasons.single.path, 'hooks.js');
    expect(valheim.reasons.single.message, contains('UTF-8'));
    expect(registry.find('valheim'), isNull);
  });

  test('thrown_error', () async {
    final env = TestEnv();
    // The throw sits on line 42 of hooks.js.
    final source =
        '${'// padding\n' * 41}'
        'exports.onPreStart = function () { throw new Error("missing cfg"); };\n';
    env.installValheim(hooks: source);
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'hook_error');
    expect(done.resultMessage, startsWith('missing cfg'));
    expect(done.resultMessage, contains('hooks.js:42'));
    // Recorded in the operation history, not only in the live result.
    final recorded = daemon.operations
        .listForInstance(instance.id)
        .singleWhere((o) => o.kind == OperationKind.start);
    expect(recorded.resultMessage, contains('hooks.js:42'));
    expect(env.process.launches, isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });
}
