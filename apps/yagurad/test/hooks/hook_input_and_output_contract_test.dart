import 'dart:convert';

import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('context_contents', () async {
    final env = TestEnv();
    // The hook hands its context back as the single extra argument.
    env.installValheim(
      hooks: 'exports.onPreStart = (ctx) => ({args: [JSON.stringify(ctx)]});',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded);
    final context = jsonDecode(
      env.process.launches.single.args.last,
    ) as Map<String, Object?>;
    final settings = context['settings']! as Map<String, Object?>;
    // `password` is the plugin's `secret` setting: a placeholder, no value.
    expect(settings['password'], {'secret': true, 'set': false});
    expect(settings['serverName'], 'Friends');
    expect(context['instanceId'], instance.id);
    expect(context['pluginId'], 'valheim');
    expect(context['os'], 'windows');
    expect(context['paths'], {'server': 'server'});
    expect(context['ports'], containsPair('game', 2456));
  });

  test('invalid_result_shape', () async {
    final env = TestEnv();
    env.installValheim(
      hooks: 'exports.onPreStart = () => ({args: "-freezecheck"});',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'hook_result_invalid');
    expect(done.resultMessage, allOf(contains('onPreStart'), contains('args')));
    expect(env.process.launches, isEmpty, reason: 'the server is not started');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });
}
