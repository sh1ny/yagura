import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/cli/service_command.dart';
import 'package:yagurad/src/platform/win32_service.dart';

import '../../test/support/elevated_support.dart';
import '../../test/support/process_support.dart';
import '../../test/support/service_rig.dart';

final _pairingString = RegExp(
  r'yagura://([^:/?]+):(\d+)\?code=([0-9A-Z]{10})'
  r'&ca=sha256:([0-9a-f]{64})&name=(\S+)',
);

void main() {
  // Real service control manager: the rows install a throwaway service
  // (`yagurad-t<random>`) from a bundle in the temp folder, so they run only
  // in the elevated workflow.
  test('install_as_a_service', tags: ['elevated'], () async {
    final rig = await ServiceRig.create(instances: 0);

    final install = await rig.install();

    // The service exists, starts automatically, runs as LocalSystem and runs
    // by the time the command returns.
    expect(rig.serviceState, serviceRunning);
    final query = powershell(
      "\$s = Get-CimInstance Win32_Service -Filter \"Name='${rig.name}'\"; "
      "'{0}|{1}|{2}' -f \$s.StartMode, \$s.StartName, \$s.State",
    );
    expect('${query.stdout}'.trim(), 'Auto|LocalSystem|Running');
    // The command printed what the administrator does next, and that works.
    final out = '${install.stdout}';
    expect(out, contains('yagurad pair'));
    final pair = await Process.run(rig.bundleExecutable, ['pair']);
    expect(pair.exitCode, 0, reason: '${pair.stderr}');
    expect('${pair.stdout}', matches(_pairingString));

    // `service status` reports the service and the daemon behind it.
    final status = await rig.service(['status']);
    expect(status.exitCode, 0, reason: '${status.stderr}');
    expect('${status.stdout}', contains('state: running'));
    expect('${status.stdout}', contains('bind: 127.0.0.1:${rig.port}'));

    // `service configure` changes the bind for the next start.
    final other = rig.port + 1;
    final configure = await rig.service([
      'configure',
      '--bind',
      '127.0.0.1:$other',
    ]);
    expect(configure.exitCode, 0, reason: '${configure.stderr}');
    rig.restart();
    await rig.eventuallyHolds(
      () => rig.serviceState == serviceRunning,
      reason: 'the service to run again',
    );
    final restarted = await rig.service(['status']);
    expect('${restarted.stdout}', contains('bind: 127.0.0.1:$other'));

    // `service uninstall --purge-accounts` removes the service; there are no
    // service accounts yet to purge.
    final uninstall = await rig.service(['uninstall', '--purge-accounts']);
    expect(uninstall.exitCode, 0, reason: '${uninstall.stderr}');
    expect(rig.serviceState, isNull);
    expect(Directory(rig.installRoot).existsSync(), isFalse);
    expect(
      Directory(rig.data).existsSync(),
      isTrue,
      reason: 'the data directory stays',
    );
  });

  test(
    'uninstall_keeps_the_data_and_the_running_servers',
    tags: ['elevated'],
    () async {
      final rig = await ServiceRig.create();
      await rig.install();
      await rig.whenServersAttached(2);
      final pids = Map.of(rig.runningServers());

      final uninstall = await rig.service(['uninstall']);

      expect(uninstall.exitCode, 0, reason: '${uninstall.stderr}');
      expect(rig.serviceState, isNull);
      for (final pid in pids.values) {
        expect(processAlive(pid), isTrue, reason: 'server $pid');
      }
      // A second uninstall has nothing to remove.
      final again = await rig.service(['uninstall']);
      expect(again.exitCode, 1);
      expect('${again.stderr}', contains('service_not_installed'));
    },
  );

  test(
    'purge_accounts_with_a_running_server_is_refused',
    tags: ['elevated'],
    () async {
      final rig = await ServiceRig.create();
      await rig.install();
      await rig.whenServersAttached(2);

      final purge = await rig.service(['uninstall', '--purge-accounts']);

      expect(purge.exitCode, 1);
      expect('${purge.stderr}', contains('servers_running'));
      expect(rig.serviceState, serviceRunning, reason: 'nothing was changed');
    },
  );

  // Runs the command in this process with the real service control manager,
  // but never installs: when the session is elevated the check is told it is
  // not, so the row also passes in the elevated workflow.
  test('not_elevated', tags: ['windows'], () async {
    final suffix = Random.secure().nextInt(1 << 30).toRadixString(16);
    final name = 'yagurad-t$suffix';
    final temp = Directory.systemTemp.createTempSync('yagurad_noelev_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final installDir = p.join(temp.path, 'install');
    final out = StringBuffer();
    final err = StringBuffer();

    final code = await runServiceCommand(
      ['install', '--service-name', name, '--install-dir', installDir],
      out: out,
      err: err,
      service: ServiceEnvironment(isElevated: () => false),
    );

    expect(code, isNot(0));
    expect('$err', contains('elevation_required'));
    expect(queryServiceState(name), isNull, reason: 'no service is registered');
    expect(Directory(installDir).existsSync(), isFalse);
  });

  test('already_installed', tags: ['elevated'], () async {
    final rig = await ServiceRig.create(instances: 0);
    await rig.install();
    final before = File(p.join(rig.installRoot, '${rig.name}.xml'))
        .readAsStringSync();

    final again = await rig.service([
      'install',
      '--bind',
      '127.0.0.1:${rig.port}',
    ]);

    expect(again.exitCode, isNot(0));
    expect('${again.stderr}', contains('service_exists'));
    expect(
      rig.serviceState,
      serviceRunning,
      reason: 'the service is unchanged',
    );
    expect(
      File(p.join(rig.installRoot, '${rig.name}.xml')).readAsStringSync(),
      before,
    );
  });
}
