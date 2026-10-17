/// Lifecycle status of an operation (mirrors `OperationStatus` in
/// `operations.proto`).
enum OperationStatus {
  queued('queued'),
  running('running'),
  waitingForInput('waiting_for_input'),
  succeeded('succeeded'),
  failed('failed'),
  cancelled('cancelled'),
  interrupted('interrupted');

  const OperationStatus(this.wireName);

  final String wireName;

  bool get isTerminal => switch (this) {
    succeeded || failed || cancelled || interrupted => true,
    _ => false,
  };

  static OperationStatus fromWire(String name) =>
      values.firstWhere((s) => s.wireName == name);
}

/// What an operation does (the `kind` strings of `operations.proto`).
enum OperationKind {
  install(heavy: true),
  update(heavy: true),
  validate(heavy: true),
  start(heavy: false),
  stop(heavy: false),
  restart(heavy: false),
  delete(heavy: false),
  restore(heavy: false);

  const OperationKind({required this.heavy});

  /// Heavy operations take a host heavy slot around their SteamCMD work
  /// (design D3).
  final bool heavy;

  String get wireName => name;

  static OperationKind fromWire(String name) =>
      values.firstWhere((k) => k.name == name);
}

/// An immutable view of an operation.
class Operation {
  const Operation({
    required this.id,
    required this.instanceId,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.queuePosition = 0,
    this.currentStep = '',
    this.startedAt,
    this.endedAt,
    this.resultReason = '',
    this.resultMessage = '',
    this.warnings = const [],
    this.lastSequence = 0,
  });

  final String id;
  final String instanceId;
  final OperationKind kind;
  final OperationStatus status;

  /// 1-based position among the instance's queued operations; 0 once running
  /// or finished.
  final int queuePosition;
  final String currentStep;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// The failure reason, or `stopped_by:graceful|kill` for a stop.
  final String resultReason;
  final String resultMessage;
  final List<String> warnings;
  final int lastSequence;

  @override
  String toString() => 'Operation($id ${kind.name} ${status.wireName})';
}

/// One event of an operation's stream. [sequence] is per operation and
/// strictly increasing.
sealed class OperationEvent {
  const OperationEvent(this.sequence, this.at);

  final int sequence;
  final DateTime at;
}

class StepStartedEvent extends OperationEvent {
  const StepStartedEvent(super.sequence, super.at, this.step);
  final String step;
}

class ProgressEvent extends OperationEvent {
  const ProgressEvent(
    super.sequence,
    super.at,
    this.step, {
    this.percent = -1,
    this.bytesDone = 0,
    this.bytesTotal = 0,
  });

  final String step;

  /// 0-100, or -1 when unknown.
  final double percent;
  final int bytesDone;
  final int bytesTotal;
}

class LogEvent extends OperationEvent {
  const LogEvent(super.sequence, super.at, this.text);
  final String text;
}

/// Terminal event; the stream ends after it.
class FinishedEvent extends OperationEvent {
  const FinishedEvent(super.sequence, super.at, this.operation);
  final Operation operation;
}

/// First message of a resume below the retained window (design D3).
class EventsDroppedEvent extends OperationEvent {
  const EventsDroppedEvent(
    super.sequence,
    super.at,
    this.fromSequence,
    this.toSequence,
  );

  final int fromSequence;
  final int toSequence;
}

/// Follows [EventsDroppedEvent] with the current operation.
class SnapshotEvent extends OperationEvent {
  const SnapshotEvent(super.sequence, super.at, this.operation);
  final Operation operation;
}
