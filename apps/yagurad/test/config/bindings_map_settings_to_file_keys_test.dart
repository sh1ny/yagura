import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/plugins/plugin_registry.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';
import 'config_support.dart';

final _maxPlayers = bindingYaml(
  file: 'serverDZ.cfg',
  format: 'dayz-cfg',
  key: 'maxPlayers',
  setting: 'maxPlayers',
);

void main() {
  test('scalar_binding_applied', () async {
    final env = TestEnv();
    installBound(env, bindings: [_maxPlayers]);
    final daemon = await env.start();
    final instance = await createBound(daemon, maxPlayers: 40);
    final file = instanceFile(
      instance,
      'serverDZ.cfg',
      'hostname = "Friends";\nmaxPlayers = 10;\n',
    );
    // What the file holds at the moment the process is launched.
    String? atLaunch;
    env.process.onLaunch = (_) => atLaunch = file.readAsStringSync();

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(atLaunch, 'hostname = "Friends";\nmaxPlayers = 40;\n');
  });

  test('bound_file_missing', () async {
    final env = TestEnv();
    installBound(env, bindings: [_maxPlayers]);
    final daemon = await env.start();
    final instance = await createBound(daemon);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'binding_file_missing');
    expect(
      done.resultMessage,
      allOf(contains('serverDZ.cfg'), contains('maxPlayers')),
    );
    expect(env.process.launches, isEmpty, reason: 'the process is not launched');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(File(p.join(instance.directory, 'serverDZ.cfg')).existsSync(), false);
  });

  test('missing_file_created_from_the_plugin_template', () async {
    final env = TestEnv();
    installBound(
      env,
      bindings: [
        bindingYaml(
          file: 'serverDZ.cfg',
          format: 'dayz-cfg',
          key: 'maxPlayers',
          setting: 'maxPlayers',
          create: true,
          template: 'templates/serverDZ.cfg',
        ),
      ],
      templates: {
        'templates/serverDZ.cfg':
            '// from the plugin\nhostname = "Template";\nmaxPlayers = 10;\n',
      },
    );
    final daemon = await env.start();
    final instance = await createBound(daemon, maxPlayers: 40);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(
      File(p.join(instance.directory, 'serverDZ.cfg')).readAsStringSync(),
      '// from the plugin\nhostname = "Template";\nmaxPlayers = 40;\n',
    );
    // The plugin's own template is not touched.
    expect(
      File(
        p.join(env.pluginsDir, 'valheim', 'templates', 'serverDZ.cfg'),
      ).readAsStringSync(),
      contains('maxPlayers = 10;'),
    );
  });

  test('secret_setting_bound', () async {
    const secret = 'Zr0-correct-horse';
    final env = TestEnv();
    installBound(
      env,
      bindings: [
        bindingYaml(
          file: 'battleye/BEServer_x64.cfg',
          format: 'kv',
          key: 'RConPassword',
          setting: 'rconPassword',
          create: true,
          template: 'templates/BEServer_x64.cfg',
        ),
      ],
      templates: {
        'templates/BEServer_x64.cfg': 'RConPassword changeme\nRConPort 2310\n',
      },
    );
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final instance = await createBound(daemon);
    daemon.instances.setSecret(instance.id, 'rconPassword', secret);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final bound = File(
      p.join(instance.directory, 'battleye', 'BEServer_x64.cfg'),
    );
    expect(bound.readAsStringSync(), 'RConPassword $secret\nRConPort 2310\n');
    // No other file Yagura writes (instance.json, run files, daemon logs, the
    // database) holds the value.
    final needle = secret.codeUnits;
    for (final entity in env.root.listSync(recursive: true)) {
      if (entity is! File || p.equals(entity.path, bound.path)) continue;
      if (p.isWithin(env.pluginsDir, entity.path)) continue;
      final bytes = entity.readAsBytesSync();
      final found = _indexOf(bytes, needle) >= 0;
      expect(found, isFalse, reason: '${entity.path} holds the secret');
    }
  });

  test('binding_names_an_unknown_setting', () async {
    final env = TestEnv();
    installBound(
      env,
      bindings: [
        bindingYaml(
          file: 'serverDZ.cfg',
          format: 'dayz-cfg',
          key: 'maxPlayers',
          setting: 'doesNotExist',
        ),
      ],
    );
    final registry = PluginRegistry(
      pluginsDirectory: env.pluginsDir,
      hooks: HookHost(),
    );

    final results = await registry.load();

    final valheim = results.singleWhere((r) => r.id == 'valheim');
    expect(valheim.status, PluginStatus.rejected);
    final reason = valheim.reasons.single;
    expect(reason.path, 'bindings[0].setting');
    expect(reason.message, contains('doesNotExist'));
    expect(reason.message, contains('bindings[0]'));
    expect(registry.find('valheim'), isNull);
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
