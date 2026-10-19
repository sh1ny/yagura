import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/confined_fs.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/daemon_support.dart';
import '../support/steam_support.dart';
import '../support/temp_support.dart';

/// A launcher whose process ends at once with [code] and no output.
class _FailingLauncher implements SteamProcessLauncher {
  _FailingLauncher(this.code);

  final int code;

  @override
  Future<SteamProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async => _Process(code);

  @override
  Future<void> close() async {}
}

class _Process implements SteamProcess {
  _Process(this._code);

  final int _code;

  @override
  int get pid => 1;

  @override
  Stream<String> get lines => const Stream.empty();

  @override
  Future<int> get exitCode async => _code;

  @override
  void kill() {}
}

void main() {
  test('an_unpack_failure_names_the_exit_code_and_the_output', () async {
    final root = createCanonicalTempSync('yagurad_unpack_');
    addTearDown(() => root.deleteSync(recursive: true));
    final server = await serveArchive(body: const [1, 2, 3]);
    final bootstrap = SteamCmdBootstrap(
      source: Uri.parse('http://127.0.0.1:${server.port}/steamcmd.zip'),
    );

    await expectLater(
      bootstrap.install(
        ConfinedFs(p.join(root.path)),
        'steamcmd',
        launcher: _FailingLauncher(0xC0000142),
      ),
      failsWith(
        'steamcmd_unavailable',
        messageHas: ['could not be unpacked', '3221225794 (0xC0000142)'],
      ),
    );
  });
}
