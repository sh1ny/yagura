import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'loader.dart';
import 'plugin_result.dart';

/// Exit status when the plugin was loaded.
const exitLoaded = 0;

/// Exit status when the plugin was rejected.
const exitRejected = 1;

/// Exit status for a usage error.
const exitUsage = 64;

/// Runs the `yagura` command line: currently `yagura plugin lint <dir>`.
///
/// Results go to [out], problems and usage errors to [err]; both default to
/// the process streams. Returns the process exit status.
Future<int> runCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final runner = CommandRunner<int>(
    'yagura',
    'Yagura command line tools.',
    usageLineLength: 80,
  )..addCommand(_PluginCommand(stdoutSink, stderrSink));
  try {
    return await runner.run(args) ?? exitLoaded;
  } on UsageException catch (e) {
    stderrSink
      ..writeln(e.message)
      ..writeln(e.usage);
    return exitUsage;
  }
}

class _PluginCommand extends Command<int> {
  _PluginCommand(StringSink out, StringSink err) {
    addSubcommand(_LintCommand(out, err));
  }

  @override
  String get name => 'plugin';

  @override
  String get description => 'Work with game plugins.';
}

class _LintCommand extends Command<int> {
  _LintCommand(this._out, this._err);

  final StringSink _out;
  final StringSink _err;

  @override
  String get name => 'lint';

  @override
  String get description =>
      'Validate the plugin in <dir> the way the daemon loads it.';

  @override
  String get invocation => 'yagura plugin lint <dir>';

  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected exactly one plugin directory.');
    }
    final directory = rest.single;
    if (!Directory(directory).existsSync()) {
      _err.writeln('$directory: not a directory');
      return exitRejected;
    }
    final result = loadPlugin(directory);
    if (result.isLoaded) {
      _out.writeln(
        '${result.id}: loaded (${result.name} ${result.version}; '
        'platforms: ${result.platforms.join(', ')})',
      );
      return exitLoaded;
    }
    final manifest = p.join(directory, 'plugin.yaml');
    _err.writeln('${result.id}: rejected');
    for (final reason in result.reasons) {
      _err.writeln(_format(manifest, reason));
    }
    return exitRejected;
  }
}

String _format(String manifest, PluginReason reason) {
  final file = reason.path == 'hooks.js'
      ? p.join(p.dirname(manifest), 'hooks.js')
      : manifest;
  final location = reason.line == null ? file : '$file:${reason.line}';
  final field = reason.path == null ? '' : ' ${reason.path}:';
  return '$location: [${reason.code}]$field ${reason.message}';
}
