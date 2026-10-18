import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/bind_address.dart';
import 'package:yagurad/src/errors.dart';

import '../support/cli_support.dart';
import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/secret_support.dart';
import '../support/secure_support.dart';

void main() {
  test('dev_mode_on_loopback', () async {
    final cli = RunningCli(['--dev', '--bind', '127.0.0.1:0']);
    final (address, port) = await Future.any([
      cli.listening.future,
      cli.exit.then<(InternetAddress, int)>(
        (code) => fail('exited $code: ${cli.errors}'),
      ),
    ]).timeout(const Duration(seconds: 20));

    expect(address.address, '127.0.0.1');
    expect(cli.errors, contains('DEV MODE: unauthenticated, localhost only'));
    final channel = ClientChannel(
      '127.0.0.1',
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    addTearDown(channel.terminate);
    final info = await pb.SystemClient(channel).getInfo(pb.GetInfoRequest());
    expect(info.devMode, isTrue, reason: 'a plaintext listener is open');

    cli.stop();
    expect(await cli.exit, 0);
  });

  test('run --console is the development mode of design D2', () async {
    // The M1 exit criteria start the daemon as `yagurad run --console --dev`.
    final cli = RunningCli(['--console', '--dev', '--bind', '127.0.0.1:0']);
    final (address, _) = await Future.any([
      cli.listening.future,
      cli.exit.then<(InternetAddress, int)>(
        (code) => fail('exited $code: ${cli.errors}'),
      ),
    ]).timeout(const Duration(seconds: 20));

    expect(address.address, '127.0.0.1');
    cli.stop();
    expect(await cli.exit, 0);
  });

  test('dev_mode_on_a_public_address', () async {
    final cli = RunningCli(['--dev', '--bind', '0.0.0.0:0']);

    final code = await cli.exit;

    expect(code, isNonZero);
    expect(cli.errors, contains('dev_mode_requires_loopback'));
    expect(cli.listening.isCompleted, isFalse, reason: 'no listener opened');
    expect(
      Directory(p.join(cli.data.path, 'data')).existsSync(),
      isFalse,
      reason: 'the daemon did not even start',
    );
  });

  test('dev_mode_default_bind', () async {
    // The default bind is a fixed port; take it only when it is free.
    try {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 7443);
      await probe.close();
    } on SocketException {
      markTestSkipped('127.0.0.1:7443 is in use on this machine');
      return;
    }

    final cli = RunningCli(['--dev']);
    final (address, port) = await Future.any([
      cli.listening.future,
      cli.exit.then<(InternetAddress, int)>(
        (code) => fail('exited $code: ${cli.errors}'),
      ),
    ]).timeout(const Duration(seconds: 20));

    expect(address.address, '127.0.0.1');
    expect(port, 7443);
    cli.stop();
    expect(await cli.exit, 0);
  });

  test('started_without_dev_mode', () async {
    // The Windows service: LocalSystem, `--service`.
    final cli = RunningCli(
      ['--service', '--bind', '127.0.0.1:0'],
      isLocalSystem: () => true,
      secretProtector: FakeSecretProtector(serviceSid),
    );
    final (_, port) = await cli.whenListening();

    // It serves mutual TLS: a plaintext client gets nowhere, a TLS client
    // with the CA but no certificate is turned away by the gate.
    final plain = ClientChannel(
      '127.0.0.1',
      port: port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        connectTimeout: Duration(seconds: 5),
      ),
    );
    addTearDown(plain.terminate);
    await expectLater(
      pb.SystemClient(plain).getInfo(
        pb.GetInfoRequest(),
        options: CallOptions(timeout: const Duration(seconds: 5)),
      ),
      throwsA(isA<GrpcError>()),
    );
    final tls = untrustedChannelTo(port);
    await expectLater(
      pb.SystemClient(tls).getInfo(pb.GetInfoRequest()),
      failsWithStatus(StatusCode.unauthenticated, 'unauthenticated'),
    );
    expect(cli.errors, isNot(contains('DEV MODE')));

    cli.stop();
    expect(await cli.exit, 0);
  });

  test('LocalSystem without --service is not service mode', () async {
    // A scheduled task or `PsExec -s` runs as SYSTEM but is not the service
    // (design D6): --service is required as well as the token.
    for (final arguments in [
      ['--bind', '127.0.0.1:0'],
      ['--console', '--bind', '127.0.0.1:0'],
    ]) {
      final cli = RunningCli(arguments, isLocalSystem: () => true);

      final code = await cli.exit;

      expect(code, isNonZero, reason: '$arguments');
      expect(
        cli.errors,
        contains('service_mode_required'),
        reason: '$arguments',
      );
      expect(cli.listening.isCompleted, isFalse, reason: 'no listener opened');
      expect(
        Directory(p.join(cli.data.path, 'data')).existsSync(),
        isFalse,
        reason: 'the daemon did not even start',
      );
    }
  });

  test('started_from_a_console_without_dev_mode', () async {
    // `yagurad run` and `yagurad run --service`, from a console: the token
    // is not LocalSystem.
    for (final arguments in [
      ['--bind', '127.0.0.1:0'],
      ['--console', '--bind', '127.0.0.1:0'],
      ['--service', '--bind', '127.0.0.1:0'],
    ]) {
      final cli = RunningCli(arguments, isLocalSystem: () => false);

      final code = await cli.exit;

      expect(code, isNonZero, reason: '$arguments');
      expect(
        cli.errors,
        contains('service_mode_required'),
        reason: '$arguments',
      );
      expect(cli.listening.isCompleted, isFalse, reason: 'no listener opened');
      expect(
        Directory(p.join(cli.data.path, 'data')).existsSync(),
        isFalse,
        reason: 'the daemon did not even start',
      );
    }
  });

  test('--dev with --service is a usage error', () async {
    final cli = RunningCli(['--dev', '--service', '--bind', '127.0.0.1:0']);

    expect(await cli.exit, isNonZero);
    expect(cli.listening.isCompleted, isFalse);
  });

  group('bind address', () {
    test('IPv6 loopback in brackets', () async {
      final bind = await parseDevBind('[::1]:9000');
      expect(bind.address.isLoopback, isTrue);
      expect(bind.port, 9000);
    });

    test('localhost resolving only to loopback is accepted', () async {
      final bind = await parseDevBind(
        'localhost:9000',
        lookup: (_) async => [
          InternetAddress.loopbackIPv6,
          InternetAddress.loopbackIPv4,
        ],
      );
      expect(bind.address.address, '127.0.0.1');
    });

    test('localhost resolving to a public address is refused', () async {
      await expectLater(
        parseDevBind(
          'localhost:9000',
          lookup: (_) async => [
            InternetAddress.loopbackIPv4,
            InternetAddress('10.0.0.5'),
          ],
        ),
        failsWith('dev_mode_requires_loopback', messageHas: ['10.0.0.5']),
      );
    });

    test('a host name that is not localhost is refused', () async {
      await expectLater(
        parseDevBind(
          'example.test:9000',
          lookup: (_) async => [InternetAddress('93.184.216.34')],
        ),
        throwsA(isA<YaguraException>()),
      );
    });

    test('a bind without a port uses the default port', () async {
      expect((await parseDevBind('127.0.0.1')).port, 7443);
    });
  });
}
