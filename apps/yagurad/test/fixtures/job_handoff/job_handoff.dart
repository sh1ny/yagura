// Stands in for a SteamCMD that hands its work to a copy of itself and exits.
//
//   dart job_handoff.dart parent <dir> <child-ms>
//     starts the child, waits until it wrote <dir>/child_started, exits 0
//   dart job_handoff.dart child <dir> <child-ms>
//     writes <dir>/child_started, sleeps <child-ms>, writes <dir>/child_done
import 'dart:io';

Future<void> main(List<String> args) async {
  final [mode, dir, milliseconds] = args;
  final started = File('$dir/child_started');
  if (mode == 'child') {
    started.writeAsStringSync('');
    await Future<void>.delayed(Duration(milliseconds: int.parse(milliseconds)));
    File('$dir/child_done').writeAsStringSync('');
    return;
  }
  await Process.start(Platform.resolvedExecutable, [
    Platform.script.toFilePath(),
    'child',
    dir,
    milliseconds,
  ], mode: ProcessStartMode.detached);
  while (!started.existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
