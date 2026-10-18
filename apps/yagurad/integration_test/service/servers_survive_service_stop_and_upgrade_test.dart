import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_service.dart';

import '../../test/support/process_support.dart';
import '../../test/support/service_rig.dart';

// The real service: two fake game servers run, the service stops, restarts or
// is upgraded, and the servers must go on. Elevated workflow only.
void main() {
  test('service_restart', tags: ['elevated'], () async {
    final rig = await ServiceRig.create();
    await rig.install();
    await rig.whenServersAttached(2);
    final before = Map.of(rig.runningServers());
    expect(before, hasLength(2));

    rig.restart();

    await rig.eventuallyHolds(
      () => rig.serviceState == serviceRunning,
      reason: 'the service to run again',
    );
    // Both server processes keep their PIDs...
    for (final pid in before.values) {
      expect(processAlive(pid), isTrue, reason: 'server $pid after restart');
    }
    // ...and the new daemon re-attached to both: they are recorded as
    // running, and nothing else was started.
    await rig.whenServersAttached(2);
    expect(rig.runningServers(), before);
    expect(
      rig.runs().where((run) => run['state'] == 'running'),
      hasLength(2),
      reason: 'no run was started again',
    );
    expect(rig.runs(), hasLength(2));
  });

  test('service_upgraded_in_place', tags: ['elevated'], () async {
    final rig = await ServiceRig.create();
    await rig.install();
    await rig.whenServersAttached(2);
    final before = Map.of(rig.runningServers());
    final older = await rig.daemonStatus();
    expect(older, isNot(contains(r'\99.0.0\')));
    // A newer bundle: the same build named as a newer release.
    final newer = rig.assembleBundle(
      p.join(rig.work.path, 'bundle-newer'),
      version: '99.0.0',
    );

    final upgrade = await rig.service(['install'], bundle: newer);

    expect(upgrade.exitCode, 0, reason: '${upgrade.stdout}${upgrade.stderr}');
    expect('${upgrade.stdout}', contains('upgraded'));
    expect(rig.serviceState, serviceRunning);
    // The service runs the newer version...
    expect(await rig.daemonStatus(), contains(r'\99.0.0\'));
    expect(Directory(p.join(rig.installRoot, '99.0.0')).existsSync(), isTrue);
    // ...the servers keep their PIDs, and the new daemon re-attached.
    for (final pid in before.values) {
      expect(processAlive(pid), isTrue, reason: 'server $pid after upgrade');
    }
    await rig.whenServersAttached(2);
    expect(rig.runningServers(), before);
    expect(rig.runs(), hasLength(2), reason: 'no run was started again');
  });

  test('server_exits_while_the_daemon_is_down', tags: ['elevated'], () async {
    final rig = await ServiceRig.create();
    await rig.install();
    await rig.whenServersAttached(2);
    final before = Map.of(rig.runningServers());
    final victim = before.entries.first;
    final survivor = before.entries.last;

    rig.stopService();
    await rig.eventuallyHolds(
      () => rig.serviceState == serviceStopped,
      reason: 'the service to stop',
    );
    for (final pid in before.values) {
      expect(
        processAlive(pid),
        isTrue,
        reason: 'server $pid with the service stopped',
      );
    }
    // One server exits by itself while nobody supervises it: the relay
    // records the exit code in its run directory.
    Process.killPid(victim.value);
    await rig.eventuallyHolds(
      () => !processAlive(victim.value),
      reason: 'the server to exit',
      timeout: const Duration(seconds: 30),
    );
    final exitFile = await _waitForExitRecord(rig, victim.key);
    final recorded = (jsonDecode(
      exitFile.readAsStringSync(),
    ) as Map<String, Object?>)['exit_code'];

    rig.startService();

    await rig.eventuallyHolds(
      () => rig.serviceState == serviceRunning,
      reason: 'the service to run',
    );
    // The run ended with the exit code of the relay's record...
    await rig.eventuallyHolds(
      () => rig.runs().any(
        (run) => run['name'] == victim.key && run['state'] == 'ended',
      ),
      reason: 'the daemon to end the run of the exited server',
    );
    final ended = rig.runs().firstWhere(
      (run) => run['name'] == victim.key && run['state'] == 'ended',
    );
    expect(ended['exit_code'], recorded);
    expect(ended['end_reason'], isNotEmpty);
    // ...and the other server was re-attached untouched.
    expect(rig.runningServers()[survivor.key], survivor.value);
    expect(processAlive(survivor.value), isTrue);
  });
}

/// The `exit.json` the relay of [instance] wrote. Looked up in the run
/// directories under the data directory.
Future<File> _waitForExitRecord(ServiceRig rig, String instance) async {
  File? found;
  await rig.eventuallyHolds(
    () {
      for (final entity in Directory(rig.data).listSync(recursive: true)) {
        if (entity is File &&
            p.basename(entity.path) == 'exit.json' &&
            _belongsTo(rig, entity, instance)) {
          found = entity;
          return true;
        }
      }
      return false;
    },
    reason: 'the relay to record the exit of $instance',
    timeout: const Duration(seconds: 30),
  );
  return found!;
}

bool _belongsTo(ServiceRig rig, File exitFile, String instance) {
  final relay = File(p.join(p.dirname(exitFile.path), 'relay.json'));
  if (!relay.existsSync()) return false;
  final pid = (jsonDecode(
    relay.readAsStringSync(),
  ) as Map<String, Object?>)['server_pid'];
  return rig.servers[instance] == pid;
}
