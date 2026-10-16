import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import '../errors.dart';
import '../host/database.dart';
import 'cancel_token.dart';
import 'operation.dart';
import 'semaphore.dart';

/// What a step of an operation sees.
abstract interface class OperationContext {
  String get operationId;
  String get instanceId;
  CancelToken get cancel;

  /// Starts step [name] (throwing [OperationCancelled] first when the
  /// operation was cancelled) and runs [body].
  Future<T> step<T>(String name, Future<T> Function() body);

  /// Marks the start of step [name] without wrapping a body, for work that
  /// reports its own steps (SteamCMD).
  void beginStep(String name);

  /// Runs [body] holding the SteamCMD installation lock of [installation],
  /// then a heavy slot (design D3). While waiting, the operation reports step
  /// `waiting_for_steamcmd` with its position.
  Future<T> heavy<T>(
    Future<T> Function() body, {
    String installation = 'anonymous',
  });

  /// Progress of [step]; [percent] is 0-100 or -1 when unknown. Only the
  /// latest per step is retained.
  void progress(
    String step, {
    double percent = -1,
    int bytesDone = 0,
    int bytesTotal = 0,
  });

  void log(String text);
  void warn(String warning);

  /// Sets the reason and message a succeeded operation reports.
  void result({String reason = '', String message = ''});
}

typedef OperationBody = Future<void> Function(OperationContext context);

/// Thrown into a body that continues after the runner was closed (a killed
/// daemon): nothing more may run or be recorded.
class _RunnerClosed implements Exception {
  const _RunnerClosed();
}

class _Op {
  _Op({
    required this.id,
    required this.instanceId,
    required this.kind,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String instanceId;
  final OperationKind kind;
  final OperationBody body;
  final DateTime createdAt;
  final cancel = CancelToken();
  final done = Completer<Operation>();
  final listeners = <StreamController<OperationEvent>>[];
  final events = <OperationEvent>[];

  var status = OperationStatus.queued;
  var step = '';
  var waitPosition = 0;
  DateTime? startedAt;
  DateTime? endedAt;
  var reason = '';
  var message = '';
  final warnings = <String>[];
  var sequence = 0;

  /// Highest sequence number removed from [events] to stay in the bound.
  var droppedUpTo = 0;
}

/// Runs operations (design D3, D18): a per-instance FIFO (10 queued at most),
/// heavy slots, step events with sequence numbers, cancellation, and the
/// persisted rows that survive a restart.
class OperationRunner {
  OperationRunner({
    required this.database,
    this.heavySlots = 4,
    this.maxQueued = 10,
    this.maxRetainedEvents = 2000,
    this.historyPerInstance = 1000,
    this.historyAge = const Duration(days: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _slots = Semaphore(heavySlots);

  final YaguraDatabase database;
  final int heavySlots;
  final int maxQueued;

  /// Non-progress events kept per operation.
  final int maxRetainedEvents;
  final int historyPerInstance;
  final Duration historyAge;
  final DateTime Function() _clock;

  final Semaphore _slots;
  final _installationLocks = <String, Semaphore>{};
  final _ops = <String, _Op>{};
  final _queues = <String, Queue<_Op>>{};
  final _running = <String, _Op>{};
  final _history = <String, Queue<String>>{};
  var _closed = false;

  // ---- requests ----------------------------------------------------------

  /// Queues an operation on [instanceId] and returns its view. A stop first
  /// cancels the queued Start and Restart operations of the instance and the
  /// running Start, and runs next; it does not cancel queued Install or
  /// Update. Throws `queue_full` at the bound.
  Operation enqueue({
    required String instanceId,
    required OperationKind kind,
    required OperationBody body,
  }) {
    if (_closed) {
      throw YaguraException('internal_error', 'the daemon is shutting down');
    }
    if (kind == OperationKind.stop) _cancelForStop(instanceId);
    final queue = _queues.putIfAbsent(instanceId, Queue.new);
    if (queue.length >= maxQueued) {
      throw YaguraException(
        'queue_full',
        'instance $instanceId already has $maxQueued queued operations',
        details: {'instanceId': instanceId, 'limit': maxQueued},
      );
    }
    final op = _Op(
      id: _newId(),
      instanceId: instanceId,
      kind: kind,
      body: body,
      createdAt: _clock(),
    );
    _ops[op.id] = op;
    if (kind == OperationKind.stop) {
      queue.addFirst(op);
    } else {
      queue.addLast(op);
    }
    _persist(op);
    _startNext(instanceId);
    return _view(op);
  }

  /// The operation, from this process or the database.
  Operation? get(String operationId) {
    final op = _ops[operationId];
    if (op != null) return _view(op);
    final rows = database.sqlite.select(
      'SELECT * FROM operations WHERE id = ?',
      [operationId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Every operation of the instance, oldest first.
  List<Operation> listForInstance(String instanceId) {
    final rows = database.sqlite.select(
      'SELECT * FROM operations WHERE instance_id = ? '
      'ORDER BY created_at, rowid',
      [instanceId],
    );
    return [
      for (final row in rows)
        if (_ops[row['id'] as String] case final op?)
          _view(op)
        else
          _fromRow(row),
    ];
  }

  /// Cancels a queued operation at once, or asks a running one to stop at its
  /// next step boundary (interruptible waits stop sooner).
  Operation cancel(String operationId) {
    final op = _ops[operationId];
    if (op == null) {
      final known = get(operationId);
      if (known == null) {
        throw YaguraException(
          'operation_not_found',
          'there is no operation $operationId',
        );
      }
      return known;
    }
    switch (op.status) {
      case OperationStatus.queued:
        _queues[op.instanceId]?.remove(op);
        _finish(
          op,
          OperationStatus.cancelled,
          message: 'cancelled while queued',
        );
      case OperationStatus.running || OperationStatus.waitingForInput:
        op.cancel.cancel();
      default:
        break;
    }
    return _view(op);
  }

  /// Completes with the final state once the operation ended.
  Future<Operation> whenDone(String operationId) {
    final op = _ops[operationId];
    if (op != null) return op.done.future;
    final known = get(operationId);
    if (known == null) {
      return Future.error(
        YaguraException(
          'operation_not_found',
          'there is no operation $operationId',
        ),
      );
    }
    return Future.value(known);
  }

  /// Events of [operationId] after [afterSequence], then live events until the
  /// terminal event, which ends the stream.
  ///
  /// The replay holds every retained non-progress event and the latest
  /// progress of each step. A resume below the retained window starts with
  /// [EventsDroppedEvent] and the current operation (design D3).
  Stream<OperationEvent> watch(String operationId, {int afterSequence = 0}) {
    final controller = StreamController<OperationEvent>();
    final op = _ops[operationId];
    if (op == null) {
      final known = get(operationId);
      if (known == null) {
        throw YaguraException(
          'operation_not_found',
          'there is no operation $operationId',
        );
      }
      // From an earlier daemon run: only the outcome is left.
      controller
        ..add(
          FinishedEvent(known.lastSequence, known.endedAt ?? _clock(), known),
        )
        ..close();
      return controller.stream;
    }
    if (afterSequence < op.droppedUpTo) {
      controller
        ..add(
          EventsDroppedEvent(
            op.droppedUpTo,
            _clock(),
            afterSequence + 1,
            op.droppedUpTo,
          ),
        )
        ..add(SnapshotEvent(op.sequence, _clock(), _view(op)));
    }
    for (final event in op.events) {
      if (event.sequence > afterSequence && event.sequence > op.droppedUpTo) {
        controller.add(event);
      }
    }
    if (op.status.isTerminal) {
      controller.close();
    } else {
      op.listeners.add(controller);
      controller.onCancel = () => op.listeners.remove(controller);
    }
    return controller.stream;
  }

  // ---- queries ------------------------------------------------------------

  /// Whether the instance has a running or queued operation.
  bool hasActive(String instanceId) =>
      _running.containsKey(instanceId) ||
      (_queues[instanceId]?.isNotEmpty ?? false);

  int queuedCount(String instanceId) => _queues[instanceId]?.length ?? 0;

  /// The running operation of the instance, if any.
  String? activeOperationId(String instanceId) => _running[instanceId]?.id;

  /// The kind of the running operation, if any.
  OperationKind? runningKind(String instanceId) => _running[instanceId]?.kind;

  // ---- recovery -----------------------------------------------------------

  /// Marks every operation left `queued` or `running` by a previous daemon as
  /// `interrupted` and returns them (design D9).
  List<Operation> recoverInterrupted() {
    final rows = database.sqlite.select(
      "SELECT * FROM operations WHERE status IN ('queued', 'running', "
      "'waiting_for_input') ORDER BY created_at, rowid",
    );
    final now = _clock().millisecondsSinceEpoch;
    database.sqlite.execute(
      "UPDATE operations SET status = 'interrupted', ended_at = ?, "
      "result_reason = 'interrupted', "
      "result_message = 'the daemon stopped while the operation was unfinished' "
      "WHERE status IN ('queued', 'running', 'waiting_for_input')",
      [now],
    );
    return [
      for (final row in rows)
        _fromRow(
          database.sqlite.select('SELECT * FROM operations WHERE id = ?', [
            row['id'],
          ]).first,
        ),
    ];
  }

  /// Deletes finished operations older than [historyAge] or beyond
  /// [historyPerInstance] per instance (the oldest first).
  void pruneHistory() {
    final cutoff = _clock().subtract(historyAge).millisecondsSinceEpoch;
    database.sqlite.execute(
      "DELETE FROM operations WHERE status NOT IN ('queued', 'running', "
      "'waiting_for_input') AND ended_at IS NOT NULL AND ended_at < ?",
      [cutoff],
    );
    database.sqlite.execute(
      "DELETE FROM operations WHERE status NOT IN ('queued', 'running', "
      "'waiting_for_input') AND id IN ("
      'SELECT id FROM operations o WHERE ('
      'SELECT COUNT(*) FROM operations n WHERE n.instance_id = o.instance_id '
      'AND (n.created_at > o.created_at OR '
      '(n.created_at = o.created_at AND n.rowid > o.rowid))) >= ?)',
      [historyPerInstance],
    );
  }

  /// Stops recording: what is unfinished stays unfinished in the database,
  /// as after a killed daemon, and bodies that keep running are stopped at
  /// their next step.
  Future<void> close() async {
    _closed = true;
    for (final op in _ops.values) {
      for (final listener in List.of(op.listeners)) {
        await listener.close();
      }
      op.listeners.clear();
    }
  }

  // ---- internals ----------------------------------------------------------

  void _cancelForStop(String instanceId) {
    final queue = _queues[instanceId];
    if (queue != null) {
      for (final op in queue.toList()) {
        if (op.kind == OperationKind.start ||
            op.kind == OperationKind.restart) {
          queue.remove(op);
          _finish(
            op,
            OperationStatus.cancelled,
            message: 'cancelled by a stop request',
          );
        }
      }
    }
    final running = _running[instanceId];
    if (running != null && running.kind == OperationKind.start) {
      running.cancel.cancel();
    }
  }

  /// Promotes the head of the queue when the instance is idle. The body runs
  /// on a later event-loop turn, so a caller can watch the operation from its
  /// first event.
  void _startNext(String instanceId) {
    if (_running.containsKey(instanceId)) return;
    final queue = _queues[instanceId];
    if (queue == null || queue.isEmpty) return;
    final op = queue.removeFirst();
    _running[instanceId] = op;
    op
      ..status = OperationStatus.running
      ..startedAt = _clock();
    _persist(op);
    Timer.run(() => _execute(op));
  }

  Future<void> _execute(_Op op) async {
    var status = OperationStatus.succeeded;
    String? reason;
    String? message;
    try {
      if (op.cancel.isCancelled) throw const OperationCancelled();
      await op.body(_Context(this, op));
    } on OperationCancelled {
      status = OperationStatus.cancelled;
      reason = '';
      message = 'cancelled';
    } on _RunnerClosed {
      return;
    } on YaguraException catch (e) {
      status = OperationStatus.failed;
      reason = e.reason;
      message = e.message;
    } on Object catch (e) {
      if (_closed) return;
      status = OperationStatus.failed;
      reason = 'internal_error';
      message = '$e';
    }
    if (_closed) return;
    _finish(op, status, reason: reason, message: message);
  }

  void _finish(
    _Op op,
    OperationStatus status, {
    String? reason,
    String? message,
  }) {
    if (op.status.isTerminal) return;
    op
      ..status = status
      ..endedAt = _clock()
      ..reason = reason ?? op.reason
      ..message = message ?? op.message
      ..step = ''
      ..waitPosition = 0;
    _emit(op, (sequence, at) => FinishedEvent(sequence, at, _view(op)));
    _persist(op);
    if (_running[op.instanceId] == op) _running.remove(op.instanceId);
    for (final listener in List.of(op.listeners)) {
      unawaited(listener.close());
    }
    op.listeners.clear();
    if (!op.done.isCompleted) op.done.complete(_view(op));
    _remember(op);
    _startNext(op.instanceId);
  }

  /// Keeps the finished operations of an instance in memory up to the history
  /// bound.
  void _remember(_Op op) {
    final history = _history.putIfAbsent(op.instanceId, Queue.new)
      ..addLast(op.id);
    while (history.length > historyPerInstance) {
      _ops.remove(history.removeFirst());
    }
  }

  void _emit(_Op op, OperationEvent Function(int sequence, DateTime at) build) {
    final event = build(++op.sequence, _clock());
    if (event is ProgressEvent) {
      op.events.removeWhere((e) => e is ProgressEvent && e.step == event.step);
    }
    op.events.add(event);
    var nonProgress = op.events.where((e) => e is! ProgressEvent).length;
    for (var i = 0; nonProgress > maxRetainedEvents && i < op.events.length;) {
      if (op.events[i] is ProgressEvent) {
        i++;
        continue;
      }
      op.droppedUpTo = max(op.droppedUpTo, op.events[i].sequence);
      op.events.removeAt(i);
      nonProgress--;
    }
    for (final listener in op.listeners) {
      listener.add(event);
    }
  }

  Semaphore _lockFor(String installation) =>
      _installationLocks.putIfAbsent(installation, () => Semaphore(1));

  Operation _view(_Op op) {
    var position = 0;
    if (op.status == OperationStatus.queued) {
      position = (_queues[op.instanceId]?.toList().indexOf(op) ?? -1) + 1;
    } else if (op.status == OperationStatus.running &&
        op.step == 'waiting_for_steamcmd') {
      position = op.waitPosition;
    }
    return Operation(
      id: op.id,
      instanceId: op.instanceId,
      kind: op.kind,
      status: op.status,
      queuePosition: position,
      currentStep: op.step,
      createdAt: op.createdAt,
      startedAt: op.startedAt,
      endedAt: op.endedAt,
      resultReason: op.reason,
      resultMessage: op.message,
      warnings: List.unmodifiable(op.warnings),
      lastSequence: op.sequence,
    );
  }

  Operation _fromRow(Map<String, Object?> row) => Operation(
    id: row['id']! as String,
    instanceId: row['instance_id']! as String,
    kind: OperationKind.fromWire(row['kind']! as String),
    status: OperationStatus.fromWire(row['status']! as String),
    currentStep: row['current_step']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    startedAt: _time(row['started_at']),
    endedAt: _time(row['ended_at']),
    resultReason: row['result_reason']! as String,
    resultMessage: row['result_message']! as String,
    warnings: [
      for (final w in jsonDecode(row['warnings_json']! as String) as List)
        w as String,
    ],
    lastSequence: row['last_sequence']! as int,
  );

  static DateTime? _time(Object? millis) => millis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis as int);

  void _persist(_Op op) {
    if (_closed) return;
    database.sqlite.execute(
      'INSERT OR REPLACE INTO operations (id, instance_id, kind, status, '
      'current_step, created_at, started_at, ended_at, result_reason, '
      'result_message, warnings_json, last_sequence) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        op.id,
        op.instanceId,
        op.kind.wireName,
        op.status.wireName,
        op.step,
        op.createdAt.millisecondsSinceEpoch,
        op.startedAt?.millisecondsSinceEpoch,
        op.endedAt?.millisecondsSinceEpoch,
        op.reason,
        op.message,
        jsonEncode(op.warnings),
        op.sequence,
      ],
    );
  }

  static final _random = Random.secure();

  static String _newId() => [
    'op',
    for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
  ].join();
}

class _Context implements OperationContext {
  _Context(this._runner, this._op);

  final OperationRunner _runner;
  final _Op _op;

  @override
  String get operationId => _op.id;

  @override
  String get instanceId => _op.instanceId;

  @override
  CancelToken get cancel => _op.cancel;

  void _checkOpen() {
    if (_runner._closed) throw const _RunnerClosed();
  }

  @override
  Future<T> step<T>(String name, Future<T> Function() body) {
    _checkOpen();
    cancel.throwIfCancelled();
    beginStep(name);
    return body();
  }

  @override
  void beginStep(String name) {
    _checkOpen();
    _op.step = name;
    _runner._emit(_op, (sequence, at) => StepStartedEvent(sequence, at, name));
  }

  @override
  Future<T> heavy<T>(
    Future<T> Function() body, {
    String installation = 'anonymous',
  }) async {
    _checkOpen();
    cancel.throwIfCancelled();
    final before = _op.step;
    var waiting = false;
    void onPosition(int position) {
      _op.waitPosition = position;
      if (!waiting) {
        waiting = true;
        beginStep('waiting_for_steamcmd');
      }
    }

    final releaseLock = await _runner
        ._lockFor(installation)
        .acquire(cancel: cancel, onPosition: onPosition);
    try {
      final releaseSlot = await _runner._slots.acquire(
        cancel: cancel,
        onPosition: onPosition,
      );
      try {
        if (waiting) _op.step = before;
        _checkOpen();
        cancel.throwIfCancelled();
        return await body();
      } finally {
        releaseSlot();
      }
    } finally {
      releaseLock();
    }
  }

  @override
  void progress(
    String step, {
    double percent = -1,
    int bytesDone = 0,
    int bytesTotal = 0,
  }) {
    _checkOpen();
    _runner._emit(
      _op,
      (sequence, at) => ProgressEvent(
        sequence,
        at,
        step,
        percent: percent,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      ),
    );
  }

  @override
  void log(String text) {
    _checkOpen();
    _runner._emit(_op, (sequence, at) => LogEvent(sequence, at, text));
  }

  @override
  void warn(String warning) => _op.warnings.add(warning);

  @override
  void result({String reason = '', String message = ''}) {
    _op
      ..reason = reason
      ..message = message;
  }
}
