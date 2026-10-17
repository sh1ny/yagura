import 'dart:io';

import 'package:yagura_plugin/src/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
