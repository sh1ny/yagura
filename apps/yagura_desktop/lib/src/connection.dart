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

/// The last attempt failed. The connection keeps retrying with backoff.
final class Offline extends ConnectionStatus {
  const Offline({required this.error, this.lastSeen});

  /// Reason or message of the last failure.
  final String error;

  /// When the daemon last answered in this session, null when never.
  final DateTime? lastSeen;
}

/// The daemon rejected this device with `device_revoked`. The connection has
/// stopped; the admin pairs again.
final class Revoked extends ConnectionStatus {
  const Revoked();
}

/// The device certificate has expired or its renewal was refused. The
/// connection has stopped; the admin pairs again.
final class Expired extends ConnectionStatus {
  const Expired();
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
    this.warnings = const [],
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

  /// Warnings the finished operation carries, e.g. `external_edit: ...`.
  final List<String> warnings;
  final int lastSequence;

  OperationState copyWith({
    OperationStatus? status,
    List<String>? steps,
    double? percent,
    bool clearPercent = false,
    String? message,
    List<String>? warnings,
    int? lastSequence,
  }) => OperationState(
    id: id,
    instanceId: instanceId,
    kind: kind,
    status: status ?? this.status,
    steps: steps ?? this.steps,
    percent: clearPercent ? null : (percent ?? this.percent),
    message: message ?? this.message,
    warnings: warnings ?? this.warnings,
    lastSequence: lastSequence ?? this.lastSequence,
  );

  bool get ended => switch (status) {
    OperationStatus.OPERATION_STATUS_QUEUED ||
    OperationStatus.OPERATION_STATUS_RUNNING ||
    OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT => false,
    _ => true,
  };
}

/// A pending prompt that another device answered, or that ended without an
/// answer from this client.
final class PromptResolution {
  const PromptResolution(this.prompt, this.resolved);

  final PendingPrompt prompt;
  final PromptResolved resolved;
}

typedef Delay = Future<void> Function(Duration duration);

/// The instance exists but a secret could not be set on it.
class SecretNotSet implements Exception {
  const SecretNotSet(this.instance, this.key, this.cause);

  final Instance instance;
  final String key;
  final DaemonCallException cause;

  String get message =>
      'The instance was created, but the secret "$key" was not set: '
      '${cause.message.isEmpty ? cause.reason : cause.message}. '
      'Set it in the instance settings.';

  @override
  String toString() => message;
}

/// Thrown by the `afterConnect` hook when the credentials changed (a renewed
/// certificate): the connection opens a new transport at once, with the new
/// pair, and closes the old one after the new one is up. The daemon is not
/// shown as reconnecting meanwhile.
class ConnectionRefresh implements Exception {
  const ConnectionRefresh();
}

/// Thrown by the connection's `connect` or `afterConnect` hooks when the
/// daemon cannot be used until the admin acts (pairs again): the connection
/// takes [status] and stops.
class ConnectionBlocked implements Exception {
  const ConnectionBlocked(this.status);

  final ConnectionStatus status;
}

/// The longest wait between reconnect attempts.
const Duration kBackoffCap = Duration(seconds: 30);

/// Reconnect delays: 1 s, doubling to a 30 s cap.
Duration backoffDelay(int attempt) {
  if (attempt >= 5) return kBackoffCap;
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
    this.afterConnect,
    this.clientVersion = kClientApiVersion,
    Delay? delay,
    DateTime Function()? now,
    this.lastSeenBefore,
    this.onSeen,
  }) : _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final String id;
  final ApiVersion clientVersion;

  /// Makes a transport for every attempt. May throw [ConnectionBlocked].
  final FutureOr<DaemonTransport> Function() _connect;

  /// Runs after each successful connect without delaying the instance
  /// stream (renewal). [ended] completes when that connection is over. May
  /// throw [ConnectionBlocked].
  final Future<void> Function(DaemonTransport transport, Future<void> ended)?
  afterConnect;
  final Delay _delay;
  final DateTime Function() _now;

  /// When the daemon last answered in an earlier session (from the daemon
  /// list), used until it answers in this one.
  final DateTime? Function()? lastSeenBefore;

  /// Called with the time the daemon answered (on connect) or was lost, so
  /// the daemon list can keep it across restarts.
  final void Function(DateTime seen)? onSeen;

  final _status = ValueNotifier<ConnectionStatus>(const Connecting());
  final _instances = ValueNotifier<List<Instance>>(const []);
  final _operations = ValueNotifier<List<OperationState>>(const []);
  final _prompts = ValueNotifier<List<PendingPrompt>>(const []);
  final _settingsInvalid = ValueNotifier<Map<String, String>>(const {});
  final _resolutions = StreamController<PromptResolution>.broadcast();

  /// Prompts this client is answering or cancelling: their resolution is its
  /// own doing and is not reported as another device's.
  final _answeredByMe = <String>{};
  final _cache = <String, Instance>{};
  final _stop = Completer<void>();
  final _connectedWaiters = <Completer<DaemonTransport>>[];

  DaemonTransport? _transport;
  bool _started = false;
  bool _disposed = false;

  /// Set when the connection has stopped for good (revoked, expired): no
  /// reconnect.
  ConnectionStatus? _terminal;
  DateTime? _lastSeen;

  /// Set when the credentials changed: the next attempt starts at once and
  /// the old transport stays in use until the new one is up.
  bool _refresh = false;
  DaemonTransport? _retiring;

  /// Ends the current instance stream early (a terminal state, dispose).
  void Function()? _cancelWatch;

  ConnectionStatus get status => _status.value;
  Stream<ConnectionStatus> get statusStream => _replay(_status);
  Stream<List<Instance>> get instancesStream => _replay(_instances);
  Stream<List<OperationState>> get operationsStream => _replay(_operations);

  /// Every prompt pending on the daemon, from `WatchPrompts`.
  Stream<List<PendingPrompt>> get promptsStream => _replay(_prompts);

  /// Prompts that ended without this client's answer (another device answered
  /// them, they expired or their operation was cancelled).
  Stream<PromptResolution> get promptResolutions => _resolutions.stream;

  /// What the daemon's `settings_invalid` notice said, by instance id.
  Stream<Map<String, String>> get settingsInvalidStream =>
      _replay(_settingsInvalid);

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
    _cancelWatch?.call();
    for (final waiter in _connectedWaiters) {
      waiter.completeError(StateError('connection disposed'));
    }
    _connectedWaiters.clear();
    unawaited(_resolutions.close());
    // The notifiers stay undisposed: widgets may still be tearing down.
    await transport?.close();
  }

  /// Stops reconnecting and takes [status] (`revoked`, `expired`).
  void _terminate(ConnectionStatus status) {
    if (_disposed || _terminal != null) return;
    _terminal = status;
    _setStatus(status);
    for (final waiter in _connectedWaiters) {
      waiter.completeError(StateError('daemon $id is not available'));
    }
    _connectedWaiters.clear();
    _cancelWatch?.call();
  }

  /// The terminal state a failed call puts the daemon in, if any.
  static ConnectionStatus? _terminalFor(Object error) => switch (error) {
    ConnectionBlocked(:final status) => status,
    DaemonCallException(reason: 'device_revoked') => const Revoked(),
    DaemonCallException(reason: 'certificate_expired') => const Expired(),
    _ => null,
  };

  static String _describe(Object error) => switch (error) {
    DaemonCallException(:final reason, :final message, :final code) =>
      reason.isNotEmpty
          ? reason
          : (message.isNotEmpty ? message : 'status $code'),
    _ => '$error',
  };

  void _markSeen() {
    final seen = _lastSeen = _now();
    onSeen?.call(seen);
  }

  void _setStatus(ConnectionStatus status) {
    if (!_disposed) _status.value = status;
  }

  Future<void> _run() async {
    var attempt = 0;
    var everConnected = false;
    var refreshing = false;
    while (!_disposed && _terminal == null) {
      // An offline daemon stays offline while it is retried; a refresh keeps
      // the connected state until the new transport is up.
      if (!refreshing && _status.value is! Offline) {
        _setStatus(everConnected ? const Reconnecting() : const Connecting());
      }
      DaemonTransport? transport;
      var connected = false;
      final ended = Completer<void>();
      try {
        transport = await _connect();
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
            final old = _retiring;
            _retiring = null;
            if (old != null) unawaited(old.close().catchError((Object _) {}));
            everConnected = true;
            connected = true;
            attempt = 0;
            _markSeen();
            _setStatus(Connected(info: info, negotiated: negotiated));
            for (final waiter in _connectedWaiters) {
              waiter.complete(transport);
            }
            _connectedWaiters.clear();
            unawaited(_watchPrompts(transport, ended.future));
            if (afterConnect case final hook?) {
              unawaited(_afterConnect(hook, transport, ended.future));
            }
            await _watch(transport);
        }
      } on Object catch (error) {
        debugPrint('daemon $id: connection lost: $error');
        if (_terminalFor(error) case final terminal?) _terminate(terminal);
        if (_terminal == null && !_disposed) {
          if (connected) {
            _markSeen();
            _setStatus(const Reconnecting());
          } else if (everConnected && backoffDelay(attempt) < kBackoffCap) {
            // It was up in this session: it is `connecting` while it is
            // retried quickly, `offline` once the backoff reaches its cap.
            _setStatus(const Reconnecting());
          } else {
            _setStatus(
              Offline(
                error: _describe(error),
                lastSeen: _lastSeen ?? lastSeenBefore?.call(),
              ),
            );
          }
        }
      }
      ended.complete();
      refreshing = _refresh && connected && _terminal == null && !_disposed;
      _refresh = false;
      if (refreshing) {
        // Keep serving on this transport; it is closed once the next one is
        // up (or when that attempt fails).
        _retiring = transport;
        attempt = 0;
        continue;
      }
      _transport = null;
      for (final t in [transport, _retiring]) {
        if (t != null) unawaited(t.close().catchError((Object _) {}));
      }
      _retiring = null;
      if (_disposed || _terminal != null) break;
      if (connected && _status.value is Connected) {
        // The stream ended without an error: the connection is lost too.
        _markSeen();
        _setStatus(const Reconnecting());
      }
      await Future.any([_delay(backoffDelay(attempt)), _stop.future]);
      attempt++;
    }
  }

  Future<void> _afterConnect(
    Future<void> Function(DaemonTransport, Future<void>) hook,
    DaemonTransport transport,
    Future<void> ended,
  ) async {
    try {
      await hook(transport, ended);
    } on ConnectionRefresh {
      if (_disposed || _terminal != null) return;
      _refresh = true;
      _cancelWatch?.call();
    } on Object catch (error) {
      if (_terminalFor(error) case final terminal?) {
        _terminate(terminal);
      } else {
        debugPrint('daemon $id: after-connect hook failed: $error');
      }
    }
  }

  /// Follows `WatchPrompts` while [ended] is pending. A failure (an older
  /// daemon answers `UNIMPLEMENTED`) leaves the rest of the connection alone;
  /// the next connection opens the stream again.
  Future<void> _watchPrompts(DaemonTransport transport, Future<void> ended) {
    final done = Completer<void>();
    final subscription = transport.watchPrompts().listen(
      _applyPromptEvent,
      onError: (Object error, StackTrace stack) {
        debugPrint('daemon $id: prompt stream failed: $error');
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return Future.any([ended, done.future])
        .whenComplete(() => subscription.cancel());
  }

  void _applyPromptEvent(PromptEvent event) {
    if (_disposed) return;
    switch (event.whichEvent()) {
      case PromptEvent_Event.snapshot:
        _prompts.value = List.unmodifiable(event.snapshot.prompts);
      case PromptEvent_Event.raised:
        final raised = event.raised;
        _prompts.value = List.unmodifiable([
          for (final p in _prompts.value)
            if (p.prompt.id != raised.prompt.id) p,
          raised,
        ]);
      case PromptEvent_Event.resolved:
        final resolved = event.resolved;
        final prompt = _prompts.value
            .where((p) => p.prompt.id == resolved.promptId)
            .firstOrNull;
        if (prompt == null) return;
        // Told before the prompt leaves the list, so a view can say why it
        // closes.
        if (!_answeredByMe.remove(resolved.promptId)) {
          _resolutions.add(PromptResolution(prompt, resolved));
        }
        _removePrompt(resolved.promptId);
      case PromptEvent_Event.resyncRequired:
        // A new snapshot follows on the same stream.
        return;
      case PromptEvent_Event.notSet:
        return;
    }
  }

  PendingPrompt? _removePrompt(String promptId) {
    final list = _prompts.value;
    final index = list.indexWhere((p) => p.prompt.id == promptId);
    if (index < 0) return null;
    _prompts.value = List.unmodifiable([...list]..removeAt(index));
    return list[index];
  }

  /// Applies the instance stream until it ends or [_cancelWatch] is called;
  /// a stream error is rethrown.
  Future<void> _watch(DaemonTransport transport) {
    final done = Completer<void>();
    final subscription = transport.watchInstances().listen(
      _apply,
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    _cancelWatch = () {
      unawaited(subscription.cancel());
      if (!done.isCompleted) done.complete();
    };
    return done.future.whenComplete(() => _cancelWatch = null);
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
        final notice = event.notice;
        if (notice.kind == 'settings_invalid') {
          _settingsInvalid.value = {
            ..._settingsInvalid.value,
            notice.instanceId: notice.message,
          };
        }
        return;
      case InstanceEvent_Event.notSet:
        return;
    }
    // The flag is the truth: a message about an instance that is valid again
    // (or gone) is stale.
    final stale = [
      for (final id in _settingsInvalid.value.keys)
        if (_cache[id]?.settingsInvalid != true) id,
    ];
    if (stale.isNotEmpty) {
      _settingsInvalid.value = {
        for (final e in _settingsInvalid.value.entries)
          if (!stale.contains(e.key)) e.key: e.value,
      };
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
    Map<String, String> secrets = const {},
  }) async {
    final plugin = await transport.getPlugin(pluginId);
    var created = await transport.createInstance(
      CreateInstanceRequest(
        pluginId: pluginId,
        name: name,
        settings: JsonDocument(
          json: jsonEncode(settings),
          schemaVersion: plugin.settingsSchema.schemaVersion,
        ),
      ),
    );
    // Secrets never ride on CreateInstance: each goes with SetSecret, against
    // the revision the previous call returned.
    for (final MapEntry(:key, :value) in secrets.entries) {
      try {
        created = await transport.setSecret(
          SetSecretRequest(
            instanceId: created.id,
            expectedRevision: created.revision,
            key: key,
            value: value,
          ),
        );
      } on DaemonCallException catch (e) {
        throw SecretNotSet(created, key, e);
      }
    }
    return created;
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

  /// Starts adding a Steam account. The password goes out with the call and is
  /// held nowhere here.
  Future<void> addAccount(
    String username,
    String password, {
    bool rememberPassword = false,
  }) => _track(
    transport.addAccount(
      AddAccountRequest(
        username: username,
        password: password,
        rememberPassword: rememberPassword,
      ),
    ),
  );

  Future<void> reauthAccount(
    String accountId,
    String password, {
    bool rememberPassword = false,
  }) => _track(
    transport.reauthAccount(
      ReauthAccountRequest(
        accountId: accountId,
        password: password,
        rememberPassword: rememberPassword,
      ),
    ),
  );

  Future<void> applyMods(Instance instance) =>
      _track(transport.applyMods(instance.id));

  Future<void> checkModUpdates(Instance instance) =>
      _track(transport.checkModUpdates(instance.id));

  Future<void> updateMods(Instance instance) =>
      _track(transport.updateMods(instance.id));

  /// Answers [pending] through the first operation waiting on it.
  Future<void> respondToPrompt(PendingPrompt pending, String value) async {
    final promptId = pending.prompt.id;
    _answeredByMe.add(promptId);
    try {
      await transport.respondToPrompt(
        RespondToPromptRequest(
          operationId: pending.operations.first.operationId,
          promptId: promptId,
          value: value,
        ),
      );
    } on Object {
      _answeredByMe.remove(promptId);
      rethrow;
    }
    _removePrompt(promptId);
    _answeredByMe.remove(promptId);
  }

  /// Cancels the operation [pending] belongs to, which resolves the prompt.
  Future<void> cancelPrompt(PendingPrompt pending) async {
    final promptId = pending.prompt.id;
    _answeredByMe.add(promptId);
    try {
      await transport.cancelOperation(pending.operations.first.operationId);
    } on Object {
      _answeredByMe.remove(promptId);
      rethrow;
    }
    _removePrompt(promptId);
    _answeredByMe.remove(promptId);
  }

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
        warnings: event.finished.warnings,
        clearPercent: true,
      ),
      OperationEvent_Event.prompt => current.copyWith(
        status: OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT,
        clearPercent: true,
      ),
      OperationEvent_Event.promptResolved =>
        current.status == OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT
            ? current.copyWith(status: OperationStatus.OPERATION_STATUS_RUNNING)
            : current,
      // Events were skipped: the snapshot that follows says where the
      // operation is now, so the steps shown so far no longer add up.
      OperationEvent_Event.eventsDropped => current.copyWith(
        steps: const [],
        clearPercent: true,
      ),
      OperationEvent_Event.snapshot => current.copyWith(
        status: event.snapshot.status,
        steps: current.steps.isEmpty && event.snapshot.currentStep.isNotEmpty
            ? [event.snapshot.currentStep]
            : current.steps,
        warnings: event.snapshot.warnings,
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
