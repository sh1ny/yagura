@Tags(['windows'])
library;

import 'package:test/test.dart';

import '../support/elevated_support.dart';
import '../support/logon_support.dart';

// The command runner of the elevated rows, tried with harmless commands: it
// must not hang on a prompt, must end a command that runs out of time, and
// must report a failed logon instead of waiting. (The rows that use it run
// only in the elevated workflow.)
void main() {
  test('a_command_runs_and_its_output_is_collected', () async {
    final result = await runCommand('cmd.exe', ['/c', 'echo hello']);

    expect(result.exitCode, 0);
    expect('${result.stdout}', contains('hello'));
  });

  test('a_command_that_reads_input_sees_the_end_of_it', () async {
    // `set /p` waits for a line; with stdin closed it returns at once.
    final result = await runCommand('cmd.exe', [
      '/c',
      'set /p x= & echo finished',
    ], timeout: const Duration(seconds: 20));

    expect('${result.stdout}', contains('finished'));
  });

  test('a_command_that_runs_out_of_time_is_ended', () async {
    final watch = Stopwatch()..start();

    final result = await runCommand(
      'ping.exe',
      ['-n', '60', '127.0.0.1'],
      timeout: const Duration(seconds: 2),
      failOnTimeout: false,
    );

    expect(result.exitCode, -1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
  });

  test('a_logon_that_fails_is_reported_and_does_not_wait', () async {
    final result = await runAsUser(
      user: 'yagurad-no-such-user',
      password: 'Aa1!nothing',
      commandLine: 'cmd.exe /c exit 0',
      workingDirectory: r'C:\',
      timeout: const Duration(seconds: 10),
      killTree: killProcessTree,
    );

    expect(result.started, isFalse);
    expect(result.error, isNot(0));
  });
}
