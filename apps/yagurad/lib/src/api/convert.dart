import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:yagura_plugin/yagura_plugin.dart' as plugin;
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../instances/instance.dart';
import '../logs/log_models.dart';
import '../operations/operation.dart';
import '../snapshots/snapshots.dart';

Timestamp timestamp(DateTime at) => Timestamp.fromDateTime(at.toUtc());

// ---- instances --------------------------------------------------------------

pb.InstanceState stateToPb(InstanceState state) => switch (state) {
  InstanceState.notInstalled => pb.InstanceState.INSTANCE_STATE_NOT_INSTALLED,
  InstanceState.installing => pb.InstanceState.INSTANCE_STATE_INSTALLING,
  InstanceState.stopped => pb.InstanceState.INSTANCE_STATE_STOPPED,
  InstanceState.starting => pb.InstanceState.INSTANCE_STATE_STARTING,
  InstanceState.running => pb.InstanceState.INSTANCE_STATE_RUNNING,
  InstanceState.stopping => pb.InstanceState.INSTANCE_STATE_STOPPING,
  InstanceState.updating => pb.InstanceState.INSTANCE_STATE_UPDATING,
  InstanceState.error => pb.InstanceState.INSTANCE_STATE_ERROR,
};

pb.Protocol protocolToPb(plugin.PortProtocol protocol) => switch (protocol) {
  plugin.PortProtocol.udp => pb.Protocol.PROTOCOL_UDP,
  plugin.PortProtocol.tcp => pb.Protocol.PROTOCOL_TCP,
  plugin.PortProtocol.both => pb.Protocol.PROTOCOL_BOTH,
};

/// The wire form of [instance]. With [includeSettings] false the settings
/// document is left out and `settings_omitted` is set (a slim delta, design
/// D15).
///
/// `revision` is always 0 (design D24).
pb.Instance instanceToPb(Instance instance, {bool includeSettings = true}) {
  return pb.Instance(
    id: instance.id,
    name: instance.name,
    pluginId: instance.pluginId,
    pluginVersion: instance.pluginVersion,
    directory: instance.directory,
    state: stateToPb(instance.state),
    stateReason: instance.stateReason,
    ports: [
      for (final port in instance.ports)
        pb.Port(
          name: port.name,
          number: port.number,
          protocol: protocolToPb(port.protocol),
          purpose: port.purpose.name,
          exposed: port.exposed,
        ),
    ],
    settings: includeSettings
        ? settingsDocument(instance.settings, instance.schemaVersion ?? 0)
        : null,
    settingsOmitted: !includeSettings,
    steamAccountId: instance.steamAccountId,
    restartPolicy: instance.restartPolicy,
    activeOperationId: instance.activeOperationId,
    queuedOperations: instance.queuedOperations,
    createdAt: timestamp(instance.createdAt),
    stateChangedAt: timestamp(instance.stateChangedAt),
    pid: instance.pid,
    health: switch (instance.health) {
      InstanceHealth.unspecified => pb.Health.HEALTH_UNSPECIFIED,
      InstanceHealth.ok => pb.Health.HEALTH_OK,
      InstanceHealth.unknown => pb.Health.HEALTH_UNKNOWN,
    },
    revision: Int64.ZERO,
    restartRequired: instance.restartRequired,
    autostart: instance.autostart,
    settingsInvalid: instance.settingsInvalid,
  );
}

pb.JsonDocument settingsDocument(Map<String, Object?> values, int version) =>
    pb.JsonDocument(json: jsonEncode(values), schemaVersion: version);

/// The JSON object in [document]. An unset or empty document is `{}` unless
/// [required]. Text that is not JSON fails `invalid_json` with the position.
Map<String, Object?> parseDocument(
  pb.JsonDocument? document,
  String field, {
  bool required = false,
}) {
  if (document == null || document.json.trim().isEmpty) {
    if (!required) return {};
    throw YaguraException(
      'invalid_json',
      '$field is required',
      details: {'field': field},
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(document.json);
  } on FormatException catch (e) {
    final offset = e.offset;
    final position = offset == null ? '' : _position(document.json, offset);
    throw YaguraException(
      'invalid_json',
      '$field is not valid JSON$position: ${e.message}',
      details: {'field': field, 'offset': ?offset},
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw YaguraException(
      'invalid_json',
      '$field must be a JSON object',
      details: {'field': field},
    );
  }
  return decoded;
}

String _position(String text, int offset) {
  final clamped = offset.clamp(0, text.length);
  final before = text.substring(0, clamped);
  final line = '\n'.allMatches(before).length + 1;
  final column = clamped - (before.lastIndexOf('\n') + 1) + 1;
  return ' at line $line, column $column (offset $offset)';
}

/// Port overrides by name from the request's ports.
Map<String, int> portOverrides(Iterable<pb.Port> ports) => {
  for (final port in ports) port.name: port.number,
};

// ---- operations -------------------------------------------------------------

pb.OperationStatus operationStatusToPb(
  OperationStatus status,
) => switch (status) {
  OperationStatus.queued => pb.OperationStatus.OPERATION_STATUS_QUEUED,
  OperationStatus.running => pb.OperationStatus.OPERATION_STATUS_RUNNING,
  OperationStatus.waitingForInput =>
    pb.OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT,
  OperationStatus.succeeded => pb.OperationStatus.OPERATION_STATUS_SUCCEEDED,
  OperationStatus.failed => pb.OperationStatus.OPERATION_STATUS_FAILED,
  OperationStatus.cancelled => pb.OperationStatus.OPERATION_STATUS_CANCELLED,
  OperationStatus.interrupted =>
    pb.OperationStatus.OPERATION_STATUS_INTERRUPTED,
};

pb.Operation operationToPb(Operation operation) => pb.Operation(
  id: operation.id,
  instanceId: operation.instanceId,
  kind: operation.kind.wireName,
  status: operationStatusToPb(operation.status),
  queuePosition: operation.queuePosition,
  currentStep: operation.currentStep,
  createdAt: timestamp(operation.createdAt),
  startedAt: operation.startedAt == null
      ? null
      : timestamp(operation.startedAt!),
  endedAt: operation.endedAt == null ? null : timestamp(operation.endedAt!),
  resultReason: operation.resultReason,
  resultMessage: operation.resultMessage,
  warnings: operation.warnings,
  lastSequence: Int64(operation.lastSequence),
);

pb.OperationEvent operationEventToPb(OperationEvent event) {
  final at = timestamp(event.at);
  final sequence = Int64(event.sequence);
  return switch (event) {
    StepStartedEvent(:final step) => pb.OperationEvent(
      sequence: sequence,
      at: at,
      stepStarted: pb.StepStarted(step: step),
    ),
    ProgressEvent(
      :final step,
      :final percent,
      :final bytesDone,
      :final bytesTotal,
    ) =>
      pb.OperationEvent(
        sequence: sequence,
        at: at,
        progress: pb.Progress(
          step: step,
          percent: percent,
          bytesDone: Int64(bytesDone),
          bytesTotal: Int64(bytesTotal),
        ),
      ),
    LogEvent(:final text) => pb.OperationEvent(
      sequence: sequence,
      at: at,
      log: pb.LogLine(text: text),
    ),
    FinishedEvent(:final operation) => pb.OperationEvent(
      sequence: sequence,
      at: at,
      finished: operationToPb(operation),
    ),
    EventsDroppedEvent(:final fromSequence, :final toSequence) =>
      pb.OperationEvent(
        sequence: sequence,
        at: at,
        eventsDropped: pb.EventsDropped(
          fromSequence: Int64(fromSequence),
          toSequence: Int64(toSequence),
        ),
      ),
    SnapshotEvent(:final operation) => pb.OperationEvent(
      sequence: sequence,
      at: at,
      snapshot: operationToPb(operation),
    ),
  };
}

// ---- snapshots --------------------------------------------------------------

pb.Snapshot snapshotToPb(SnapshotInfo snapshot) => pb.Snapshot(
  id: snapshot.id,
  instanceId: snapshot.instanceId,
  instanceName: snapshot.instanceName,
  reason: snapshot.reason,
  createdAt: timestamp(snapshot.createdAt),
  sizeBytes: Int64(snapshot.sizeBytes),
);

// ---- logs -------------------------------------------------------------------

pb.LogEntry logEntryToPb(LogEntry entry) => pb.LogEntry(
  source: entry.source,
  sequence: Int64(entry.sequence),
  receivedAt: timestamp(entry.receivedAt),
  text: entry.text,
);

pb.LogSource logSourceToPb(LogSourceStatus status) => pb.LogSource(
  name: status.name,
  kind: status.kind.wireName,
  status: status.status,
  currentFile: status.currentFile,
  encoding: status.encoding.wireName,
  lastError: status.lastError,
);
