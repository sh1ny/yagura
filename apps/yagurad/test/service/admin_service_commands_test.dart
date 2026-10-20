@Tags(['windows'])
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/admin/admin_client.dart';
import 'package:yagurad/src/errors.dart';

import '../support/admin_support.dart';
import '../support/daemon_support.dart';

// What `service configure`, `service status` and `uninstall --purge-accounts`
// ask the running daemon over the admin channel.
void main() {
  test('ports_check_names_the_instance_that_uses_the_port', () async {
    final env = TestEnv()..installValheim();
    final h = await AdminHarness.start(env);
    final instance = await createValheim(h.daemon, name: 'Friends');
    final taken = instance.ports.first.number;
    final client = AdminClient(h.connector());

    await expectLater(
      client.call('ports.check', {'port': taken}),
      throwsA(
        isA<YaguraException>()
            .having((e) => e.reason, 'reason', 'port_conflict')
            .having((e) => e.message, 'message', contains('Friends')),
      ),
    );
    expect(await client.call('ports.check', {'port': taken + 1000}), isEmpty);
  });

  test('ports_check_wants_a_port_number', () async {
    final h = await AdminHarness.start(TestEnv());
    final client = AdminClient(h.connector());

    for (final port in [null, 'x', 0, 70000]) {
      await expectLater(
        client.call('ports.check', {'port': ?port}),
        throwsA(
          isA<YaguraException>().having(
            (e) => e.reason,
            'reason',
            'admin_request_invalid',
          ),
        ),
        reason: '$port',
      );
    }
  });

  test('status_lists_running_servers_and_the_executable', () async {
    final env = TestEnv()..installValheim();
    final h = await AdminHarness.start(env);
    final client = AdminClient(h.connector());
    expect((await client.call('status'))['running_servers'], isEmpty);

    await createRunning(h.daemon, name: 'Friends');
    await createInstalled(h.daemon, name: 'Idle', ports: {'game': 2556});

    final status = await client.call('status');
    expect(status['running_servers'], ['Friends']);
    expect(status['executable'], Platform.resolvedExecutable);
  });

  test('status_lists_an_instance_that_is_installing', () async {
    final env = TestEnv()..installValheim();
    final h = await AdminHarness.start(env);
    final client = AdminClient(h.connector());
    final instance = await createValheim(h.daemon, name: 'Fresh');
    final hold = env.steam.hold = Completer<void>(); // the download never ends
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });
    h.daemon.instances.install(instance.id);
    await env.steam.reachedDownload.future;

    final status = await client.call('status');

    expect(status['running_servers'], ['Fresh']);
  });
}
