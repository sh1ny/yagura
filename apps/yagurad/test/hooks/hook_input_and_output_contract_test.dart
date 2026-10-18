import 'dart:convert';

import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';

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

  test('context_with_a_secret_set', () async {
    final env = TestEnv();
    env.installValheim(
      hooks: 'exports.onPreStart = (ctx) => ({args: [JSON.stringify(ctx)]});',
    );
    final daemon = await env.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final instance = await createInstalled(daemon);
    daemon.instances.setSecret(instance.id, 'password', 'hunter2');

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final text = env.process.launches.single.args.last;
    final settings =
        (jsonDecode(text) as Map<String, Object?>)['settings']!
            as Map<String, Object?>;
    expect(settings['password'], {'secret': true, 'set': true});
    expect(text, isNot(contains('hunter2')));
  });

  // The relay rotates its capture only on whole line breaks of the server's
  // output encoding, so the launch carries the `stdout: true` source's.
  test('launch_carries_the_stdout_encoding', () async {
    final env = TestEnv();
    env.installValheim(
      from: '    rotation: fixed\n',
      to:
          '    rotation: fixed\n'
          '  - name: console\n'
          '    stdout: true\n'
          '    encoding: utf-16le\n',
    );
    final daemon = await env.start();
    final instance = await createInstalled(daemon);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(env.process.launches.single.stdoutEncoding, 'utf-16le');
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
