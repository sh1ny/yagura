@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../../test/support/account_support.dart';
import '../../test/support/service_client.dart';
import '../../test/support/service_rig.dart';
import '../../test/support/valheim_support.dart';

// graceful-stop, "A stop from the service" (spike S2.6, design D7): the real
// Valheim server runs as `yagura-srv` under the service, and a Stop through
// the API reaches it as a console signal, so it saves its world before it
// exits. Needs a Valheim server install (YAGURA_VALHEIM_SERVER, as the
// development row `valheim_saves_on_a_signal_stop`) and the manual `elevated`
// workflow.

void main() {
  test(
    'valheim_saves_on_a_signal_stop_from_the_service',
    tags: ['elevated', 'valheim'],
    skip: Platform.environment[valheimServerEnvironment] == null
        ? '$valheimServerEnvironment names no Valheim server install'
        : null,
    () async {
      final existing = Platform.environment[valheimServerEnvironment]!;
      expect(
        File(p.join(existing, 'valheim_server.exe')).existsSync(),
        isTrue,
        reason: '$valheimServerEnvironment has no valheim_server.exe',
      );
      final rig = await ServiceRig.create(instances: 0);
      // The shipped plugin, not the test fixture.
      File(
        p.absolute('..', '..', 'plugins', 'valheim', 'plugin.yaml'),
      ).copySync(p.join(rig.process.env.pluginsDir, 'valheim', 'plugin.yaml'));
      await rig.seedFakeSteamCmd();
      await rig.install();
      final client = await ServiceClient.pair(rig);

      var instance = await client.instances.createInstance(
        pb.CreateInstanceRequest(
          pluginId: 'valheim',
          name: 'Service signal stop',
          settings: pb.JsonDocument(
            json: '{"serverName":"Service signal stop"}',
          ),
        ),
      );
      final id = instance.id;
      // Copied by the test (an administrator): the files inherit the
      // instance's entries for yagura-srv.
      copyDirectory(existing, p.join(instance.directory, 'server'));
      await client.succeeded(
        await client.instances.install(pb.LifecycleRequest(instanceId: id)),
      );

      final started = await client.succeeded(
        await client.instances.start(pb.LifecycleRequest(instanceId: id)),
        timeout: const Duration(minutes: 10),
      );
      expect(started.resultReason, isEmpty);
      instance = await client.instances.getInstance(
        pb.GetInstanceRequest(instanceId: id),
      );
      expect(instance.state, pb.InstanceState.INSTANCE_STATE_RUNNING);
      final serverPid = instance.pid;
      expect(await processOwnerSid(serverPid), await accountSid('yagura-srv'));

      final log = File(p.join(instance.directory, 'logs', 'server.log'));
      expect(log.readAsStringSync(), contains('Game server connected'));
      final saveLine = RegExp(r'World save \(5/5\) done');
      final savesBefore = saveLine.allMatches(log.readAsStringSync()).length;
      final world = Directory(
        p.join(instance.directory, 'save', 'worlds_local', 'Dedicated'),
      );
      final generationBefore = _newestDb(world)?.path;

      final requestedAt = DateTime.now();
      final stopped = await client.succeeded(
        await client.instances.stop(pb.LifecycleRequest(instanceId: id)),
        timeout: const Duration(minutes: 2),
      );
      expect(stopped.resultReason, 'stopped_by:graceful');
      await rig.eventuallyHolds(
        () => !processAliveForTest(serverPid),
        reason: 'the server to exit',
        timeout: const Duration(seconds: 30),
      );
      instance = await client.instances.getInstance(
        pb.GetInstanceRequest(instanceId: id),
      );
      expect(instance.state, pb.InstanceState.INSTANCE_STATE_STOPPED);

      // The relay wrote the observed exit time to the run's exit.json (UTC).
      final exitFiles = Directory(p.join(instance.directory, '.yagura', 'run'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.basename(f.path) == 'exit.json')
          .toList();
      expect(exitFiles, hasLength(1));
      final exit = jsonDecode(exitFiles.single.readAsStringSync()) as Map;
      final exitedAt = DateTime.parse(exit['exited_at'] as String);
      expect(exit['exit_code'], 0);

      // The world save was written after the stop was requested and no later
      // than the exit.
      final db = _newestDb(world);
      expect(db, isNotNull, reason: 'no world save in ${world.path}');
      final savedAt = db!.statSync().modified;
      expect(savedAt.isAfter(requestedAt), isTrue, reason: 'save $savedAt');
      expect(savedAt.isAfter(exitedAt), isFalse, reason: 'save $savedAt');
      if (generationBefore != null) {
        expect(db.path, isNot(generationBefore), reason: 'a new generation');
      }
      expect(
        saveLine.allMatches(log.readAsStringSync()).length,
        greaterThan(savesBefore),
      );
    },
  );
}

/// Whether the process [pid] still exists.
bool processAliveForTest(int pid) {
  final result = Process.runSync('tasklist', [
    '/FI',
    'PID eq $pid',
    '/FO',
    'CSV',
    '/NH',
  ]);
  return '${result.stdout}'.contains('"$pid"');
}

/// The newest `_main.<N>.db2` in [world], or null when there is none.
File? _newestDb(Directory world) {
  if (!world.existsSync()) return null;
  final files = world
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'_main\.\d+\.db2$').hasMatch(f.path))
      .toList();
  if (files.isEmpty) return null;
  files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
  return files.last;
}
