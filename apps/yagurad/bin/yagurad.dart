import 'dart:io';

import 'package:yagurad/src/cli/run_command.dart';

/// Entry point. `run --dev` serves the development API; the `launch`,
/// `relay` and `signal` modes (design D2) arrive with the process model.
Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments, CliEnvironment(out: stdout, err: stderr));
}
