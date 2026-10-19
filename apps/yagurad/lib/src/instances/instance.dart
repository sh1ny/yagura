import 'package:yagura_plugin/yagura_plugin.dart';

/// The eight instance states (`openspec/architecture.md`, mirrors
/// `InstanceState` in `instances.proto`).
enum InstanceState {
  notInstalled('not_installed'),
  installing('installing'),
  stopped('stopped'),
  starting('starting'),
  running('running'),
  stopping('stopping'),
  updating('updating'),
  error('error');

  const InstanceState(this.wireName);

  final String wireName;

  static InstanceState fromWire(String name) =>
      values.firstWhere((s) => s.wireName == name);
}

/// Whether the start-time health check passed (`Health` in
/// `instances.proto`).
enum InstanceHealth { unspecified, ok, unknown }

/// Error reasons that have their own exits (design D17). Any other reason on
/// an `error` instance is an update failure, whose exits are the same as
/// `update_interrupted`.
const crashLoopReason = 'crash_loop';
const updateInterruptedReason = 'update_interrupted';
const restoreInterruptedReason = 'restore_interrupted';
const settingsInvalidReason = 'settings_invalid';
const pluginMissingReason = 'plugin_missing';
const runRecordRejectedReason = 'run_record_rejected';

/// The notice and warning of an instance whose directory could not be given
/// its permissions at the first service start (ADR 0015).
const aclMigrationFailedReason = 'acl_migration_failed';

/// A port of an instance with its resolved number.
class PortAssignment {
  const PortAssignment({
    required this.name,
    required this.number,
    required this.protocol,
    required this.purpose,
    required this.exposed,
  });

  final String name;
  final int number;
  final PortProtocol protocol;
  final PortPurpose purpose;
  final bool exposed;

  @override
  String toString() => '$name=$number/${protocol.name}';
}

/// An immutable view of an instance.
class Instance {
  const Instance({
    required this.id,
    required this.name,
    required this.pluginId,
    required this.pluginVersion,
    required this.directory,
    required this.state,
    required this.stateReason,
    required this.warning,
    required this.ports,
    required this.settings,
    required this.steamAccountId,
    required this.restartPolicy,
    required this.autostart,
    required this.restartRequired,
    required this.settingsInvalid,
    required this.activeOperationId,
    required this.queuedOperations,
    required this.createdAt,
    required this.stateChangedAt,
    required this.pid,
    this.revision = 1,
    this.schemaVersion,
    this.health = InstanceHealth.unspecified,
  });

  final String id;
  final String name;
  final String pluginId;
  final String pluginVersion;
  final String directory;
  final InstanceState state;

  /// Why the instance is in `error` (empty otherwise).
  final String stateReason;

  /// A warning kept after an Acknowledge (files may be inconsistent).
  final String warning;
  final List<PortAssignment> ports;

  /// Setting values; secrets as `{"secret": true, "set": false}`.
  final Map<String, Object?> settings;

  /// Version of the plugin settings schema the settings were validated
  /// against, when the plugin is loaded.
  final int? schemaVersion;
  final String steamAccountId;
  final String restartPolicy;
  final bool autostart;

  /// Settings changed since the running process started.
  final bool restartRequired;

  /// A running instance whose settings failed re-validation on reload.
  final bool settingsInvalid;
  final String activeOperationId;
  final int queuedOperations;
  final DateTime createdAt;
  final DateTime stateChangedAt;

  /// 0 when not running.
  final int pid;

  /// `unknown` when the instance runs but its health check did not pass
  /// within `start_timeout`; `unspecified` while it is not running.
  final InstanceHealth health;

  /// The configuration revision (design D12): starts at 1 and increments
  /// only on configuration changes, never on state, health, pid or queue
  /// changes.
  final int revision;

  Map<String, int> get portNumbers => {for (final p in ports) p.name: p.number};
}

/// A change to report on the instance stream.
sealed class InstanceEvent {
  const InstanceEvent();
}

class InstanceChanged extends InstanceEvent {
  const InstanceChanged(this.instance);
  final Instance instance;
}

class InstanceRemoved extends InstanceEvent {
  const InstanceRemoved(this.instanceId);
  final String instanceId;
}

/// `crashed`, `lost_while_daemon_down`, `install_interrupted`,
/// `update_interrupted`, `settings_invalid`, `instance_file_stale`... (the
/// kinds of `InstanceNotice` in `instances.proto`).
class InstanceNotice extends InstanceEvent {
  const InstanceNotice(
    this.instanceId,
    this.kind,
    this.message, {
    this.exitCode = 0,
    this.lastLogLines = const [],
  });
  final String instanceId;
  final String kind;
  final String message;

  /// The exit code of a `crashed` notice.
  final int exitCode;

  /// Up to the last 50 log lines of a `crashed` or `crash_loop` notice.
  final List<String> lastLogLines;

  @override
  String toString() => 'InstanceNotice($instanceId $kind: $message)';
}

class CreateInstanceRequest {
  const CreateInstanceRequest({
    required this.pluginId,
    required this.name,
    this.directory,
    this.settings = const {},
    this.ports = const {},
    this.steamAccountId,
    this.schemaVersion,
  });

  final String pluginId;
  final String name;

  /// Null or empty means `<data>/instances/<id>`.
  final String? directory;
  final Map<String, Object?> settings;

  /// Port number overrides by port name.
  final Map<String, int> ports;
  final String? steamAccountId;

  /// When set, must equal the plugin's current settings schema version.
  final int? schemaVersion;
}

class UpdateSettingsRequest {
  const UpdateSettingsRequest({
    required this.instanceId,
    required this.settings,
    this.ports,
    this.restartPolicy,
    this.steamAccountId,
    this.autostart,
    this.schemaVersion,
    this.expectedRevision,
  });

  final String instanceId;

  /// The revision the caller last read. Null skips the check (in-process
  /// callers); the API always passes it, and 0 fails `revision_required`.
  final int? expectedRevision;

  /// When set, must equal the plugin's current settings schema version, so a
  /// form opened before a plugin reload cannot write stale fields.
  final int? schemaVersion;

  /// The full non-secret settings document.
  final Map<String, Object?> settings;

  /// Port overrides by name; null leaves ports unchanged.
  final Map<String, int>? ports;
  final String? restartPolicy;

  /// Null leaves it unchanged; empty unlinks.
  final String? steamAccountId;
  final bool? autostart;
}
