/// One connection object per daemon (design D10).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'api_version.dart';
import 'transport.dart';

sealed class ConnectionStatus {
  const ConnectionStatus();
}

final class Connecting extends ConnectionStatus {
  const Connecting();
}

final class Connected extends ConnectionStatus {
  const Connected({required this.info, required this.negotiated});

  final DaemonInfo info;
  final Compatible negotiated;
}

final class Reconnecting extends ConnectionStatus {
  const Reconnecting();
}

final class IncompatibleDaemon extends ConnectionStatus {
  const IncompatibleDaemon({required this.client, required this.daemon});

  final ApiVersion client;
  final List<ApiVersion> daemon;
}

/// What the client shows about one operation.
final class OperationState {
  const OperationState({
    required this.id,
    required this.instanceId,
    required this.kind,
    this.status = OperationStatus.OPERATION_STATUS_RUNNING,
    this.steps = const [],
    this.percent,
    this.message = '',
    this.lastSequence = 0,
  });

  final String id;
  final String instanceId;
  final String kind;
  final OperationStatus status;

  /// Steps in the order they started; the last one is current.
  final List<String> steps;

  /// 0-100 of the current step, null when unknown.
  final double? percent;
  final String message;
  final int lastSequence;

  OperationState copyWith({
    OperationStatus? status,
    List<String>? steps,
    double? percent,
    bool clearPercent = false,
    String? message,
    int? lastSequence,
  }) => OperationState(
    id: id,
    instanceId: instanceId,
    kind: kind,
    status: status ?? this.status,
    steps: steps ?? this.steps,
    percent: clearPercent ? null : (percent ?? this.percent),
    message: message ?? this.message,
    lastSequence: lastSequence ?? this.lastSequence,
  );

  bool get ended => switch (status) {
    OperationStatus.OPERATION_STATUS_QUEUED ||
    OperationStatus.OPERATION_STATUS_RUNNING ||
    OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT => false,
    _ => true,
  };
}

typedef Delay = Future<void> Function(Duration duration);

/// Reconnect delays: 1 s, doubling to a 30 s cap.
Duration backoffDelay(int attempt) {
  const cap = Duration(seconds: 30);
  if (attempt >= 5) return cap;
  return Duration(seconds: 1 << attempt);
}

/// Replays the current value to each new listener, then every change.
Stream<T> _replay<T>(ValueListenable<T> source) => Stream<T>.multi((c) {
  c.add(source.value);
  void onChange() => c.add(source.value);
  source.addListener(onChange);
  c.onCancel = () => source.removeListener(onChange);
});

/// The connection to one daemon. It owns the `WatchInstances` stream and the
/// snapshot cache; views subscribe through providers (design D10).
///
/// [connect] makes a transport for every attempt. After the connection drops
/// the object reconnects with [backoffDelay], takes a fresh instance snapshot
/// and lets the streams opened through it resume.
class DaemonConnection {
  DaemonConnection({
    required this.id,
    required this._connect,
    this.clientVersion = kClientApiVersion,
    Delay? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final String id;
  final ApiVersion clientVersion;
  final DaemonTransport Function() _connect;
  final Delay _delay;

  final _status = ValueNotifier<ConnectionStatus>(const Connecting());
  final _instances = ValueNotifier<List<Instance>>(const []);
  final _operations = ValueNotifier<List<OperationState>>(const []);
  final _cache = <String, Instance>{};
  final _stop = Completer<void>();
  final _connectedWaiters = <Completer<DaemonTransport>>[];

  DaemonTransport? _transport;
  bool _started = false;
  bool _disposed = false;

  ConnectionStatus get status => _status.value;
  Stream<ConnectionStatus> get statusStream => _replay(_status);
  Stream<List<Instance>> get instancesStream => _replay(_instances);
  Stream<List<OperationState>> get operationsStream => _replay(_operations);

  /// The transport of the current connection; throws [StateError] when the
  /// daemon is not connected.
  DaemonTransport get transport => switch ((_status.value, _transport)) {
    (Connected(), final t?) => t,
    _ => throw StateError('daemon $id is not connected'),
  };

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_stop.isCompleted) _stop.complete();
    final transport = _transport;
    _transport = null;
    for (final waiter in _connectedWaiters) {
      waiter.completeError(StateError('connection disposed'));
    }
    _connectedWaiters.clear();
    // The notifiers stay undisposed: widgets may still be tearing down.
    await transport?.close();
  }

  void _setStatus(ConnectionStatus status) {
    if (!_disposed) _status.value = status;
  }

  Future<void> _run() async {
    var attempt = 0;
    var everConnected = false;
    while (!_disposed) {
      _setStatus(everConnected ? const Reconnecting() : const Connecting());
      final transport = _connect();
      try {
        final info = await transport.getInfo();
        if (_disposed) break;
        final versions = [
          for (final v in info.apiVersions) ?ApiVersion.tryParse(v),
        ];
        if (versions.isEmpty) {
          if (ApiVersion.tryParse(info.apiVersion) case final v?) {
            versions.add(v);
          }
        }
        switch (negotiate(client: clientVersion, daemon: versions)) {
          case Incompatible(:final client, :final daemon):
            _setStatus(IncompatibleDaemon(client: client, daemon: daemon));
            await transport.close();
            return;
          case final Compatible negotiated:
            _transport = transport;
            everConnected = true;
            attempt = 0;
            _setStatus(Connected(info: info, negotiated: negotiated));
            for (final waiter in _connectedWaiters) {
              waiter.complete(transport);
            }
            _connectedWaiters.clear();
            await for (final event in transport.watchInstances()) {
              _apply(event);
            }
        }
      } on Object catch (error) {
        debugPrint('daemon $id: connection lost: $error');
      }
      _transport = null;
      unawaited(transport.close().catchError((Object _) {}));
      if (_disposed) break;
      _setStatus(const Reconnecting());
      await Future.any([_delay(backoffDelay(attempt)), _stop.future]);
      attempt++;
    }
  }

  void _apply(InstanceEvent event) {
    switch (event.whichEvent()) {
      case InstanceEvent_Event.snapshot:
        _cache
          ..clear()
          ..addEntries(event.snapshot.instances.map((i) => MapEntry(i.id, i)));
      case InstanceEvent_Event.changed:
        final changed = event.changed;
        final old = _cache[changed.id];
        // Deltas may omit unchanged settings: keep the cached document.
        _cache[changed.id] = changed.settingsOmitted && old != null
            ? (changed.deepCopy()..settings = old.settings)
            : changed;
      case InstanceEvent_Event.removedInstanceId:
        _cache.remove(event.removedInstanceId);
      case InstanceEvent_Event.resyncRequired:
        // A new snapshot follows on the same stream.
        return;
      case InstanceEvent_Event.notice:
      case InstanceEvent_Event.notSet:
        return;
    }
    _instances.value = List.unmodifiable(
      _cache.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  /// Completes with the transport once the daemon is connected (immediately
  /// when it already is); fails with [StateError] after [dispose].
  Future<DaemonTransport> whenConnected() {
    if (_disposed) return Future.error(StateError('connection disposed'));
    if (_status.value is Connected && _transport != null) {
      return Future.value(_transport);
    }
    final waiter = Completer<DaemonTransport>();
    _connectedWaiters.add(waiter);
    return waiter.future;
  }

  /// Opens a stream on the current transport and, when the connection drops,
  /// opens it again on the next one. A stream that ends normally ends here.
  /// Repeated failures without data are passed on.
  Stream<T> _resumable<T>(Stream<T> Function(DaemonTransport t) open) async* {
    var failures = 0;
    while (!_disposed) {
      final DaemonTransport t;
      try {
        t = await whenConnected();
      } on StateError {
        return;
      }
      try {
        await for (final item in open(t)) {
          failures = 0;
          yield item;
        }
        return;
      } on Object {
        if (_disposed || ++failures > 5) rethrow;
      }
      await Future.any([_delay(backoffDelay(0)), _stop.future]);
    }
  }

  Future<Instance> createInstance(
    String pluginId,
    String name, {
    Map<String, Object?> settings = const {},
  }) async {
    final plugin = await transport.getPlugin(pluginId);
    return transport.createInstance(
      CreateInstanceRequest(
        pluginId: pluginId,
        name: name,
        settings: JsonDocument(
          json: jsonEncode(settings),
          schemaVersion: plugin.settingsSchema.schemaVersion,
        ),
      ),
    );
  }

  Future<void> install(Instance instance) =>
      _track(transport.install(instance.id));

  Future<void> startInstance(Instance instance) =>
      _track(transport.start(instance.id));

  Future<void> stopInstance(Instance instance) =>
      _track(transport.stop(instance.id));

  Future<void> deleteInstance(
    Instance instance, {
    bool deleteFiles = false,
    String confirmName = '',
  }) => _track(
    transport.deleteInstance(
      DeleteInstanceRequest(
        instanceId: instance.id,
        expectedRevision: instance.revision,
        deleteFiles: deleteFiles,
        confirmName: confirmName,
      ),
    ),
  );

  /// Follows an operation the daemon accepted and shows its steps.
  Future<void> _track(Future<Operation> call) async {
    final operation = await call;
    _putOperation(
      OperationState(
        id: operation.id,
        instanceId: operation.instanceId,
        kind: operation.kind,
        status: operation.status == OperationStatus.OPERATION_STATUS_UNSPECIFIED
            ? OperationStatus.OPERATION_STATUS_RUNNING
            : operation.status,
      ),
    );
    unawaited(_followOperation(operation.id));
  }

  void _putOperation(OperationState state) {
    if (_disposed) return;
    final list = [..._operations.value];
    final index = list.indexWhere((o) => o.id == state.id);
    if (index < 0) {
      list.add(state);
    } else {
      list[index] = state;
    }
    _operations.value = List.unmodifiable(list);
  }

  OperationState? _operation(String id) {
    for (final o in _operations.value) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Follows [operationId] until it ends; after a reconnect the stream resumes
  /// from the last sequence seen.
  Future<void> _followOperation(String operationId) async {
    try {
      await for (final event in _resumable(
        (t) => t.watchOperation(
          operationId,
          afterSequence: _operation(operationId)?.lastSequence ?? 0,
        ),
      )) {
        _applyOperationEvent(operationId, event);
      }
    } on Object catch (error) {
      debugPrint('daemon $id: operation $operationId stream failed: $error');
    }
  }

  void _applyOperationEvent(String operationId, OperationEvent event) {
    final current = _operation(operationId);
    if (current == null) return;
    final updated = switch (event.whichEvent()) {
      OperationEvent_Event.stepStarted => current.copyWith(
        steps: [...current.steps, event.stepStarted.step],
        clearPercent: true,
      ),
      OperationEvent_Event.progress => current.copyWith(
        percent: event.progress.percent,
        clearPercent: event.progress.percent < 0,
      ),
      OperationEvent_Event.finished => current.copyWith(
        status: event.finished.status,
        message: event.finished.resultMessage.isNotEmpty
            ? event.finished.resultMessage
            : event.finished.resultReason,
        clearPercent: true,
      ),
      OperationEvent_Event.snapshot => current.copyWith(
        status: event.snapshot.status,
        steps: current.steps.isEmpty && event.snapshot.currentStep.isNotEmpty
            ? [event.snapshot.currentStep]
            : current.steps,
      ),
      _ => current,
    };
    _putOperation(updated.copyWith(lastSequence: event.sequence.toInt()));
  }

  /// Backlog lines, oldest first.
  Stream<LogBatch> backlog(String instanceId) =>
      _resumable((t) => t.backlog(instanceId));

  /// Live log batches; re-opened after a reconnect.
  Stream<LogBatch> followLogs(String instanceId) =>
      _resumable((t) => t.follow(instanceId));
}
