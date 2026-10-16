// Tries the data directory lock from a separate process, standing in for a
// second yagurad. It uses only dart:io (no package imports, so `dart run`
// needs no build hooks) and locks the byte the daemon locks, passed in as
// DataDirLock.lockOffset. Prints `acquired`, or `locked <PID in the file>`.
//
// Usage: dart run test/support/lock_probe.dart <lock file> <offset>
import 'dart:io';

void main(List<String> args) {
  final path = args[0];
  final offset = int.parse(args[1]);
  final file = File(path).openSync(mode: FileMode.append);
  try {
    file.lockSync(FileLock.exclusive, offset, offset + 1);
    stdout.writeln('acquired');
  } on FileSystemException {
    stdout.writeln('locked ${File(path).readAsStringSync().trim()}');
    exitCode = 3;
  } finally {
    file.closeSync();
  }
}
