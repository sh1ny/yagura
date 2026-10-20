import 'dart:async';
import 'dart:math';

import '../errors.dart';

/// How a prompt ended (the `outcome` of `PromptResolved`).
enum PromptOutcome {
  /// A client answered it, or the work that raised it no longer needs an
  /// answer (a mobile approval that came through).
  answered,

  /// Nobody answered in time.
  expired,

  /// The operation that raised it ended or was cancelled first.
  cancelled,
}

/// What an operation asks of the administrator (design D13).
class PromptSpec {
  const PromptSpec({
    required this.kind,
    required this.message,
    required this.steamAccount,
    required this.wait,
    this.acceptsAnswer = true,
  });

  /// `email`, `authenticator` or `mobile_approval`.
  final String kind;
  final String message;

  /// The Steam username the prompt is about.
  final String steamAccount;

  /// How long the prompt waits before it expires.
  final Duration wait;

  /// Whether a client answers it with a code; a mobile approval is given on
  /// the phone and takes no answer.
  final bool acceptsAnswer;
}

/// A raised prompt.
class Prompt {
  const Prompt({
    required this.id,
    required this.kind,
    required this.message,
    required this.steamAccount,
    required this.expiresAt,
    required this.acceptsAnswer,
  });

  final String id;
  final String kind;
  final String message;
  final String steamAccount;
  final DateTime expiresAt;
  final bool acceptsAnswer;
}

/// An operation waiting on a prompt.
class PromptSubject {
  const PromptSubject({
    required this.operationId,
    this.instanceId = '',
    this.accountId = '',
  });

  final String operationId;

  /// Empty for an account operation.
  final String instanceId;

  /// Empty for an instance operation.
  final String accountId;
}

/// A prompt and the operations waiting on it.
class PendingPrompt {
  const PendingPrompt(this.prompt, this.subjects);

  final Prompt prompt;
  final List<PromptSubject> subjects;
}

/// How a prompt ended and, when answered, with what and by whom.
class PromptResult {
  const PromptResult(this.outcome, {this.value = '', this.byDeviceId = ''});

  final PromptOutcome outcome;

  /// The answer; empty unless a client answered.
  final String value;

  /// The device that answered; empty for any other outcome, and in dev mode.
  final String byDeviceId;
}

/// What the work that raised a prompt holds: the prompt, how it ended, and a
/// way to end it from the work's side.
abstract interface class PromptTicket {
  Prompt get prompt;

  /// Completes once, when the prompt is resolved.
  Future<PromptResult> get result;

  /// Resolves the prompt as [outcome] unless it already is (a mobile approval
  /// the run no longer waits for).
  void close(PromptOutcome outcome);
}

/// A change in the pending prompts of the daemon.
sealed class PromptBrokerEvent {
  const PromptBrokerEvent();
}

class PromptRaised extends PromptBrokerEvent {
  const PromptRaised(this.pending);
  final PendingPrompt pending;
}

class PromptResolved extends PromptBrokerEvent {
  const PromptResolved(this.promptId, this.byDeviceId, this.outcome);
  final String promptId;
  final String byDeviceId;
  final PromptOutcome outcome;
}

/// The pending prompts of the daemon (design D13): raised by operations,
/// answered once by whichever client is first, and expired by the clock.
///
/// One broker serves the daemon. Answers are compare-and-set: the first
/// resolves the prompt and every later one is refused `prompt_resolved`.
class PromptBroker {
  PromptBroker({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _entries = <String, _Entry>{};
  final _events = StreamController<PromptBrokerEvent>.broadcast(sync: true);
  var _closed = false;

  /// Longest answer to a code prompt.
  static const maxAnswerLength = 16;
  static final _answer = RegExp(r'^[A-Za-z0-9]{1,16}$');

  static final _random = Random.secure();

  /// Raised and resolved prompts, as they happen.
  Stream<PromptBrokerEvent> get events => _events.stream;

  /// Every pending prompt, oldest first.
  List<PendingPrompt> snapshot() => [
    for (final entry in _entries.values) entry.pending,
  ];

  /// The pending prompt of [operationId], if any.
  Prompt? pendingFor(String operationId) {
    for (final entry in _entries.values) {
      if (entry.subjects.any((s) => s.operationId == operationId)) {
        return entry.prompt;
      }
    }
    return null;
  }

  /// Raises a prompt for [subject]. [onResolved] runs synchronously when the
  /// prompt is resolved, before anything waiting on the ticket continues.
  PromptTicket raise(
    PromptSpec spec,
    PromptSubject subject, {
    void Function(Prompt prompt, PromptResult result)? onResolved,
  }) {
    final prompt = Prompt(
      id: [
        'pr',
        for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
      ].join(),
      kind: spec.kind,
      message: spec.message,
      steamAccount: spec.steamAccount,
      expiresAt: _clock().add(spec.wait),
      acceptsAnswer: spec.acceptsAnswer,
    );
    final entry = _Entry(this, prompt, [subject], onResolved);
    entry.timer = Timer(
      spec.wait,
      () => _resolve(entry, PromptOutcome.expired),
    );
    _entries[prompt.id] = entry;
    _events.add(PromptRaised(entry.pending));
    return entry;
  }

  /// Answers [promptId] of [operationId] with [value] on behalf of
  /// [byDeviceId]. A prompt that is not pending is `prompt_resolved`; a value
  /// that is not a Steam Guard code, or an answer to a prompt that takes none,
  /// is `prompt_answer_invalid` and leaves the prompt pending.
  void answer(
    String operationId,
    String promptId,
    String value,
    String byDeviceId,
  ) {
    final entry = _entries[promptId];
    if (entry == null ||
        !entry.subjects.any((s) => s.operationId == operationId)) {
      throw YaguraException(
        'prompt_resolved',
        'prompt $promptId of operation $operationId is not waiting for an '
            'answer any more',
        details: {'operationId': operationId, 'promptId': promptId},
      );
    }
    if (!entry.prompt.acceptsAnswer) {
      throw YaguraException(
        'prompt_answer_invalid',
        'a ${entry.prompt.kind} prompt takes no answer; confirm it on the '
            'phone',
        details: {'promptId': promptId},
      );
    }
    if (!_answer.hasMatch(value)) {
      throw YaguraException(
        'prompt_answer_invalid',
        'a Steam Guard code is 1 to $maxAnswerLength letters and digits',
        details: {'promptId': promptId, 'limit': maxAnswerLength},
      );
    }
    _resolve(entry, PromptOutcome.answered, value: value, by: byDeviceId);
  }

  /// Resolves the pending prompt of [operationId] as cancelled.
  void cancelOperation(String operationId) {
    for (final entry in _entries.values.toList()) {
      if (entry.subjects.any((s) => s.operationId == operationId)) {
        _resolve(entry, PromptOutcome.cancelled);
      }
    }
  }

  /// Stops the timers; nothing more is raised or resolved.
  void close() {
    _closed = true;
    for (final entry in _entries.values) {
      entry.timer?.cancel();
    }
    _entries.clear();
    unawaited(_events.close());
  }

  void _resolve(
    _Entry entry,
    PromptOutcome outcome, {
    String value = '',
    String by = '',
  }) {
    if (_closed || _entries.remove(entry.prompt.id) == null) return;
    entry.timer?.cancel();
    final result = PromptResult(outcome, value: value, byDeviceId: by);
    entry.onResolved?.call(entry.prompt, result);
    _events.add(PromptResolved(entry.prompt.id, by, outcome));
    entry.completer.complete(result);
  }
}

class _Entry implements PromptTicket {
  _Entry(this._broker, this.prompt, this.subjects, this.onResolved);

  final PromptBroker _broker;
  @override
  final Prompt prompt;
  final List<PromptSubject> subjects;
  final void Function(Prompt prompt, PromptResult result)? onResolved;
  final completer = Completer<PromptResult>();
  Timer? timer;

  PendingPrompt get pending =>
      PendingPrompt(prompt, List.unmodifiable(subjects));

  @override
  Future<PromptResult> get result => completer.future;

  @override
  void close(PromptOutcome outcome) => _broker._resolve(this, outcome);
}
