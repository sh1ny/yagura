import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/bind_address.dart';
import 'package:yagurad/src/cli/run_command.dart';
import 'package:yagurad/src/errors.dart';

import '../support/daemon_support.dart';

/// A `yagurad run` in this process: collects its output, reports where it
/// listens and stops when [stop] is called.
class RunningCli {
  RunningCli(List<String> arguments, {Directory? data})
    : data = data ?? Directory.systemTemp.createTempSync('yagurad_cli_') {
    addTearDown(() async {
      stop();
      await exit;
      if (this.data.existsSync()) this.data.deleteSync(recursive: true);
    });
    exit = runCli(
      ['run', ...arguments, '--data-dir', p.join(this.data.path, 'data')],
      CliEnvironment(
        out: _out,
        err: _err,
        stop: _stop.future,
        onListening: (address, port) {
          listening.complete((address, port));
        },
      ),
    );
    // A run that ends without listening ends the wait too.
    unawaited(exit.then((_) => _ended = true));
  }

  final Directory data;
  final _out = StringBuffer();
  final _err = StringBuffer();
  final _stop = Completer<void>();
  final listening = Completer<(InternetAddress, int)>();
  late final Future<int> exit;
  var _ended = false;

  String get output => '$_out';
  String get errors => '$_err';
  bool get ended => _ended;

  void stop() {
    if (!_stop.isCompleted) _stop.complete();
  }
}

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
    final cli = RunningCli(['--bind', '127.0.0.1:0']);

    final code = await cli.exit;

    expect(code, isNonZero);
    expect(cli.errors, contains('secure_mode_unavailable'));
    expect(cli.listening.isCompleted, isFalse, reason: 'no listener opened');
    expect(Directory(p.join(cli.data.path, 'data')).existsSync(), isFalse);
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
