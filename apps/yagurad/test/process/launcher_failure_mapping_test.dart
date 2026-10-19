import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_logon.dart';
import 'package:yagurad/src/process/launcher_modes.dart';

// Design D7: only the logon steps are a logon failure; a failure to create
// the process once the logon succeeded is launch_failed.
void main() {
  test('a_logon_step_failure_is_a_logon_failure', () {
    const failure = LogonFailure('yagura-srv', 'LogonUserW', 1326);

    expect(launcherExitFor(failure), helperLogonFailed);
  });

  test('a_process_creation_failure_is_not_a_logon_failure', () {
    const failure = LogonFailure(
      'yagura-srv',
      'CreateProcessAsUserW',
      5,
      stage: LogonStage.process,
    );

    expect(launcherExitFor(failure), helperFailed);
    expect(
      launcherFailureText(failure),
      allOf(contains('CreateProcessAsUserW'), contains('5')),
    );
  });
}
