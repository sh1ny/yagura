import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/cli/run_command.dart';
import 'package:yagurad/src/host/secret_store.dart';

import 'temp_support.dart';

/// A `yagurad run` in this process: collects its output, reports where it
/// listens and stops when [stop] is called.
class RunningCli {
  RunningCli(
    List<String> arguments, {
    Directory? data,
    bool Function()? isLocalSystem,
    SecretProtector? secretProtector,
  }) : data = data ?? createCanonicalTempSync('yagurad_cli_') {
    addTearDown(() async {
      stop();
      await exit;
      if (this.data.existsSync()) this.data.deleteSync(recursive: true);
    });
    exit = runCli(
      ['run', ...arguments, '--data-dir', p.join(this.data.path, 'data')],
      CliEnvironment(
        out: _out,
        err: _err,
        stop: _stop.future,
        onListening: (address, port) {
          listening.complete((address, port));
        },
        isLocalSystem: isLocalSystem,
        secretProtector: secretProtector,
      ),
    );
    // A run that ends without listening ends the wait too.
    unawaited(exit.then((_) => _ended = true));
  }

  final Directory data;
  final _out = StringBuffer();
  final _err = StringBuffer();
  final _stop = Completer<void>();
  final listening = Completer<(InternetAddress, int)>();
  late final Future<int> exit;
  var _ended = false;

  String get output => '$_out';
  String get errors => '$_err';
  bool get ended => _ended;

  void stop() {
    if (!_stop.isCompleted) _stop.complete();
  }

  /// Waits until the run listens; fails the test when it ends first.
  Future<(InternetAddress, int)> whenListening() => Future.any([
    listening.future,
    exit.then<(InternetAddress, int)>((code) => fail('exited $code: $errors')),
  ]).timeout(const Duration(seconds: 30));
}
