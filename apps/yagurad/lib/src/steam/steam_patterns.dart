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

/// What a login run came to (the `kind` of `login.outcomes` in the table).
enum LoginKind {
  reauthNeeded('reauth_needed'),
  rateLimited('rate_limited'),
  guardInvalid('guard_invalid'),
  loginInvalid('login_invalid'),
  ok('ok'),
  guardEmail('guard_email'),
  guardAuthenticator('guard_authenticator'),
  guardMobile('guard_mobile');

  const LoginKind(this.wire);

  final String wire;

  static LoginKind fromWire(String wire) => values.firstWhere(
    (k) => k.wire == wire,
    orElse: () => throw FormatException('unknown login outcome kind: $wire'),
  );
}

/// The outcome of a login run read from its output. [reason] and [message]
/// are set for the outcomes that fail the run.
class LoginOutcome {
  const LoginOutcome(this.kind, {this.reason, this.message});

  final LoginKind kind;
  final String? reason;
  final String? message;

  /// Whether Steam asks for a code or an approval.
  bool get isGuard =>
      kind == LoginKind.guardEmail ||
      kind == LoginKind.guardAuthenticator ||
      kind == LoginKind.guardMobile;
}

class _LoginPattern {
  _LoginPattern(this.kind, this.match, this.reason, this.message);

  final LoginKind kind;
  final RegExp match;
  final String? reason;
  final String? message;
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

class _WorkshopReason {
  _WorkshopReason(this.why, this.reason, this.message);

  final RegExp why;
  final String reason;
  final String message;
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
    required List<_LoginPattern> loginOutcomes,
    required this.connectionLog,
    required RegExp liveGuardMobile,
    required RegExp workshopStarted,
    required RegExp workshopDownloaded,
    required RegExp workshopFailed,
    required List<_WorkshopReason> workshopReasons,
  }) : _steps = steps,
       _progress = progress,
       _states = states,
       _success = success,
       _failures = failures,
       _loginOutcomes = loginOutcomes,
       _liveGuardMobile = liveGuardMobile,
       _workshopStarted = workshopStarted,
       _workshopDownloaded = workshopDownloaded,
       _workshopFailed = workshopFailed,
       _workshopReasons = workshopReasons;

  /// The table embedded in the daemon.
  factory SteamPatterns.embedded() => SteamPatterns.parse(steamPatternsYaml);

  factory SteamPatterns.parse(String source) {
    final root = loadYaml(source) as YamlMap;
    final progress = root['progress'] as YamlMap;
    final login = root['login'] as YamlMap;
    final live = login['live'] as YamlMap;
    final workshop = root['workshop'] as YamlMap;
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
      loginOutcomes: [
        for (final outcome in login['outcomes'] as YamlList)
          _LoginPattern(
            LoginKind.fromWire((outcome as YamlMap)['kind'] as String),
            RegExp(outcome['match'] as String),
            outcome['reason'] as String?,
            outcome['message'] as String?,
          ),
      ],
      connectionLog: live['connection_log'] as String,
      liveGuardMobile: RegExp(live['guard_mobile'] as String),
      workshopStarted: RegExp(workshop['started'] as String),
      workshopDownloaded: RegExp(workshop['downloaded'] as String),
      workshopFailed: RegExp(workshop['failed'] as String),
      workshopReasons: [
        for (final reason in workshop['reasons'] as YamlList)
          _WorkshopReason(
            RegExp((reason as YamlMap)['why'] as String),
            reason['reason'] as String,
            reason['message'] as String,
          ),
      ],
    );
  }

  final int version;

  /// The installation's log (below its directory) that shows a mobile
  /// approval being waited for while the run lives.
  final String connectionLog;
  final List<_LoginPattern> _loginOutcomes;
  final RegExp _liveGuardMobile;
  final RegExp _workshopStarted;
  final RegExp _workshopDownloaded;
  final RegExp _workshopFailed;
  final List<_WorkshopReason> _workshopReasons;
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

  /// What the output of a login run [lines] came to: the outcomes are tried
  /// in the order of the table, and the first that any line matches wins.
  /// Null when none matches.
  LoginOutcome? classifyLogin(Iterable<String> lines) {
    final all = lines.toList();
    for (final outcome in _loginOutcomes) {
      if (all.any(outcome.match.hasMatch)) {
        return LoginOutcome(
          outcome.kind,
          reason: outcome.reason,
          message: outcome.message,
        );
      }
    }
    return null;
  }

  /// Whether [line] of the connection log says a mobile approval is waited
  /// for.
  bool isLiveGuardMobile(String line) => _liveGuardMobile.hasMatch(line);

  /// What [line] says about a workshop item, if anything.
  WorkshopLine? workshopLine(String line) {
    if (_workshopFailed.firstMatch(line) case final match?) {
      final item = match.namedGroup('item')!;
      final why = match.namedGroup('why')!;
      for (final reason in _workshopReasons) {
        if (reason.why.hasMatch(why)) {
          return WorkshopFailed(
            item,
            reason.reason,
            reason.message.replaceAll('{item}', item).replaceAll('{why}', why),
          );
        }
      }
      return WorkshopFailed(
        item,
        'steam_unknown_error',
        'SteamCMD could not download the workshop item $item (SteamCMD: $why).',
      );
    }
    if (_workshopDownloaded.firstMatch(line) case final match?) {
      return WorkshopDownloaded(match.namedGroup('item')!);
    }
    if (_workshopStarted.firstMatch(line) case final match?) {
      return WorkshopStarted(match.namedGroup('item')!);
    }
    return null;
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

/// A line of a workshop download run (design D5).
sealed class WorkshopLine {
  const WorkshopLine(this.item);

  final String item;
}

/// SteamCMD began downloading [item].
class WorkshopStarted extends WorkshopLine {
  const WorkshopStarted(super.item);
}

/// SteamCMD downloaded [item].
class WorkshopDownloaded extends WorkshopLine {
  const WorkshopDownloaded(super.item);
}

/// SteamCMD failed to download [item].
class WorkshopFailed extends WorkshopLine {
  const WorkshopFailed(super.item, this.reason, this.message);

  final String reason;
  final String message;
}
