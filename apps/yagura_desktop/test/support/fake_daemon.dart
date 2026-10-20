import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:yagura_desktop/src/api_version.dart';
import 'package:yagura_desktop/src/connection.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/transport.dart';
import 'package:yagura_proto/yagura_proto.dart';

/// A daemon the tests drive by hand: it emits snapshots, deltas, operation
/// events, log batches and field violations on demand.
class FakeDaemon implements DaemonTransport {
  FakeDaemon({
    this.apiVersions = const ['1.0'],
    List<Instance> instances = const [],
  }) : instances = [...instances];

  /// Versions `GetInfo` reports (the highest is also `api_version`).
  List<String> apiVersions;
  List<Instance> instances;
  bool up = true;

  /// Every call the client made, e.g. `GetInfo`, `Start:i1`.
  final List<String> calls = [];
  final Map<String, PluginDetail> plugins = {};
  final List<UpdateSettingsRequest> updates = [];
  final List<DeleteInstanceRequest> deletes = [];
  final List<CreateInstanceRequest> creates = [];

  /// Thrown by the next `UpdateSettings` when set.
  DaemonCallException? updateFailure;

  /// While set, `GetInfo` and `WatchInstances` fail with it (a daemon that
  /// rejects this client).
  DaemonCallException? failure;

  /// Every `SetSecret` call: (instance id, key, value, expected revision).
  final List<({String instanceId, String key, String value, int revision})>
  secretCalls = [];

  /// Runs at the start of every `SetSecret` (to change the instance
  /// meanwhile, as another device would).
  void Function()? beforeSetSecret;

  /// Thrown by `SetSecret` when set.
  DaemonCallException? setSecretFailure;

  /// When true a successful `UpdateSettings` stores the new settings and ports
  /// and bumps the revision, as the real daemon does.
  bool updateBumpsRevision = false;

  /// The CSRs of `RenewCertificate` calls.
  final List<Uint8List> renewals = [];

  /// Answers `RenewCertificate`.
  Future<EnrollResponse> Function(Uint8List csr)? onRenew;

  final List<StreamController<InstanceEvent>> _watchers = [];
  final Map<String, List<OperationEvent>> _opEvents = {};
  final Map<String, List<StreamController<OperationEvent>>> _opWatchers = {};
  final List<StreamController<LogBatch>> _followers = [];
  final List<LogBatch> backlogBatches = [];

  /// When set, `Backlog` sends nothing until this completes.
  Completer<void>? backlogGate;

  /// `afterSequence` of each `WatchOperation` call.
  final List<int> watchOperationResumes = [];

  int _nextOp = 1;

  @override
  Future<DaemonInfo> getInfo() async {
    calls.add('GetInfo');
    if (failure case final f?) throw f;
    if (!up) throw const DaemonCallException(code: 14, reason: 'unavailable');
    return DaemonInfo(
      daemonVersion: '0.1.0',
      apiVersion: apiVersions.last,
      apiVersions: apiVersions,
      hostName: 'fake-host',
    );
  }

  @override
  Stream<InstanceEvent> watchInstances() {
    calls.add('WatchInstances');
    if (failure case final f?) return Stream.error(f);
    if (!up) {
      return Stream.error(const DaemonCallException(code: 14));
    }
    final controller = StreamController<InstanceEvent>();
    _watchers.add(controller);
    controller.add(
      InstanceEvent(snapshot: InstanceSnapshot(instances: instances)),
    );
    return controller.stream;
  }

  /// The daemon goes away: every open stream fails and calls are refused.
  void kill({DaemonCallException error = const DaemonCallException(code: 14)}) {
    up = false;
    for (final c in [..._watchers, ..._followers, ..._promptWatchers]) {
      c.addError(error);
      c.close();
    }
    for (final list in _opWatchers.values) {
      for (final c in list) {
        c.addError(error);
        c.close();
      }
    }
    _watchers.clear();
    _followers.clear();
    _promptWatchers.clear();
    _opWatchers.clear();
  }

  void restart({List<Instance>? instances}) {
    up = true;
    if (instances != null) this.instances = [...instances];
  }

  void emitChanged(Instance instance) {
    instances = [
      for (final i in instances)
        if (i.id == instance.id) instance else i,
    ];
    for (final c in _watchers) {
      c.add(InstanceEvent(changed: instance));
    }
  }

  void emitOperation(String operationId, OperationEvent event) {
    _opEvents.putIfAbsent(operationId, () => []).add(event);
    for (final c in _opWatchers[operationId] ?? const []) {
      c.add(event);
    }
  }

  void emitLog(LogBatch batch) {
    for (final c in _followers) {
      c.add(batch);
    }
  }

  void _requireUp() {
    if (!up) throw const DaemonCallException(code: 14);
  }

  Operation _newOperation(String instanceId, String kind) {
    final op = Operation(
      id: 'op-${_nextOp++}',
      instanceId: instanceId,
      kind: kind,
      status: OperationStatus.OPERATION_STATUS_RUNNING,
    );
    return op;
  }

  @override
  Future<Instance> setSecret(SetSecretRequest request) async {
    _requireUp();
    calls.add('SetSecret:${request.instanceId}:${request.key}');
    secretCalls.add((
      instanceId: request.instanceId,
      key: request.key,
      value: request.value,
      revision: request.expectedRevision.toInt(),
    ));
    beforeSetSecret?.call();
    if (setSecretFailure case final failure?) throw failure;
    final current = instances.firstWhere((i) => i.id == request.instanceId);
    if (request.expectedRevision != current.revision) {
      throw const DaemonCallException(code: 9, reason: 'revision_conflict');
    }
    final settings = jsonDecode(current.settings.json) as Map<String, Object?>;
    settings[request.key] = {'secret': true, 'set': true};
    final updated = current.deepCopy()
      ..settings = JsonDocument(
        json: jsonEncode(settings),
        schemaVersion: current.settings.schemaVersion,
      )
      ..revision = current.revision + 1;
    emitChanged(updated);
    return updated;
  }

  @override
  Future<Instance> getInstance(String instanceId) async {
    _requireUp();
    calls.add('GetInstance:$instanceId');
    return instances.firstWhere((i) => i.id == instanceId);
  }

  @override
  Future<EnrollResponse> renewCertificate(Uint8List csrDer) async {
    _requireUp();
    calls.add('RenewCertificate');
    renewals.add(csrDer);
    return onRenew!(csrDer);
  }

  @override
  Future<Operation> install(String instanceId) async {
    _requireUp();
    calls.add('Install:$instanceId');
    return _newOperation(instanceId, 'install');
  }

  @override
  Future<Operation> start(String instanceId) async {
    _requireUp();
    calls.add('Start:$instanceId');
    return _newOperation(instanceId, 'start');
  }

  @override
  Future<Operation> stop(String instanceId) async {
    _requireUp();
    calls.add('Stop:$instanceId');
    return _newOperation(instanceId, 'stop');
  }

  @override
  Future<Operation> deleteInstance(DeleteInstanceRequest request) async {
    _requireUp();
    calls.add('DeleteInstance:${request.instanceId}');
    deletes.add(request);
    return _newOperation(request.instanceId, 'delete');
  }

  @override
  Future<Instance> createInstance(CreateInstanceRequest request) async {
    _requireUp();
    calls.add('CreateInstance:${request.pluginId}');
    creates.add(request);
    final created = Instance(
      id: 'new',
      name: request.name,
      pluginId: request.pluginId,
      state: InstanceState.INSTANCE_STATE_NOT_INSTALLED,
      settings: request.settings,
      revision: Int64(1),
    );
    instances = [...instances, created];
    for (final c in _watchers) {
      c.add(InstanceEvent(changed: created));
    }
    return created;
  }

  @override
  Future<Instance> updateSettings(UpdateSettingsRequest request) async {
    _requireUp();
    calls.add('UpdateSettings:${request.instanceId}');
    updates.add(request);
    if (updateFailure case final failure?) throw failure;
    final current = instances.firstWhere((i) => i.id == request.instanceId);
    if (request.expectedRevision != current.revision) {
      throw const DaemonCallException(code: 9, reason: 'revision_conflict');
    }
    if (!updateBumpsRevision) return current;
    final updated = current.deepCopy()
      ..settings = request.settings
      ..revision = current.revision + 1;
    emitChanged(updated);
    return updated;
  }

  @override
  Stream<OperationEvent> watchOperation(
    String operationId, {
    int afterSequence = 0,
  }) {
    calls.add('WatchOperation:$operationId');
    watchOperationResumes.add(afterSequence);
    if (!up) return Stream.error(const DaemonCallException(code: 14));
    final controller = StreamController<OperationEvent>();
    for (final e in _opEvents[operationId] ?? const <OperationEvent>[]) {
      if (e.sequence > Int64(afterSequence)) controller.add(e);
    }
    _opWatchers.putIfAbsent(operationId, () => []).add(controller);
    return controller.stream;
  }

  // ---- prompts ------------------------------------------------------------

  /// Prompts a new `WatchPrompts` subscriber gets as its snapshot.
  List<PendingPrompt> pendingPrompts = [];

  /// Every `RespondToPrompt` call: (operation id, prompt id, value).
  final List<({String operationId, String promptId, String value})>
  promptResponses = [];

  /// Thrown by `RespondToPrompt` when set (e.g. `prompt_resolved`).
  DaemonCallException? respondFailure;

  /// Answers `RespondToPrompt` instead of the default (resolves the prompt).
  Future<Operation> Function(RespondToPromptRequest request)? onRespond;

  final List<StreamController<PromptEvent>> _promptWatchers = [];

  @override
  Stream<PromptEvent> watchPrompts() {
    calls.add('WatchPrompts');
    if (!up) return Stream.error(const DaemonCallException(code: 14));
    final controller = StreamController<PromptEvent>();
    _promptWatchers.add(controller);
    controller.add(
      PromptEvent(snapshot: PromptSnapshot(prompts: pendingPrompts)),
    );
    return controller.stream;
  }

  @override
  Future<Operation> cancelOperation(String operationId) async {
    _requireUp();
    calls.add('CancelOperation:$operationId');
    for (final p in [...pendingPrompts]) {
      if (p.operations.any((o) => o.operationId == operationId)) {
        resolvePrompt(
          p.prompt.id,
          byDeviceId: 'this-device',
          outcome: 'cancelled',
        );
      }
    }
    return Operation(
      id: operationId,
      status: OperationStatus.OPERATION_STATUS_CANCELLED,
    );
  }

  /// The daemon sends a notice about [notice].instanceId.
  void emitNotice(InstanceNotice notice) {
    for (final c in _watchers) {
      c.add(InstanceEvent(notice: notice));
    }
  }

  /// An operation raises [prompt]: every prompt watcher gets it.
  void raisePrompt(Prompt prompt, {String operationId = 'op-1'}) {
    final pending = PendingPrompt(
      prompt: prompt,
      operations: [PromptSubject(operationId: operationId)],
    );
    pendingPrompts = [...pendingPrompts, pending];
    for (final c in _promptWatchers) {
      c.add(PromptEvent(raised: pending));
    }
  }

  /// Another client answered (or the prompt expired): every watcher is told.
  void resolvePrompt(
    String promptId, {
    String byDeviceId = 'other-device',
    String outcome = 'answered',
  }) {
    pendingPrompts = [
      for (final p in pendingPrompts)
        if (p.prompt.id != promptId) p,
    ];
    for (final c in _promptWatchers) {
      c.add(
        PromptEvent(
          resolved: PromptResolved(
            promptId: promptId,
            byDeviceId: byDeviceId,
            outcome: outcome,
          ),
        ),
      );
    }
  }

  @override
  Future<Operation> respondToPrompt(RespondToPromptRequest request) async {
    _requireUp();
    calls.add('RespondToPrompt:${request.operationId}');
    promptResponses.add((
      operationId: request.operationId,
      promptId: request.promptId,
      value: request.value,
    ));
    if (respondFailure case final failure?) throw failure;
    if (onRespond case final answer?) return answer(request);
    resolvePrompt(request.promptId, byDeviceId: 'this-device');
    return Operation(
      id: request.operationId,
      status: OperationStatus.OPERATION_STATUS_RUNNING,
    );
  }

  // ---- Steam accounts -----------------------------------------------------

  List<SteamAccount> accounts = [];
  final List<AddAccountRequest> accountAdds = [];
  final List<ReauthAccountRequest> accountReauths = [];

  /// Holds `AddAccount` until it completes (the call is "in flight").
  Completer<void>? addAccountGate;

  /// Thrown by `RemoveAccount` when set (e.g. `account_in_use`).
  DaemonCallException? removeAccountFailure;

  @override
  Future<List<SteamAccount>> listAccounts() async {
    _requireUp();
    calls.add('ListAccounts');
    return [...accounts];
  }

  @override
  Future<Operation> addAccount(AddAccountRequest request) async {
    _requireUp();
    calls.add('AddAccount:${request.username}');
    accountAdds.add(request);
    await addAccountGate?.future;
    return _newOperation('', 'add_steam_account');
  }

  @override
  Future<Operation> reauthAccount(ReauthAccountRequest request) async {
    _requireUp();
    calls.add('ReauthAccount:${request.accountId}');
    accountReauths.add(request);
    return _newOperation('', 'reauth_steam_account');
  }

  @override
  Future<List<SteamAccount>> removeAccount(String accountId) async {
    _requireUp();
    calls.add('RemoveAccount:$accountId');
    if (removeAccountFailure case final failure?) throw failure;
    accounts = [
      for (final a in accounts)
        if (a.id != accountId) a,
    ];
    return [...accounts];
  }

  // ---- mods ---------------------------------------------------------------

  /// The mods `ListMods` returns.
  List<Mod> mods = [];
  final List<SetModsRequest> modSets = [];

  /// Runs at the start of every `SetMods` (to change the list meanwhile, as
  /// another device would).
  void Function()? beforeSetMods;

  /// Builds the mods a successful `SetMods` stores; by default each requested
  /// mod is `pending` with a name.
  Mod Function(ModRef ref, int position)? modFor;

  @override
  Future<ListModsResponse> listMods(String instanceId) async {
    _requireUp();
    calls.add('ListMods:$instanceId');
    return ListModsResponse(mods: mods, updateCheck: 'ok');
  }

  @override
  Future<ListModsResponse> setMods(SetModsRequest request) async {
    _requireUp();
    calls.add('SetMods:${request.instanceId}');
    modSets.add(request);
    beforeSetMods?.call();
    final current = instances.firstWhere((i) => i.id == request.instanceId);
    if (request.expectedRevision != current.revision) {
      throw const DaemonCallException(code: 9, reason: 'revision_conflict');
    }
    mods = [
      for (final (i, ref) in request.mods.indexed)
        modFor?.call(ref, i) ??
            Mod(
              source: ref.source,
              itemId: ref.itemId,
              role: ref.role,
              position: i,
              name: 'Mod ${ref.itemId}',
              status: 'pending',
            ),
    ];
    emitChanged(current.deepCopy()..revision = current.revision + 1);
    return ListModsResponse(mods: mods, updateCheck: 'ok');
  }

  @override
  Future<Operation> applyMods(String instanceId) async {
    _requireUp();
    calls.add('ApplyMods:$instanceId');
    return _newOperation(instanceId, 'apply_mods');
  }

  @override
  Future<Operation> checkModUpdates(String instanceId) async {
    _requireUp();
    calls.add('CheckModUpdates:$instanceId');
    return _newOperation(instanceId, 'check_mod_updates');
  }

  @override
  Future<Operation> updateMods(
    String instanceId, {
    List<String> itemIds = const [],
  }) async {
    _requireUp();
    calls.add('UpdateMods:$instanceId');
    return _newOperation(instanceId, 'update_mods');
  }

  @override
  Future<List<PluginSummary>> listPlugins() async => [
    for (final p in plugins.values) p.summary,
  ];

  @override
  Future<PluginDetail> getPlugin(String pluginId) async {
    calls.add('GetPlugin:$pluginId');
    return plugins[pluginId]!;
  }

  @override
  Stream<LogBatch> backlog(String instanceId) {
    calls.add('Backlog:$instanceId');
    final gate = backlogGate;
    if (gate == null) return Stream.fromIterable(backlogBatches);
    return () async* {
      await gate.future;
      yield* Stream.fromIterable(backlogBatches);
    }();
  }

  @override
  Stream<LogBatch> follow(String instanceId) {
    calls.add('Follow:$instanceId');
    if (!up) return Stream.error(const DaemonCallException(code: 14));
    final controller = StreamController<LogBatch>();
    _followers.add(controller);
    return controller.stream;
  }

  @override
  Future<void> close() async {}
}

Instance makeInstance({
  required String id,
  required String name,
  InstanceState state = InstanceState.INSTANCE_STATE_STOPPED,
  String pluginId = 'testgame',
  List<Port> ports = const [],
  Map<String, Object?> settings = const {},
  int schemaVersion = 7,
  int revision = 1,
}) => Instance(
  id: id,
  name: name,
  pluginId: pluginId,
  state: state,
  ports: ports,
  settings: JsonDocument(
    json: jsonEncode(settings),
    schemaVersion: schemaVersion,
  ),
  revision: Int64(revision),
);

OperationEvent stepStarted(int sequence, String step) => OperationEvent(
  sequence: Int64(sequence),
  stepStarted: StepStarted(step: step),
);

OperationEvent progress(int sequence, String step, double percent) =>
    OperationEvent(
      sequence: Int64(sequence),
      progress: Progress(step: step, percent: percent),
    );

OperationEvent finished(int sequence, Operation operation) =>
    OperationEvent(sequence: Int64(sequence), finished: operation);

LogBatch logBatch(Iterable<int> numbers, {int dropped = 0}) => LogBatch(
  dropped: Int64(dropped),
  entries: [
    for (final n in numbers)
      LogEntry(source: 'server', sequence: Int64(n), text: 'line $n'),
  ],
);

/// Reconnect delays the test releases by hand instead of waiting.
class FakeDelay {
  final List<Duration> requested = [];
  final List<Completer<void>> _pending = [];

  Future<void> call(Duration duration) {
    requested.add(duration);
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  int get pending => _pending.length;

  /// Lets the oldest pending delay elapse.
  void release() => _pending.removeAt(0).complete();
}

class Harness {
  Harness({
    FakeDaemon? daemon,
    ApiVersion clientVersion = kClientApiVersion,
    this.autoStart = true,
  }) : daemon = daemon ?? FakeDaemon() {
    delay = FakeDelay();
    connection = DaemonConnection(
      id: kDevDaemonId,
      connect: () => this.daemon,
      clientVersion: clientVersion,
      delay: delay.call,
    );
  }

  final FakeDaemon daemon;
  final bool autoStart;
  late final FakeDelay delay;
  late final DaemonConnection connection;

  /// The overrides that put [connection] behind the dev daemon id.
  List<Override> get overrides => [
    daemonConnectionProvider(kDevDaemonId).overrideWithValue(connection),
  ];
}

/// Pumps [home] in an app wired to [harness] and starts its connection.
Future<void> pumpApp(
  WidgetTester tester,
  Harness harness,
  Widget home, {
  Size size = const Size(1000, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(home: Scaffold(body: home)),
    ),
  );
  if (harness.autoStart) harness.connection.start();
  await settle(tester);
  addTearDown(harness.connection.dispose);
}

/// Lets queued microtasks and provider updates reach the widgets.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}
