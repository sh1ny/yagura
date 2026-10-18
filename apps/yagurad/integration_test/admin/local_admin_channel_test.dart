import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/admin/admin_server.dart';
import 'package:yagurad/src/admin/admin_wire.dart';
import 'package:yagurad/src/admin/named_pipe.dart';

import '../../test/support/admin_support.dart';
import '../../test/support/daemon_support.dart';
import '../../test/support/elevated_support.dart';
import '../../test/support/process_support.dart';
import '../../test/support/secret_support.dart';
import '../../test/support/secure_support.dart';

/// `yagura://<host>:<port>?code=<CODE>&ca=sha256:<64 hex>&name=<name>`
final pairingString = RegExp(
  r'yagura://([^:/?]+):(\d+)\?code=([0-9A-Z]{10})'
  r'&ca=sha256:([0-9a-f]{64})&name=(\S+)',
);

void main() {
  // The real thing: the service account serves the pipe, an elevated
  // administrator reaches it, and a standard user is refused by its ACL.
  test('administrator_requests_a_pairing_code', tags: ['elevated'], () async {
    final tools = await processTools();
    final daemon = await SystemDaemon.start(tools);

    final result = await runYaguradExe(tools, ['pair']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final match = pairingString.firstMatch(result.stdout as String);
    expect(match, isNotNull, reason: '${result.stdout}');
    expect(match![3], hasLength(10));
    expect(daemon.dataDir.existsSync(), isTrue);
  });

  test('non_administrator', tags: ['elevated'], () async {
    final tools = await processTools();
    await SystemDaemon.start(tools);
    final user = StandardUser.create();
    // The user must be able to run the executable.
    Process.runSync('icacls', [
      p.dirname(p.dirname(tools.yagurad)),
      '/grant',
      '*S-1-5-32-545:(OI)(CI)RX',
    ]);

    final denied = await user.run(tools.yagurad, ['pair']);

    expect(denied.exitCode, isNot(0));
    expect(denied.err, contains('access_denied'));
    expect(denied.out, isNot(contains('yagura://')));
    // No code was issued by the refused call: the next one is the first.
    final admin = await runYaguradExe(tools, ['pair']);
    expect(admin.exitCode, 0, reason: '${admin.stderr}');
    expect(admin.stdout as String, matches(pairingString));
  });

  // A process that is not the LocalSystem daemon serves the name: the real
  // check (the server's token user) runs, unprivileged, against this very
  // test process.
  test('channel_served_by_another_process', tags: ['windows'], () async {
    final received = <AdminRequest>[];
    final name = testPipeName();
    final server = AdminServer(
      NamedPipeListener(name: name, sddl: currentUserPipeSddl()),
      (request) async {
        received.add(request);
        return {
          'pairing_string':
              'yagura://evil:7443?code=AAAAAAAAAA&ca=sha256:${'0' * 64}&name=x',
        };
      },
    );
    await server.start();
    addTearDown(server.close);

    final result = await runYagurad(['pair'], NamedPipeConnector(name: name));

    expect(result.code, isNot(0));
    expect(result.err, contains('admin_channel_untrusted'));
    expect(result.out, isNot(contains('yagura://')));
    expect(result.err, isNot(contains('yagura://')));
    // Nothing was sent to the impostor, not even the command.
    expect(received, isEmpty);
  });

  test('daemon_not_running', tags: ['windows'], () async {
    final result = await runYagurad([
      'pair',
    ], NamedPipeConnector(name: testPipeName(), verifier: (_) => true));

    expect(result.code, isNot(0));
    expect(result.err, contains('daemon_not_running'));
    expect(result.out, isEmpty);
    // The CLI side has no way to the database: it imports neither the
    // database nor the daemon.
    for (final file in [
      'lib/src/admin/admin_client.dart',
      'lib/src/admin/admin_wire.dart',
      'lib/src/admin/admin_transport.dart',
      'lib/src/admin/named_pipe.dart',
      'lib/src/cli/admin_commands.dart',
    ]) {
      final imports = RegExp(
        r'''^import\s+'([^']+)';''',
        multiLine: true,
      ).allMatches(File(file).readAsStringSync()).map((m) => m[1]!);
      expect(
        imports.where(
          (i) =>
              i.contains('database') ||
              i.contains('daemon.dart') ||
              i.contains('sqlite3') ||
              i.contains('security/'),
        ),
        isEmpty,
        reason: file,
      );
    }
  });

  group('with a service-mode daemon on a test pipe', () {
    test(
      'pairing_string_is_issued_by_the_running_daemon',
      tags: ['windows'],
      () async {
        final h = await AdminHarness.start(TestEnv());

        final result = await h.run(['pair']);

        expect(result.code, 0, reason: '$result');
        final match = pairingString.firstMatch(result.out)!;
        // The first non-loopback IPv4 address and the daemon's API port.
        expect(match[1], '192.168.10.20');
        expect(match[2], '$apiPort');
        expect(match[4], h.daemon.security!.identity.caFingerprint);
        expect(Uri.decodeComponent(match[5]!), Platform.localHostname);
        // The code is the daemon's active one: a device enrolls with it.
        final secure = await SecureHarness.start(h.env, daemon: h.daemon);
        final device = await secure.pair('desk-01', code: match[3]);
        expect(device.name, 'desk-01');
      },
    );

    test(
      'the_address_option_overrides_the_default',
      tags: ['windows'],
      () async {
        final h = await AdminHarness.start(TestEnv());

        final named = await h.run(['pair', '--address', 'host.example']);
        final withPort = await h.run(['pair', '--address', 'gw.example:9000']);

        expect(pairingString.firstMatch(named.out)![1], 'host.example');
        expect(pairingString.firstMatch(named.out)![2], '$apiPort');
        expect(pairingString.firstMatch(withPort.out)![1], 'gw.example');
        expect(pairingString.firstMatch(withPort.out)![2], '9000');
        final bad = await h.run(['pair', '--address', 'bad address!']);
        expect(bad.code, isNot(0));
        expect(bad.err, contains('admin_request_invalid'));
      },
    );

    test('a_second_pair_replaces_the_first_code', tags: ['windows'], () async {
      final h = await AdminHarness.start(TestEnv());
      final first = pairingString.firstMatch((await h.run(['pair'])).out)![3]!;
      final second = pairingString.firstMatch((await h.run(['pair'])).out)![3]!;
      expect(second, isNot(first));
      final secure = await SecureHarness.start(h.env, daemon: h.daemon);

      await expectLater(secure.pair('late', code: first), throwsA(anything));
      expect((await secure.pair('desk-01', code: second)).name, 'desk-01');
    });

    test(
      'a_host_without_a_usable_address_asks_for_one',
      tags: ['windows'],
      () async {
        final h = await AdminHarness.start(
          TestEnv(),
          hostAddresses: () async => [InternetAddress.loopbackIPv4],
        );

        final result = await h.run(['pair']);

        expect(result.code, isNot(0));
        expect(result.err, contains('address_required'));
        expect(result.out, isEmpty);
      },
    );

    test(
      'the_pipe_acl_refuses_a_user_it_does_not_name',
      tags: ['windows'],
      () async {
        // The descriptor names SYSTEM only: the OS itself refuses this
        // (standard, non-elevated) user when the CLI opens the pipe.
        final name = testPipeName();
        final env = TestEnv();
        final daemon = await env.start(
          serviceMode: true,
          adminListener: () =>
              NamedPipeListener(name: name, sddl: 'D:P(A;;GA;;;SY)'),
          secretProtector: FakeSecretProtector(serviceSid),
        );

        final result = await runYagurad(
          ['pair'],
          NamedPipeConnector(
            name: name,
            verifier: (_) => true,
            elevationMissing: () => false,
          ),
        );

        expect(result.code, isNot(0));
        expect(result.err, contains('access_denied'));
        expect(result.out, isEmpty);
        // No code was issued.
        expect(
          daemon.security!.pairing.hasActiveCode,
          isFalse,
          reason: 'a refused call issues nothing',
        );
      },
    );

    test(
      'an_administrator_who_has_not_elevated_is_told_to_elevate',
      tags: ['windows'],
      () async {
        final name = testPipeName();
        final env = TestEnv();
        await env.start(
          serviceMode: true,
          adminListener: () =>
              NamedPipeListener(name: name, sddl: 'D:P(A;;GA;;;SY)'),
          secretProtector: FakeSecretProtector(serviceSid),
        );

        final result = await runYagurad(
          ['pair'],
          NamedPipeConnector(
            name: name,
            verifier: (_) => true,
            elevationMissing: () => true,
          ),
        );

        expect(result.code, isNot(0));
        expect(result.err, contains('elevation_required'));
        expect(result.err, isNot(contains('access_denied')));
      },
    );

    test(
      'admin_calls_that_change_state_are_audited_as_host_admin',
      tags: ['windows'],
      () async {
        final h = await AdminHarness.start(TestEnv());
        await h.run(['pair']);
        await h.run(['status']);
        await h.run(['devices', 'list']);

        final entries = h.daemon.security!.audit.list();

        expect(entries, hasLength(1), reason: 'reads are not audited');
        expect(entries.single.deviceId, 'host-admin');
        expect(entries.single.method, 'admin/pair');
        expect(entries.single.result, 'ok');
        // The code never reaches the log.
        expect(
          '${entries.single.target}${entries.single.result}',
          isNot(matches(RegExp('[0-9A-Z]{10}'))),
        );
      },
    );

    test(
      'status_reports_the_daemon_and_the_admin_channel',
      tags: ['windows'],
      () async {
        final h = await AdminHarness.start(TestEnv());

        final result = await h.run(['status']);

        expect(result.code, 0, reason: '$result');
        expect(result.out, contains('admin_channel: ok'));
        expect(result.out, contains('mode: service'));
        expect(
          result.out,
          contains('data_dir: ${h.daemon.dataDirectory.path}'),
        );
        expect(result.out, contains('api_port: $apiPort'));
        expect(result.out, contains('devices: 0'));
      },
    );

    test('health_reports_the_admin_channel_ok', tags: ['windows'], () async {
      final h = await AdminHarness.start(TestEnv());
      final secure = await SecureHarness.start(h.env, daemon: h.daemon);
      final device = await secure.pair('desk-01');

      final health = await device.system.getHealth(pb.GetHealthRequest());

      expect(health.adminChannelOk, isTrue);
      expect(h.daemon.adminChannelOk, isTrue);
    });

    test(
      'a_squatted_pipe_name_is_a_notice_and_a_false_health_flag',
      tags: ['windows'],
      () async {
        final name = testPipeName();
        final squatter = NamedPipeListener(
          name: name,
          sddl: currentUserPipeSddl(),
        );
        await squatter.open();
        addTearDown(squatter.close);
        final env = TestEnv();

        final h = await AdminHarness.start(env, pipeName: name);

        expect(h.daemon.adminChannelOk, isFalse);
        expect(
          h.daemon.startupNotices.map((n) => n.step),
          contains('admin_channel_squatted'),
          reason: '${h.daemon.startupNotices}',
        );
        final secure = await SecureHarness.start(env, daemon: h.daemon);
        final device = await secure.pair('desk-01');
        final health = await device.system.getHealth(pb.GetHealthRequest());
        expect(health.adminChannelOk, isFalse);
      },
    );

    test('a_dev_daemon_has_no_admin_channel', tags: ['windows'], () async {
      final env = TestEnv();
      final daemon = await env.start();

      expect(daemon.adminChannelOk, isFalse);
    });

    test(
      'the_daemon_stops_serving_when_it_closes',
      tags: ['windows'],
      () async {
        final h = await AdminHarness.start(TestEnv());
        await h.env.closeDaemons();

        final result = await h.run(['status']);

        expect(result.code, isNot(0));
        expect(result.err, contains('daemon_not_running'));
      },
    );

    test(
      'the_audit_entries_are_listed_with_the_host_admin_name',
      tags: ['windows'],
      () async {
        final h = await AdminHarness.start(TestEnv());
        await h.run(['pair']);
        final secure = await SecureHarness.start(h.env, daemon: h.daemon);
        final device = await secure.pair('desk-01');

        final listed = await device.system.listAudit(pb.ListAuditRequest());

        expect(
          listed.entries.map((e) => e.deviceId),
          containsAll(['host-admin', device.deviceId]),
        );
      },
    );
  });
}
