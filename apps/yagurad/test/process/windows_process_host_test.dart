import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/process/process_host.dart';
import 'package:yagurad/src/process/windows_process_host.dart';

import '../support/daemon_support.dart';

void main() {
  test(
    'a daemon run through the Dart VM refuses to launch with a clear reason',
    () async {
      // Under `dart run` the helper modes would be handed to dart.exe, which
      // answers "Could not find a command named launch".
      final dir = Directory.systemTemp.createTempSync('yagura_host_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final host = WindowsProcessHost(
        helperExecutable: Platform.resolvedExecutable,
      );

      await expectLater(
        host.launch(
          LaunchRequest(
            instanceId: 'inst-1',
            runId: 'run-1',
            executable: p.join(dir.path, 'server.exe'),
            args: const [],
            env: const {},
            workingDirectory: dir.path,
            instanceDirectory: dir.path,
            runDirectory: p.join(dir.path, 'run'),
          ),
        ),
        failsWith('launch_failed', messageHas: ['dart build cli']),
      );
    },
    testOn: 'windows',
  );
}
