@Tags(['windows'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/daemon_support.dart';
import '../support/steam_support.dart';

final onWindows = Platform.isWindows ? false : 'needs Windows';

bool alive(int pid) => Process.killPid(pid);

Future<SteamProcess> startFake(
  JobObjectLauncher launcher,
  Map<String, String> environment,
) => launcher.start(
  Platform.resolvedExecutable,
  [fakeSteamCmdScript, '+quit'],
  workingDirectory: Directory.systemTemp.path,
  environment: environment,
);

void main() {
  test('output_and_exit_code_come_back', () async {
    final launcher = JobObjectLauncher();
    addTearDown(launcher.close);

    final process = await startFake(launcher, {});
    final lines = await process.lines.toList();

    expect(await process.exitCode, 0);
    expect(lines, contains('Loading Steam API...OK'));
  }, skip: onWindows);

  test('stdin_is_closed', () async {
    final env = TestEnv();
    final record = '${env.root.path}\\record.jsonl';
    final launcher = JobObjectLauncher();
    addTearDown(launcher.close);

    final process = await startFake(launcher, {'FAKE_STEAMCMD_RECORD': record});
    await process.lines.drain<void>();
    await process.exitCode;

    expect(File(record).readAsStringSync(), contains('"stdinClosed":true'));
  }, skip: onWindows);

  test('kill_ends_the_process', () async {
    final launcher = JobObjectLauncher();
    addTearDown(launcher.close);
    final process = await launcher.start(
      Platform.resolvedExecutable,
      [fakeSteamCmdScript, '+app_update', '1', '+quit'],
      workingDirectory: Directory.systemTemp.path,
      environment: {'FAKE_STEAMCMD_STALL_AFTER': '3'},
    );
    await process.lines.first;

    process.kill();

    await process.exitCode.timeout(const Duration(seconds: 10));
    expect(alive(process.pid), isFalse);
  }, skip: onWindows);

  test('closing_the_launcher_kills_what_it_started', () async {
    final launcher = JobObjectLauncher();
    final process = await launcher.start(
      Platform.resolvedExecutable,
      [fakeSteamCmdScript, '+app_update', '1', '+quit'],
      workingDirectory: Directory.systemTemp.path,
      environment: {'FAKE_STEAMCMD_STALL_AFTER': '3'},
    );
    await process.lines.first;

    await launcher.close();

    await process.exitCode.timeout(const Duration(seconds: 10));
    await eventually(() => !alive(process.pid), reason: 'process gone');
  }, skip: onWindows);

  test('arguments_with_spaces_and_quotes_survive', () {
    expect(quoteWindowsArgument('plain'), 'plain');
    expect(quoteWindowsArgument(r'C:\a dir\x'), r'"C:\a dir\x"');
    expect(quoteWindowsArgument(r'say "hi"'), r'"say \"hi\""');
    expect(quoteWindowsArgument(r'C:\a dir\'), r'"C:\a dir\\"');
    expect(quoteWindowsArgument(''), '""');
  });
}
