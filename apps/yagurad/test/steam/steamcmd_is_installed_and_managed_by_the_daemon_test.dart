import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/daemon_support.dart';
import '../support/steam_support.dart';

void main() {
  test('first_install_bootstraps_steamcmd', () async {
    final env = TestEnv();
    env.installValheim();
    final server = await serveArchive(
      body: tarArchive({
        'steamcmd.exe': utf8.encode('MZ placeholder'),
        'steamcmd.sh': utf8.encode('#!/bin/sh'),
      }),
    );
    final steam = SteamHarness(
      env,
      ready: false,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
      ),
    );
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final op = daemon.instances.install(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(
      File(p.join(steam.installation, 'steamcmd.exe')).existsSync(),
      isTrue,
      reason: 'the archive was unpacked into <data>/steamcmd/anonymous',
    );
    expect(
      File(p.join(steam.installation, SteamCmdService.readyMarker))
          .existsSync(),
      isTrue,
    );
    // The self-update run (+quit alone) came before the app run.
    final runs = steam.runs();
    expect(runs, hasLength(2));
    expect((runs.first['args']! as List).last, '+quit');
    expect(runs.first['appId'], isNull);
    expect(runs.last['appId'], valheimAppId);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('steamcmd_download_fails', () async {
    final env = TestEnv();
    env.installValheim();
    final server = await serveArchive(status: HttpStatus.serviceUnavailable);
    final steam = SteamHarness(
      env,
      ready: false,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.tar'),
      ),
    );
    final daemon = await env.start(steamService: steam.service);
    final instance = await createValheim(daemon);

    final done = await daemon.operations.whenDone(
      daemon.instances.install(instance.id).id,
    );

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'steamcmd_unavailable');
    expect(done.resultMessage, contains('503'));
    expect(
      File(p.join(steam.installation, SteamCmdService.readyMarker))
          .existsSync(),
      isFalse,
      reason: 'no partial directory is marked ready',
    );
    expect(steam.launcher.started, isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);
  });

  test('steamcmd_download_network_error', () async {
    final env = TestEnv();
    final dead = await serveArchive();
    final port = dead.port;
    await dead.close(force: true);
    final steam = SteamHarness(
      env,
      ready: false,
      bootstrap: SteamCmdBootstrap(
        source: Uri.parse('http://127.0.0.1:$port/steamcmd.tar'),
      ),
    );

    await expectLater(
      steam.service.installApp(
        SteamAppRequest(
          appId: valheimAppId,
          installDirectory: p.join(env.root.path, 'server'),
        ),
        RecordingReporter(),
        CancelToken(),
      ),
      failsWith(
        'steamcmd_unavailable',
        messageHas: ['could not be downloaded'],
      ),
    );
    expect(
      File(p.join(steam.installation, SteamCmdService.readyMarker))
          .existsSync(),
      isFalse,
    );
  });
}
