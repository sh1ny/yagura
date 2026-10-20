import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_plugin/src/cli.dart';

import 'support.dart';

Future<(int, String, String)> _run(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args, out: out, err: err);
  return (code, '$out', '$err');
}

void main() {
  test('plugin lint exits 0 for a loadable plugin', () async {
    final dir = writePlugin(valheimManifest(), folder: 'valheim');

    final (code, out, err) = await _run(['plugin', 'lint', dir]);

    expect(code, 0);
    expect(out, contains('valheim: loaded'));
    expect(err, isEmpty);
  });

  test(
    'plugin lint prints the errors and exits non-zero when rejected',
    () async {
      final text = valheimWith(
        'protocol: udp\n    purpose: game',
        'protocol: tcpp\n    purpose: game',
      );
      final line = text.split('\n').indexWhere((l) => l.contains('tcpp')) + 1;
      final dir = writePlugin(text, folder: 'broken');

      final (code, out, err) = await _run(['plugin', 'lint', dir]);

      expect(code, isNot(0));
      expect(out, isEmpty);
      expect(err, contains('plugin.yaml:$line'));
      expect(err, contains('ports[0].protocol'));
      expect(err, contains('udp, tcp, both'));
    },
  );

  test('plugin lint exits 0 for the shipped DayZ plugin', () async {
    final (code, out, err) = await _run([
      'plugin',
      'lint',
      p.join('..', '..', 'plugins', 'dayz'),
    ]);

    expect(err, isEmpty);
    expect(code, 0);
    expect(out, contains('dayz: loaded'));
  });

  test('plugin lint without a directory is a usage error', () async {
    final (code, _, err) = await _run(['plugin', 'lint']);

    expect(code, 64);
    expect(err, contains('plugin lint'));
  });

  test('plugin lint of a missing directory fails', () async {
    final (code, _, err) = await _run(['plugin', 'lint', p.join('nope', 'x')]);

    expect(code, 1);
    expect(err, contains('not a directory'));
  });

  test('the yagura executable runs plugin lint', () async {
    final dir = writePlugin(valheimManifest(), folder: 'valheim');

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/yagura.dart',
      'plugin',
      'lint',
      dir,
    ]);

    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('valheim: loaded'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
