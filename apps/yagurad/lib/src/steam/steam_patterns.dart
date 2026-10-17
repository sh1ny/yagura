// ignore_for_file: prefer_initializing_formals
import 'package:yaml/yaml.dart';

import 'patterns.g.dart';

/// One progress report parsed from a SteamCMD line.
class SteamProgress {
  const SteamProgress({
    required this.step,
    required this.percent,
    required this.bytesDone,
    required this.bytesTotal,
  });

  /// `download`, `verify` or `commit`.
  final String step;
  final double percent;
  final int bytesDone;
  final int bytesTotal;

  @override
  String toString() => '$step $percent% ($bytesDone/$bytesTotal)';
}

/// A recognised failure.
class SteamFailure {
  const SteamFailure(
    this.id,
    this.reason,
    this.message, {
    this.retryOnce = false,
  });

  final String id;
  final String reason;
  final String message;

  /// The same SteamCMD command runs once more before this is reported.
  final bool retryOnce;
}

class _FailurePattern {
  _FailurePattern(
    this.id,
    this.reason,
    this.match,
    this.message, {
    this.retryOnce = false,
  });

  final String id;
  final String reason;
  final RegExp match;
  final String message;
  final bool retryOnce;
}

/// The versioned pattern table (`steam/patterns.yaml`, ADR 0010): which lines
/// start a step, report progress, mean success or name a known failure.
class SteamPatterns {
  SteamPatterns._({
    required this.version,
    required List<(String, RegExp)> steps,
    required RegExp progress,
    required List<(RegExp, String)> states,
    required RegExp success,
    required List<_FailurePattern> failures,
  }) : _steps = steps,
       _progress = progress,
       _states = states,
       _success = success,
       _failures = failures;

  /// The table embedded in the daemon.
  factory SteamPatterns.embedded() => SteamPatterns.parse(steamPatternsYaml);

  factory SteamPatterns.parse(String source) {
    final root = loadYaml(source) as YamlMap;
    final progress = root['progress'] as YamlMap;
    return SteamPatterns._(
      version: root['version'] as int,
      steps: [
        for (final step in root['steps'] as YamlList)
          (
            (step as YamlMap)['step'] as String,
            RegExp(step['match'] as String),
          ),
      ],
      progress: RegExp(progress['match'] as String),
      states: [
        for (final state in progress['states'] as YamlList)
          (
            RegExp((state as YamlMap)['match'] as String),
            state['step'] as String,
          ),
      ],
      success: RegExp(root['success'] as String),
      failures: [
        for (final failure in root['failures'] as YamlList)
          _FailurePattern(
            (failure as YamlMap)['id'] as String,
            failure['reason'] as String,
            RegExp(failure['match'] as String),
            failure['message'] as String,
            retryOnce: switch (failure['retry']) {
              null => false,
              'once' => true,
              final other => throw FormatException(
                'failure ${failure['id']}: retry must be "once", not $other',
              ),
            },
          ),
      ],
    );
  }

  final int version;
  final List<(String, RegExp)> _steps;
  final RegExp _progress;
  final List<(RegExp, String)> _states;
  final RegExp _success;
  final List<_FailurePattern> _failures;

  /// The step [line] starts, if any.
  String? stepFor(String line) {
    for (final (step, match) in _steps) {
      if (match.hasMatch(line)) return step;
    }
    return null;
  }

  /// The progress [line] reports, if it is a progress line.
  SteamProgress? progressFor(String line) {
    final match = _progress.firstMatch(line);
    if (match == null) return null;
    final state = match.namedGroup('state')!.toLowerCase();
    final step = _states.firstWhere((s) => s.$1.hasMatch(state)).$2;
    return SteamProgress(
      step: step,
      percent: double.parse(match.namedGroup('percent')!),
      bytesDone: int.parse(match.namedGroup('done')!),
      bytesTotal: int.parse(match.namedGroup('total')!),
    );
  }

  bool isSuccess(String line) => _success.hasMatch(line);

  /// The known failure in [lines], or null when none matches.
  SteamFailure? classify(Iterable<String> lines, {required int appId}) {
    for (final line in lines) {
      for (final failure in _failures) {
        if (failure.match.hasMatch(line)) {
          return SteamFailure(
            failure.id,
            failure.reason,
            failure.message.replaceAll('{app_id}', '$appId'),
            retryOnce: failure.retryOnce,
          );
        }
      }
    }
    return null;
  }
}
