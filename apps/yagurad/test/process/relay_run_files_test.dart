import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/process/relay_run_files.dart';
import 'package:yagurad/src/process/run_files.dart';

import '../support/daemon_support.dart';

// The relay replaces relay.json while the daemon polls it. Windows refuses to
// replace a file another handle has open at that moment, and the relay used to
// die on that refusal (exit code 255, no server started): the first elevated
// run of group 9 lost the second server of two seeded launches this way.

/// Holds [path] open for [hold] after saying it is open.
void _hold((SendPort, String, Duration) arguments) {
  final (port, path, hold) = arguments;
  final file = File(path).openSync();
  port.send('open');
  sleep(hold);
  file.closeSync();
}

void main() {
  test('the relay waits out a reader that has relay.json open', () async {
    final env = TestEnv();
    final directory = Directory(p.join(env.root.path, 'run'))
      ..createSync(recursive: true);
    final path = RunFiles(directory.path).relayPath;
    File(path).writeAsStringSync('{"format_version":1}');
    final opened = ReceivePort();
    await Isolate.spawn(_hold, (
      opened.sendPort,
      path,
      const Duration(milliseconds: 400),
    ));
    await opened.first;

    RelayRunFiles.writeJson(path, {'format_version': 1, 'relay_pid': 7});

    expect(jsonDecode(File(path).readAsStringSync()), {
      'format_version': 1,
      'relay_pid': 7,
    });
    expect(directory.listSync().map((e) => p.basename(e.path)), [
      'relay.json',
    ], reason: 'no temporary file is left');
  }, tags: ['windows']);
}
