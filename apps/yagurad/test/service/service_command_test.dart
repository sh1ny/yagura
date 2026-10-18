import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/cli/run_command.dart';
import 'package:yagurad/src/cli/service_command.dart';
import 'package:yagurad/src/service/bundle.dart';

import '../support/service_support.dart';

/// `yagurad service ...` through `runCli`, over the fakes of the installer.
class _Cli {
  _Cli({this.elevated = true, bool withBundle = true})
    : temp = Directory.systemTemp.createTempSync() {
    addTearDown(() => temp.deleteSync(recursive: true));
    bundle = withBundle ? makeBundle('0.1.0', parent: temp) : null;
  }

  final Directory temp;
  late final Bundle? bundle;
  final bool elevated;
  final control = FakeServiceControl();
  final servers = FakeServers();
  final purger = FakePurger();
  var clock = DateTime.utc(2026, 1, 1);

  String get installDir => p.join(temp.path, 'Program Files', 'Yagura');

  Future<({int code, String out, String err})> run(
    List<String> arguments,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      ['service', ...arguments],
      CliEnvironment(
        out: out,
        err: err,
        service: ServiceEnvironment(
          control: control,
          isElevated: () => elevated,
          bundle: bundle,
          admin: (command, [args = const {}]) async => {
            'mode': 'service',
            'version': '0.1.0',
            'api_port': 7443,
          },
          servers: servers,
          purger: purger,
          environment: {'ProgramFiles': p.join(temp.path, 'Program Files')},
          delay: (d) async => clock = clock.add(d),
          now: () => clock,
        ),
      ),
    );
    return (code: code, out: '$out', err: '$err');
  }
}

void main() {
  test('no_subcommand_prints_the_usage', () async {
    final result = await _Cli().run([]);

    expect(result.code, 64);
    expect(result.err, contains('yagurad service install'));
  });

  test('an_unknown_subcommand_is_a_usage_error', () async {
    final result = await _Cli().run(['frobnicate']);

    expect(result.code, 64);
    expect(result.err, contains('unknown service command "frobnicate"'));
  });

  test('configure_needs_a_bind', () async {
    final result = await _Cli().run(['configure']);

    expect(result.code, 64);
    expect(result.err, contains('--bind'));
  });

  test('a_service_name_with_a_path_in_it_is_refused', () async {
    final result = await _Cli().run(['status', '--service-name', r'..\evil']);

    expect(result.code, 64);
  });

  test('install_then_status_then_uninstall', () async {
    final cli = _Cli();

    final install = await cli.run(['install', '--bind', '127.0.0.1:7443']);
    expect(install.code, 0, reason: install.err);
    expect(install.out, contains('yagurad pair'));
    expect(File(p.join(cli.installDir, 'yagurad.xml')).existsSync(), isTrue);

    final status = await cli.run(['status']);
    expect(status.code, 0, reason: status.err);
    expect(status.out, contains('state: running'));
    expect(status.out, contains('bind: 127.0.0.1:7443'));

    final uninstall = await cli.run(['uninstall']);
    expect(uninstall.code, 0, reason: uninstall.err);
    expect(Directory(cli.installDir).existsSync(), isFalse);
  });

  test('a_failure_prints_the_reason_and_exits_1', () async {
    final result = await _Cli(elevated: false).run(['install']);

    expect(result.code, 1);
    expect(result.err, startsWith('yagurad: elevation_required: '));
  });

  test('elevation_is_checked_before_the_bundle_is_looked_at', () async {
    // No bundle is given and the test runs under the Dart VM, not from a
    // bundle: the elevation check still comes first.
    final result = await _Cli(
      elevated: false,
      withBundle: false,
    ).run(['install']);

    expect(result.code, 1);
    expect(result.err, contains('elevation_required'));
  });

  test('without_a_bundle_an_elevated_install_is_bundle_invalid', () async {
    final result = await _Cli(withBundle: false).run(['install']);

    expect(result.code, 1);
    expect(result.err, contains('bundle_invalid'));
  });

  test('a_second_install_of_the_same_version_is_service_exists', () async {
    final cli = _Cli();
    await cli.run(['install']);

    final again = await cli.run(['install']);

    expect(again.code, 1);
    expect(again.err, contains('service_exists'));
  });

  test('purge_accounts_with_a_server_running_is_servers_running', () async {
    final cli = _Cli();
    await cli.run(['install']);
    cli.servers.running = ['Friends'];

    final result = await cli.run(['uninstall', '--purge-accounts']);

    expect(result.code, 1);
    expect(result.err, contains('servers_running'));
    expect(result.err, contains('Friends'));
    expect(cli.purger.calls, 0);
  });

  test('the_install_dir_option_moves_the_installation', () async {
    final cli = _Cli();
    final dir = p.join(cli.temp.path, 'elsewhere');

    final result = await cli.run([
      'install',
      '--install-dir',
      dir,
      '--service-name',
      'yagurad-test',
    ]);

    expect(result.code, 0, reason: result.err);
    expect(File(p.join(dir, 'yagurad-test.xml')).existsSync(), isTrue);
    expect(cli.control.services, {'yagurad-test': anything});
  });
}
