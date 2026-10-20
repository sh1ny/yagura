/// The seam between the client and one daemon (design D10).
///
/// The connection object talks to a [DaemonTransport]; production uses the gRPC
/// implementation, widget tests inject a fake that emits snapshots, deltas,
/// operation events, log lines and field violations.
library;

import 'dart:typed_data';

import 'package:yagura_proto/yagura_proto.dart';

/// A failed call, reduced to what the UI needs from the gRPC status and its
/// `ErrorDetail` (docs/protocol.md "Errors").
class DaemonCallException implements Exception {
  const DaemonCallException({
    required this.code,
    this.reason = '',
    this.message = '',
    this.fieldViolations = const {},
  });

  /// gRPC status code (`StatusCode`).
  final int code;

  /// Stable machine-readable reason, empty when the daemon sent no detail.
  final String reason;
  final String message;

  /// Constraint description by JSON field path, e.g. `ports.game`.
  final Map<String, String> fieldViolations;

  @override
  String toString() => 'DaemonCallException($code, $reason, $message)';
}

abstract interface class DaemonTransport {
  Future<DaemonInfo> getInfo();

  /// A snapshot first, then deltas.
  Stream<InstanceEvent> watchInstances();

  Future<Instance> getInstance(String instanceId);
  Future<Instance> createInstance(CreateInstanceRequest request);
  Future<Instance> updateSettings(UpdateSettingsRequest request);
  Future<Instance> setSecret(SetSecretRequest request);
  Future<Operation> install(String instanceId);
  Future<Operation> start(String instanceId);
  Future<Operation> stop(String instanceId);
  Future<Operation> deleteInstance(DeleteInstanceRequest request);

  /// Events after [afterSequence]; the stream ends after the finished event.
  Stream<OperationEvent> watchOperation(
    String operationId, {
    int afterSequence = 0,
  });

  /// Every pending prompt on the daemon (a snapshot first), then each prompt
  /// raised or resolved (design D13).
  Stream<PromptEvent> watchPrompts();

  /// Cancels an operation; a prompt it waits on resolves `cancelled`.
  Future<Operation> cancelOperation(String operationId);

  /// Answers a pending prompt of [RespondToPromptRequest.operationId].
  Future<Operation> respondToPrompt(RespondToPromptRequest request);

  Future<List<SteamAccount>> listAccounts();
  Future<Operation> addAccount(AddAccountRequest request);
  Future<Operation> reauthAccount(ReauthAccountRequest request);

  /// The accounts left after the removal.
  Future<List<SteamAccount>> removeAccount(String accountId);

  Future<ListModsResponse> listMods(String instanceId);
  Future<ListModsResponse> setMods(SetModsRequest request);
  Future<Operation> applyMods(String instanceId);
  Future<Operation> checkModUpdates(String instanceId);
  Future<Operation> updateMods(
    String instanceId, {
    List<String> itemIds = const [],
  });

  Future<List<PluginSummary>> listPlugins();
  Future<PluginDetail> getPlugin(String pluginId);

  Stream<LogBatch> backlog(String instanceId);
  Stream<LogBatch> follow(String instanceId);

  /// `Pairing.RenewCertificate` over this (authenticated) connection: signs a
  /// CSR for a new key.
  Future<EnrollResponse> renewCertificate(Uint8List csrDer);

  Future<void> close();
}
