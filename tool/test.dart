// Runs the tests of every workspace package: `dart test` for Dart packages,
// `flutter test` for Flutter packages. Arguments after the script name are
// forwarded to each test runner (for example `--exclude-tags valheim`).
//
// Usage: dart run tool/test.dart [test-runner arguments]
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent;
  final failed = <String>[];
  for (final member in _workspaceMembers(root)) {
    final dir = Directory('${root.path}/$member');
    if (!Directory('${dir.path}/test').existsSync()) continue;
    final usesFlutter = File('${dir.path}/pubspec.yaml')
        .readAsLinesSync()
        .any((line) => line.trim() == 'sdk: flutter');
    final command = usesFlutter ? 'flutter' : 'dart';
    stdout.writeln('==> $member: $command test ${arguments.join(' ')}');
    final process = await Process.start(
      command,
      ['test', ...arguments],
      workingDirectory: dir.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    if (await process.exitCode != 0) failed.add(member);
  }
  if (failed.isNotEmpty) {
    stderr.writeln('Tests failed in: ${failed.join(', ')}');
    exitCode = 1;
  }
}

/// Reads the `workspace:` list from the root pubspec.yaml.
List<String> _workspaceMembers(Directory root) {
  final lines = File('${root.path}/pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((line) => line.trim() == 'workspace:');
  final members = <String>[];
  for (final line in lines.skip(start + 1)) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('- ')) break;
    members.add(trimmed.substring(2).trim());
  }
  return members;
}
