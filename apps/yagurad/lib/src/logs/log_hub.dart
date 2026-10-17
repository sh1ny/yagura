import 'dart:async';

import '../errors.dart';
import '../host/database.dart';
import 'line_assembler.dart';
import 'log_limits.dart';
import 'log_models.dart';
import 'log_offset_store.dart';
import 'log_ring.dart';
import 'source_tailer.dart';

/// Timing of the log hub: injectable so tests run fast (design D6).
class LogHubOptions {
  const LogHubOptions({
    this.pollFollowed = const Duration(milliseconds: 250),
    this.pollIdle = const Duration(seconds: 2),
    this.persistInterval = const Duration(seconds: 10),
    this.waitingAfter = const Duration(seconds: 60),
  });

  /// Tests that drive the hub with `pollNow` and fake time: nothing polls or
  /// persists by itself within a test's lifetime.
  const LogHubOptions.manual()
    : pollFollowed = const Duration(hours: 1),
      pollIdle = const Duration(hours: 1),
      persistInterval = const Duration(hours: 1),
      waitingAfter = const Duration(seconds: 60);

  /// Poll interval while a client follows the instance (or a start waits on
  /// its log).
  final Duration pollFollowed;

  /// Poll interval otherwise.
  final Duration pollIdle;

  /// How often offsets are saved.
  final Duration persistInterval;

  /// How long a source without a file may go before it reports `waiting`.
  final Duration waitingAfter;
}

/// The log hub: tails the declared sources of every instance, decodes,
/// ring-buffers and fans out (`openspec/architecture.md`, Components).
///
/// Lines of an instance get increasing sequence numbers across its sources.
/// `follow` and `backlog` carry what `Logs.Follow` and `Logs.Backlog` send
/// (`LogBatch`: lines, `dropped`, `truncated`, `source_event`); `markRun` and
/// `linesAfter` are what the start-time `log_match` health check uses.
class LogHub {
  LogHub({
    YaguraDatabase? database,
    DateTime Function()? clock,
    this.options = const LogHubOptions(),
  }) : _offsets = database == null ? null : LogOffsetStore(database),
       _clock = clock ?? DateTime.now {
    _persistTimer = Timer.periodic(options.persistInterval, (_) {
      persistOffsets();
    });
  }

  final LogHubOptions options;
  final LogOffsetStore? _offsets;
  final DateTime Function() _clock;
  late final Timer _persistTimer;
  final _instances = <String, _InstanceLogs>{};
  final _saved = <String, LogPosition>{};
  var _closed = false;

  // ---- sources -------------------------------------------------------------

  /// Starts tailing [sources] of [instanceId], refilling each ring from the
  /// file tail. Attaching an instance again keeps the sources that did not
  /// change and replaces or drops the others.
  Future<void> attach(String instanceId, List<LogSourceSpec> sources) {
    if (_closed) return Future<void>.value();
    final instance = _instances.putIfAbsent(
      instanceId,
      () => _InstanceLogs(instanceId),
    );
    final wanted = {for (final s in sources) s.name: s};
    for (final name in instance.tailers.keys.toList()) {
      final tailer = instance.tailers[name]!;
      if (wanted[name] != tailer.spec) {
        instance.tailers.remove(name);
        instance.rings.remove(name);
        _offsets?.forgetSource(instanceId, name);
        _saved.remove('$instanceId/$name');
      }
    }
    final starts = <Future<void>>[];
    for (final spec in sources) {
      if (instance.tailers.containsKey(spec.name)) continue;
      final ring = instance.rings[spec.name] = LogRing();
      final tailer = SourceTailer(
        spec: spec,
        sink: (source, line, {required history}) =>
            _line(instance, ring, spec, line, history: history),
        onEvent: (event) => _event(instance, event),
        clock: _clock,
        waitingAfter: options.waitingAfter,
      );
      instance.tailers[spec.name] = tailer;
      final saved = _offsets?.load(instanceId, spec.name);
      starts.add(tailer.start(saved).catchError((Object _) {}));
    }
    instance.ready = Future.wait<void>([instance.ready, ...starts])
        .then((_) {});
    _schedule(instance);
    return instance.ready;
  }

  /// Stops tailing [instanceId] and closes its followers; [forget] also drops
  /// the saved offsets (the instance was deleted).
  Future<void> detach(String instanceId, {bool forget = false}) async {
    final instance = _instances.remove(instanceId);
    if (instance == null) return;
    instance.timer?.cancel();
    await instance.ready;
    for (final tailer in instance.tailers.values) {
      await tailer.poll();
    }
    if (forget) {
      _offsets?.forgetInstance(instanceId);
      _saved.removeWhere((key, _) => key.startsWith('$instanceId/'));
    } else {
      _persist(instance);
    }
    for (final follower in instance.followers.toList()) {
      follower.close();
    }
  }

  /// The state of each source of [instanceId].
  List<LogSourceStatus> sources(String instanceId) => [
    for (final tailer in _require(instanceId).tailers.values) tailer.status,
  ];

  /// What the ring buffer of [source] holds.
  LogBufferStats bufferStats(String instanceId, String source) {
    final ring = _require(instanceId).rings[source];
    return LogBufferStats(lines: ring?.length ?? 0, bytes: ring?.bytes ?? 0);
  }

  _InstanceLogs _require(String instanceId) =>
      _instances[instanceId] ??
      (throw YaguraException(
        'instance_not_found',
        'there is no instance $instanceId',
        details: {'instanceId': instanceId},
      ));

  // ---- reading -------------------------------------------------------------

  /// Up to 5,000 recent lines of [sources] (all when empty), oldest first.
  /// A request for more than the cap, or for 0 lines (unset), gets the cap;
  /// above it the answer is marked `truncated`.
  LogBacklog backlog(
    String instanceId, {
    Set<String> sources = const {},
    int lines = 0,
  }) {
    final instance = _require(instanceId);
    final wanted = lines <= 0 || lines > backlogMaxLines
        ? backlogMaxLines
        : lines;
    final entries = <LogEntry>[
      for (final MapEntry(:key, :value) in instance.rings.entries)
        if (sources.isEmpty || sources.contains(key)) ...value.last(wanted),
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));
    final skip = entries.length > wanted ? entries.length - wanted : 0;
    return LogBacklog(
      entries.sublist(skip),
      truncated: lines > backlogMaxLines,
    );
  }

  /// New lines of [sources] (all when empty). A subscriber that falls more
  /// than 1,000 lines or 4 MiB behind (it is paused, or does not read) gets
  /// the newest lines and a batch whose `dropped` counts the lines it missed.
  /// Source events (`file_switched:<name>`, `waiting`, `error:<message>`) come
  /// in their own batches.
  Stream<LogBatch> follow(String instanceId, {Set<String> sources = const {}}) {
    final instance = _require(instanceId);
    late final _Follower follower;
    final controller = StreamController<LogBatch>(
      onListen: () {
        instance.followers.add(follower);
        _schedule(instance);
      },
      onResume: () => follower.flush(),
      onCancel: () {
        instance.followers.remove(follower);
        _schedule(instance);
      },
    );
    follower = _Follower(controller, sources);
    return controller.stream;
  }

  // ---- polling -------------------------------------------------------------

  /// Polls the sources of [instanceId] once, now, and waits for it.
  Future<void> pollNow(String instanceId) async {
    final instance = _require(instanceId);
    await instance.ready;
    await _pollInstance(instance);
  }

  Future<void> _pollInstance(_InstanceLogs instance) async {
    await Future.wait([for (final t in instance.tailers.values) t.poll()]);
    for (final follower in instance.followers.toList()) {
      follower.flush();
    }
  }

  void _schedule(_InstanceLogs instance) {
    if (_closed || !identical(_instances[instance.id], instance)) return;
    instance.timer?.cancel();
    final interval = instance.isFollowed
        ? options.pollFollowed
        : options.pollIdle;
    instance.timer = Timer(interval, () async {
      try {
        await instance.ready;
        await _pollInstance(instance);
      } on Object {
        // A tailer reports its own failures as a source status.
      }
      _schedule(instance);
    });
  }

  // ---- lines and events ----------------------------------------------------

  void _line(
    _InstanceLogs instance,
    LogRing ring,
    LogSourceSpec spec,
    AssembledLine line, {
    required bool history,
  }) {
    final entry = LogEntry(
      source: spec.name,
      sequence: ++instance.sequence,
      receivedAt: _clock(),
      text: spec.encoding.decode(line.bytes),
      sizeBytes: line.bytes.length + spec.encoding.unitBytes,
      truncated: line.truncated,
    );
    ring.add(entry);
    if (history) return;
    for (final follower in instance.followers) {
      if (follower.wants(spec.name)) follower.offer(entry);
    }
    for (final listener in instance.listeners.toList()) {
      listener(entry);
    }
  }

  void _event(_InstanceLogs instance, LogSourceEvent event) {
    for (final follower in instance.followers) {
      if (follower.wants(event.source)) follower.offerEvent(event);
    }
  }

  // ---- the current-run mark (for the log_match health check) ---------------

  /// Reads what is pending, then records the current-run mark (design D6):
  /// the last sequence number, and for every `fixed` file source its size and
  /// the SHA-256 of its first 4 KiB. Call it before each Start.
  Future<LogRunMark> markRun(String instanceId) async {
    final instance = _require(instanceId);
    await instance.ready;
    await _pollInstance(instance);
    final marks = <String, FixedFileMark>{};
    for (final MapEntry(:key, :value) in instance.tailers.entries) {
      if (await value.markRun() case final mark?) marks[key] = mark;
    }
    return LogRunMark(sequence: instance.sequence, fixedFiles: marks);
  }

  /// The lines of [source] read after [mark], those already read since and
  /// those that follow, each once and in order. A `fixed` file rewritten
  /// since the mark is read from its start, even when it grew past its old
  /// size before the next poll.
  Stream<LogEntry> linesAfter(
    String instanceId,
    String source,
    LogRunMark mark,
  ) {
    final instance = _require(instanceId);
    late final void Function(LogEntry) listener;
    late final StreamController<LogEntry> controller;
    controller = StreamController<LogEntry>(
      onListen: () {
        final ring = instance.rings[source];
        if (ring != null) {
          for (final entry in ring.entries) {
            if (entry.sequence > mark.sequence) controller.add(entry);
          }
        }
        instance.listeners.add(listener);
        _schedule(instance);
      },
      onCancel: () {
        instance.listeners.remove(listener);
        _schedule(instance);
      },
    );
    listener = (entry) {
      if (entry.source == source && entry.sequence > mark.sequence) {
        controller.add(entry);
      }
    };
    return controller.stream;
  }

  // ---- offsets -------------------------------------------------------------

  /// Saves where every source was read up to.
  void persistOffsets() {
    if (_closed) return;
    for (final instance in _instances.values) {
      _persist(instance);
    }
  }

  void _persist(_InstanceLogs instance) {
    final store = _offsets;
    if (store == null) return;
    for (final MapEntry(:key, :value) in instance.tailers.entries) {
      final position = value.position;
      if (position == null) continue;
      final id = '${instance.id}/$key';
      final last = _saved[id];
      if (last != null &&
          last.file == position.file &&
          last.offset == position.offset) {
        continue;
      }
      try {
        store.save(instance.id, key, position);
        _saved[id] = position;
      } on Object {
        // The database is going away; the next start refills from the file.
      }
    }
  }

  /// Stops polling, saves the offsets and closes every follower.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final instances = _instances.values.toList();
    for (final instance in instances) {
      instance.timer?.cancel();
    }
    _persistTimer.cancel();
    for (final instance in instances) {
      try {
        await instance.ready;
        await Future.wait([for (final t in instance.tailers.values) t.poll()]);
      } on Object {
        // Whatever could not be read is read again after the restart.
      }
    }
    for (final instance in instances) {
      _persist(instance);
      for (final follower in instance.followers.toList()) {
        follower.close();
      }
    }
    _instances.clear();
  }
}

class _InstanceLogs {
  _InstanceLogs(this.id);

  final String id;
  final tailers = <String, SourceTailer>{};
  final rings = <String, LogRing>{};
  final followers = <_Follower>[];
  final listeners = <void Function(LogEntry)>[];
  var sequence = 0;
  Future<void> ready = Future<void>.value();
  Timer? timer;

  bool get isFollowed => followers.isNotEmpty || listeners.isNotEmpty;
}

/// One `Follow` subscriber with its bounded queue. While the subscriber is
/// paused, lines pile up to 1,000 or 4 MiB, then the oldest are dropped and
/// counted; the count goes out with the next batch. Source events pile up to
/// [followMaxEvents], then the oldest are dropped (silently: they carry no
/// count). A batch is closed at [followBatchBytes] on the wire.
class _Follower {
  _Follower(this.controller, this.sources);

  final StreamController<LogBatch> controller;
  final Set<String> sources;

  /// [LogEntry] and [LogSourceEvent] in arrival order.
  final _queue = <Object>[];
  var _lines = 0;
  var _bytes = 0;
  var _events = 0;
  var _dropped = 0;

  bool wants(String source) => sources.isEmpty || sources.contains(source);

  /// Most a line can grow when decoded and sent as UTF-8: an invalid UTF-8
  /// byte becomes the three bytes of U+FFFD.
  static const _wireFactor = 3;

  bool get _canDeliver =>
      controller.hasListener && !controller.isPaused && !controller.isClosed;

  void offer(LogEntry entry) {
    _queue.add(entry);
    _lines++;
    _bytes += entry.sizeBytes;
    if (_canDeliver) {
      // Not behind: hand over in batches, never drop.
      if (_lines >= followMaxLagLines ~/ 4 ||
          _bytes * _wireFactor >= followBatchBytes) {
        flush();
      }
      return;
    }
    while (_lines > followMaxLagLines || _bytes > followMaxLagBytes) {
      final at = _queue.indexWhere((item) => item is LogEntry);
      final dropped = _queue.removeAt(at) as LogEntry;
      _lines--;
      _bytes -= dropped.sizeBytes;
      _dropped++;
    }
  }

  void offerEvent(LogSourceEvent event) {
    _queue.add(event);
    _events++;
    if (_canDeliver) {
      flush();
    } else if (_events > followMaxEvents) {
      _queue.removeAt(_queue.indexWhere((item) => item is LogSourceEvent));
      _events--;
    }
  }

  /// Sends what is queued, unless the subscriber is paused.
  void flush() {
    if (!_canDeliver || (_queue.isEmpty && _dropped == 0)) return;
    final batches = <LogBatch>[];
    var entries = <LogEntry>[];
    var dropped = _dropped;
    var wireBytes = 0;
    void closeLines() {
      wireBytes = 0;
      if (entries.isEmpty && dropped == 0) return;
      batches.add(LogBatch(entries: entries, dropped: dropped));
      entries = [];
      dropped = 0;
    }

    for (final item in _queue) {
      switch (item) {
        case LogEntry():
          entries.add(item);
          wireBytes += item.sizeBytes * _wireFactor;
          if (wireBytes >= followBatchBytes) closeLines();
        case LogSourceEvent(:final source, :final event):
          closeLines();
          batches.add(LogBatch(source: source, sourceEvent: event));
      }
    }
    closeLines();
    _queue.clear();
    _lines = 0;
    _bytes = 0;
    _events = 0;
    _dropped = 0;
    batches.forEach(controller.add);
  }

  void close() {
    if (!controller.isClosed) controller.close();
  }
}
