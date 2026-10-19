import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../errors.dart';
import '../files/files.dart';
import '../hooks/hooks.dart';
import '../host/acl_layout.dart';
import '../host/data_directory.dart';
import '../host/secret_store.dart';
import '../operations/operations.dart';
import '../plugins/plugin_registry.dart';
import '../process/process.dart';
import '../snapshots/snapshots.dart';
import '../steam/steam.dart';
import 'health_check.dart';
import 'instance.dart';
import 'instance_acls.dart';
import 'instance_file.dart';
import 'instance_roots.dart';
import 'instance_store.dart';
import 'lifecycle.dart';
import 'restart_policy.dart';

/// The instance manager: sole writer of instances, settings, ports and the
/// instance state machine (design D17, D21, D25). Lifecycle work runs as
/// operations of the [OperationRunner]; the steps themselves are in
/// [Lifecycle].
class InstanceManager {
  InstanceManager({
    required this.store,
    required this.secrets,
    required this.runner,
    required this.registry,
    required this.dataDirectory,
    required this.roots,
    required this.apiPort,
    required this.os,
    required this.processHost,
    required this.steam,
    required this.hooks,
    required this.snapshotter,
    required this.runs,
    this.acls,
    HealthEvaluator? healthEvaluator,
    this.restartDelay = const Duration(seconds: 5),
    this.autostartInterval = const Duration(seconds: 10),
    this.pendingRunWait = const Duration(seconds: 10),
    Future<void> Function(String directory)? removeDirectory,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now,
       healthEvaluator = healthEvaluator ?? HealthEvaluator(),
       removeDirectory = removeDirectory ?? _removeTree {
    lifecycle = Lifecycle(this);
    for (final record in store.loadAll()) {
      _records[record.id] = record;
    }
  }

  final InstanceStore store;

  /// Secret setting values, one secret per (instance, setting).
  final SecretStore secrets;
  final OperationRunner runner;
  final PluginRegistry registry;
  final DataDirectory dataDirectory;

  /// The places instance directories may live.
  final HostRoots roots;

  /// The daemon API port, which no instance may use.
  final int apiPort;

  /// `windows` or `linux`.
  final String os;
  final ProcessHost processHost;
  final SteamService steam;
  final HookHost hooks;
  final Snapshotter snapshotter;

  /// Run records and crash timestamps; the supervisor in this class and in
  /// [Lifecycle] is their only writer.
  final RunStore runs;

  /// Writes the instance DACL at create and for older instances; null in
  /// development mode, which manages no ACLs.
  final InstanceAcls? acls;
  final HealthEvaluator healthEvaluator;

  /// How long after a crash the instance is started again.
  final Duration restartDelay;

  /// Gap between autostarted instances (design D14).
  final Duration autostartInterval;

  /// How long recovery waits for a live relay to record its server.
  final Duration pendingRunWait;

  /// The last lines of an instance's log, for crash notices; set by the
  /// daemon once the log hub exists.
  Future<List<String>> Function(String instanceId, int lines)? logTail;

  /// Opens a `log_match` watch on [source] of an instance (set by the daemon
  /// once the log hub exists).
  Future<LogMatchWatch> Function(
    String instanceId,
    String source,
    RegExp pattern,
  )?
  logMatchWatch;

  /// Removes an instance directory after delete; a seam so tests can stop the
  /// daemon in the middle of it.
  final Future<void> Function(String directory) removeDirectory;
  final DateTime Function() clock;
  late final Lifecycle lifecycle;

  final _records = <String, InstanceRecord>{};
  final _events = StreamController<InstanceEvent>.broadcast();
  final _pluginsReloaded = StreamController<void>.broadcast();
  final _recoveryNotices = <InstanceNotice>[];
  final _restartTimers = <String, Timer>{};
  var _createTail = Future<void>.value();
  var _closed = false;

  static final _random = Random.secure();

  static Future<void> _removeTree(String directory) async =>
      InstanceFs(directory).deleteTree('');

  // ---- reading ------------------------------------------------------------

  Stream<InstanceEvent> get events => _events.stream;

  /// Notices raised while recovering at startup.
  List<InstanceNotice> get recoveryNotices =>
      List.unmodifiable(_recoveryNotices);

  List<Instance> list() => [for (final r in _records.values) view(r)];

  Instance? find(String id) {
    final record = _records[id];
    return record == null ? null : view(record);
  }

  Instance get(String id) => view(_require(id));

  InstanceRecord _require(String id) =>
      _records[id] ??
      (throw YaguraException(
        'instance_not_found',
        'there is no instance $id',
        details: {'instanceId': id},
      ));

  /// The record an operation works on; an instance deleted while the
  /// operation was queued makes it fail `invalid_state`.
  InstanceRecord recordForOperation(String id) =>
      _records[id] ??
      (throw YaguraException(
        'invalid_state',
        'instance $id no longer exists',
        details: {'instanceId': id},
      ));

  /// An immutable view of [record], with secrets as placeholders.
  Instance view(InstanceRecord record) {
    final plugin = registry.find(record.pluginId);
    return Instance(
      id: record.id,
      name: record.name,
      pluginId: record.pluginId,
      pluginVersion: record.pluginVersion,
      directory: record.directory,
      state: record.state,
      stateReason: record.stateReason,
      warning: record.warning,
      ports: List.unmodifiable(record.ports),
      settings: withSecretPlaceholders(
        plugin?.manifest.settings ?? const {},
        record.settings,
        const {'secret': true, 'set': false},
        setSecrets: setSecretsOf(record),
      ),
      schemaVersion: plugin?.schemaVersion,
      steamAccountId: record.steamAccountId,
      restartPolicy: record.restartPolicy,
      autostart: record.autostart,
      restartRequired: record.restartRequired,
      settingsInvalid: record.settingsInvalid,
      activeOperationId: runner.activeOperationId(record.id) ?? '',
      queuedOperations: runner.queuedCount(record.id),
      createdAt: record.createdAt,
      stateChangedAt: record.stateChangedAt,
      pid: record.server?.pid ?? 0,
      health: record.health,
      revision: record.revision,
    );
  }

  /// The top-level secret settings of [record] that hold a value.
  Set<String> setSecretsOf(InstanceRecord record) {
    final defs = registry.find(record.pluginId)?.manifest.settings;
    if (defs == null) return const {};
    return {
      for (final MapEntry(key: name, value: def) in defs.entries)
        if (def.type == SettingType.secret &&
            secrets.contains(secretIdFor(record.id, name)))
          name,
    };
  }

  // ---- create -------------------------------------------------------------

  /// Creates an instance. Creates are serialised, so the port and directory
  /// checks see every earlier create.
  Future<Instance> create(CreateInstanceRequest request) {
    final result = _createTail.then((_) => _create(request));
    _createTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Instance _create(CreateInstanceRequest request) {
    final plugin =
        registry.find(request.pluginId) ??
        (throw YaguraException(
          'plugin_missing',
          'plugin ${request.pluginId} is not loaded',
          details: {'pluginId': request.pluginId},
        ));
    final manifest = plugin.manifest;
    if (!manifest.executables.containsKey(os)) {
      throw YaguraException(
        'unsupported_platform',
        'plugin ${manifest.id} has no executable for $os '
            '(it declares: ${manifest.platforms.join(', ')})',
        details: {'pluginId': manifest.id, 'os': os},
      );
    }
    final name = request.name.trim();
    if (name.isEmpty) {
      throw _settingsInvalid([const SettingError('name', 'must not be empty')]);
    }
    _checkSchemaVersion(request.schemaVersion, plugin);

    final settings = _validated(manifest, request.settings);
    final ports = _resolvePorts(manifest, request.ports);
    final id = _newId();
    _checkPorts(name, ports, excluding: null);
    final directory = _checkDirectory(request.directory, id);

    final created = ConfinedFs.create(directory);
    var aclLayout = 0;
    if (acls case final acls?) {
      try {
        aclLayout = acls.apply(directory);
      } on Object catch (e) {
        if (created) InstanceFs(directory).deleteTree('');
        if (e is AclLinkFound) {
          throw confinedViolation(
            e.path,
            '${e.kind} in the new instance directory',
          );
        }
        rethrow;
      }
    }
    final now = clock();
    final record = InstanceRecord(
      id: id,
      name: name,
      pluginId: manifest.id,
      pluginVersion: manifest.version,
      directory: directory,
      state: InstanceState.notInstalled,
      settings: settings,
      ports: ports,
      steamAccountId: request.steamAccountId ?? '',
      createdAt: now,
      stateChangedAt: now,
    );
    try {
      store.save(record);
    } on Object {
      if (created) InstanceFs(directory).deleteTree('');
      rethrow;
    }
    if (aclLayout != 0) store.setAclLayout(id, aclLayout);
    _records[id] = record;
    writeInstanceFile(record);
    _emitChanged(record);
    return view(record);
  }

  /// Gives every instance whose ACL layout is below the current one the
  /// instance DACL and the inherited entries (once, at the first service
  /// start after M1 or a development daemon). A link met leaves the layout
  /// unchanged and raises warning `acl_migration_failed` naming it; the
  /// instance's launches fail until the admin removes the link. Returns the
  /// messages of the instances that could not be migrated.
  List<String> migrateInstanceAcls() {
    final writer = acls;
    if (writer == null) return const [];
    final failed = <String>[];
    for (final record in _records.values.toList()) {
      if (store.aclLayout(record.id) >= currentAclLayout) continue;
      if (_migrateAcls(writer, record) case final message?) {
        _recoveryNotice(record, aclMigrationFailedReason, message);
        failed.add(message);
      }
    }
    return failed;
  }

  /// Gives [record] its permissions; returns why it could not (and keeps that
  /// as the instance's warning), or null.
  String? _migrateAcls(InstanceAcls writer, InstanceRecord record) {
    try {
      final reached = writer.apply(record.directory);
      if (reached != 0) store.setAclLayout(record.id, reached);
      return null;
    } on Object catch (e) {
      final path = e is AclLinkFound
          ? InstanceFs(record.directory).absolute(e.path)
          : record.directory;
      final message = e is AclLinkFound
          ? 'instance "${record.name}": $path is ${e.kind}; remove '
                '${e.hardLinks ? 'the other names (fsutil hardlink list)' : 'it'}'
                ' so the instance can be given its permissions'
          : 'instance "${record.name}": its permissions could not be set: '
                '${e is YaguraException ? e.message : e}';
      record.warning = message;
      store.save(record);
      return message;
    }
  }

  /// Refuses a launch of an instance whose permissions are not in place (design
  /// D6: "that instance's launches fail until the link is removed"). The
  /// migration is tried again first, so removing the link is enough; a
  /// development daemon (no ACL writer) has nothing to check.
  void requireAclLayout(InstanceRecord record) {
    final writer = acls;
    if (writer == null || store.aclLayout(record.id) >= currentAclLayout) {
      return;
    }
    final message = _migrateAcls(writer, record);
    if (message == null) return;
    throw YaguraException(
      aclMigrationFailedReason,
      message,
      details: {'instanceId': record.id},
    );
  }

  // ---- settings -----------------------------------------------------------

  /// Refuses settings made for another version of the plugin's settings
  /// schema.
  void _checkSchemaVersion(int? version, LoadedPlugin plugin) {
    if (version == null || version == plugin.schemaVersion) return;
    throw YaguraException(
      'schema_version_mismatch',
      'the settings were made for schema version $version, '
          'the plugin is at ${plugin.schemaVersion}',
      details: {'schemaVersion': plugin.schemaVersion},
    );
  }

  /// Saves settings and ports. Secret values are refused
  /// (`secret_via_set_secret`); an omitted secret or its placeholder leaves
  /// the stored value unchanged.
  Instance updateSettings(UpdateSettingsRequest request) {
    final record = _require(request.instanceId);
    _checkRevision(record, request.expectedRevision);
    final plugin = _requirePlugin(record);
    final manifest = plugin.manifest;
    _checkSchemaVersion(request.schemaVersion, plugin);
    final settings = _validated(manifest, request.settings);

    var ports = record.ports;
    if (request.ports case final overrides?) {
      final current = {
        for (final port in record.ports)
          if (manifest.ports.any((d) => d.name == port.name && !d.isDerived))
            port.name: port.number,
      };
      ports = _resolvePorts(manifest, {...current, ...overrides});
    }
    _checkPorts(record.name, ports, excluding: record.id);

    final policy = request.restartPolicy;
    if (policy != null && policy != 'never' && policy != 'on_crash') {
      throw _settingsInvalid([
        SettingError(
          'restart_policy',
          'must be never or on_crash (got $policy)',
        ),
      ]);
    }

    record
      ..settings = settings
      ..ports = ports
      ..pluginVersion = manifest.version
      ..settingsInvalid = false
      ..restartPolicy = policy ?? record.restartPolicy
      ..autostart = request.autostart ?? record.autostart
      ..steamAccountId = request.steamAccountId ?? record.steamAccountId;
    if (record.state == InstanceState.running ||
        record.state == InstanceState.starting) {
      record.restartRequired = true;
    }
    if (record.state == InstanceState.error &&
        record.stateReason == settingsInvalidReason) {
      _applyState(record, InstanceState.stopped);
    }
    _commit(record, revisedFrom: record.revision);
    return view(record);
  }

  /// Stores [value] as the secret setting [key] of instance [id] (design
  /// D3). The value is never returned: the view reports `set: true`. A store
  /// that refuses the write fails `secret_store_unavailable` and leaves the
  /// previous value.
  Instance setSecret(
    String id,
    String key,
    String value, {
    int? expectedRevision,
  }) {
    final record = _require(id);
    _checkRevision(record, expectedRevision);
    _requireSecretSetting(record, key);
    final secretId = secretIdFor(id, key);
    final bytes = Uint8List.fromList(utf8.encode(value));
    Uint8List? previous;
    try {
      previous = secrets.get(secretId);
    } on YaguraException {
      // A value that cannot be opened is replaced, and counts as changed.
    }
    final changed =
        previous == null ||
        previous.length != bytes.length ||
        !_sameBytes(previous, bytes);
    secrets.put(secretId, bytes, instanceId: id, setting: key);
    return _secretChanged(record, changed: changed);
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Clears the secret setting [key] of instance [id].
  Instance deleteSecret(String id, String key, {int? expectedRevision}) {
    final record = _require(id);
    _checkRevision(record, expectedRevision);
    _requireSecretSetting(record, key);
    final secretId = secretIdFor(id, key);
    final changed = secrets.contains(secretId);
    secrets.delete(secretId);
    return _secretChanged(record, changed: changed);
  }

  /// A running server keeps the old value until it restarts, so a change of
  /// the stored value marks the instance restart-required; a write of the
  /// value already stored does not.
  Instance _secretChanged(InstanceRecord record, {required bool changed}) {
    if (changed &&
        (record.state == InstanceState.running ||
            record.state == InstanceState.starting)) {
      record.restartRequired = true;
    }
    _commit(record, revisedFrom: record.revision);
    return view(record);
  }

  /// Fails `revision_required` when [expected] is 0 (proto3 omitted) and
  /// `revision_conflict` with the current revision when it is stale (design
  /// D12). Null skips the check, for in-process callers. The check runs
  /// before any change, so a refused call leaves the record untouched.
  void _checkRevision(InstanceRecord record, int? expected) {
    if (expected == null) return;
    if (expected <= 0) {
      throw YaguraException(
        'revision_required',
        'the call needs expected_revision, the revision the caller last read '
            '(instance "${record.name}" is at ${record.revision})',
        details: {'instanceId': record.id},
      );
    }
    if (expected != record.revision) {
      throw revisionConflict(record.id, record.revision);
    }
  }

  void _requireSecretSetting(InstanceRecord record, String key) {
    final def = _requirePlugin(record).manifest.settings[key];
    if (def == null || def.type != SettingType.secret) {
      throw _settingsInvalid([SettingError(key, 'is not a secret setting')]);
    }
  }

  /// Fails `secret_required` naming the `required` secret settings of
  /// [record] that are unset.
  void requireSecrets(InstanceRecord record) {
    final defs = registry.find(record.pluginId)?.manifest.settings;
    if (defs == null) return;
    final set = setSecretsOf(record);
    final missing = [
      for (final MapEntry(key: name, value: def) in defs.entries)
        if (def.type == SettingType.secret &&
            def.required &&
            !set.contains(name))
          name,
    ];
    if (missing.isEmpty) return;
    throw YaguraException(
      'secret_required',
      'the required secret ${missing.join(', ')} is not set; set it with '
          'SetSecret before starting',
      details: {'instanceId': record.id, 'settings': missing.join(', ')},
    );
  }

  Map<String, Object?> _validated(
    PluginManifest manifest,
    Map<String, Object?> input,
  ) {
    final validation = validateSettings(manifest, input);
    if (validation.isValid) return validation.values;
    final secret = validation.errors.where(
      (e) => e.code == 'secret_via_set_secret',
    );
    if (secret.isNotEmpty) {
      throw YaguraException(
        'secret_via_set_secret',
        'a secret value is set with SetSecret, not in the settings: '
            '${secret.map((e) => e.path).join(', ')}',
        details: {
          'fields': [for (final e in secret) e.path],
        },
      );
    }
    throw _settingsInvalid(validation.errors);
  }

  YaguraException _settingsInvalid(List<SettingError> errors) =>
      YaguraException(
        settingsInvalidReason,
        'invalid settings: ${errors.join('; ')}',
        details: {
          'fieldViolations': [
            for (final e in errors) {'field': e.path, 'description': e.message},
          ],
        },
      );

  // ---- ports and directories ----------------------------------------------

  List<PortAssignment> _resolvePorts(
    PluginManifest manifest,
    Map<String, int> overrides,
  ) {
    final Map<String, int> numbers;
    try {
      numbers = resolvePorts(manifest, overrides);
    } on ArgumentError catch (e) {
      throw _settingsInvalid([
        SettingError('ports.${e.name ?? ''}', '${e.message}'),
      ]);
    }
    return [
      for (final decl in manifest.ports)
        PortAssignment(
          name: decl.name,
          number: numbers[decl.name]!,
          protocol: decl.protocol,
          purpose: decl.purpose,
          exposed: decl.exposed,
        ),
    ];
  }

  bool _overlap(PortProtocol a, PortProtocol b) =>
      a == PortProtocol.both || b == PortProtocol.both || a == b;

  void _checkPorts(
    String name,
    List<PortAssignment> ports, {
    required String? excluding,
  }) {
    for (final port in ports) {
      if (port.number == apiPort) {
        throw YaguraException(
          'port_conflict',
          'port ${port.name} of "$name" would use ${port.number}, the port '
              'of the daemon API',
          details: {
            'port': port.number,
            'portName': port.name,
            'daemonApi': true,
          },
        );
      }
    }
    for (final other in _records.values) {
      if (other.id == excluding) continue;
      for (final theirs in other.ports) {
        for (final mine in ports) {
          if (mine.number == theirs.number &&
              _overlap(mine.protocol, theirs.protocol)) {
            throw YaguraException(
              'port_conflict',
              'port ${mine.name} (${mine.number}/${mine.protocol.name}) of '
                  '"$name" collides with port ${theirs.name} of '
                  '"${other.name}"',
              details: {
                'port': mine.number,
                'portName': mine.name,
                'conflictingInstance': other.name,
                'conflictingInstanceId': other.id,
                'conflictingPortName': theirs.name,
              },
            );
          }
        }
      }
    }
  }

  /// The instance directory: `<data>/instances/<id>` by default, or a path
  /// strictly under `<data>/instances` or a root an administrator added with
  /// `yagurad roots add` (design D5, D21) that overlaps no other instance.
  String _checkDirectory(String? requested, String id) {
    final root = p.normalize(p.absolute(dataDirectory.instancesPath));
    if (requested == null || requested.isEmpty) return p.join(root, id);
    Never refuse(String why) => throw YaguraException(
      'directory_not_allowed',
      'directory $requested is not allowed: $why',
      details: {'path': requested},
    );
    // The real name of the folder, with Windows' reading of the path applied:
    // `<root>\...` is the root, a short name or another case is the same
    // folder, and a link on the way leads elsewhere. A path Windows would
    // rewrite is refused.
    final String directory;
    try {
      directory = roots.canonical(requested);
    } on FormatException catch (e) {
      refuse(e.message);
    }
    if (!roots.allows(directory)) {
      refuse(
        'instances live under ${[for (final r in roots.list()) r.path].join(', ')}',
      );
    }
    for (final other in _records.values) {
      final theirs = _canonicalOf(other.directory);
      bool same(String a, String b) => a.toLowerCase() == b.toLowerCase();
      bool within(String parent, String child) =>
          p.isWithin(parent.toLowerCase(), child.toLowerCase());
      if (same(directory, theirs) ||
          within(theirs, directory) ||
          within(directory, theirs)) {
        refuse('it overlaps instance "${other.name}" at ${other.directory}');
      }
    }
    return directory;
  }

  String _canonicalOf(String directory) {
    try {
      return roots.canonical(directory);
    } on FormatException {
      return p.normalize(p.absolute(directory));
    }
  }

  String _newId() {
    String hex() =>
        [for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16)]
            .join();
    var id = 'inst-${hex()}';
    while (_records.containsKey(id)) {
      id = 'inst-${hex()}';
    }
    return id;
  }

  // ---- lifecycle requests -------------------------------------------------

  Operation install(String id, {bool validateFiles = false}) {
    final record = _guarded(id, OperationKind.install);
    return runner.enqueue(
      instanceId: id,
      kind: OperationKind.install,
      body: (context) =>
          lifecycle.install(context, record.id, validate: validateFiles),
    );
  }

  Operation update(
    String id, {
    bool skipSnapshot = false,
    bool validateFiles = false,
  }) {
    final record = _guarded(id, OperationKind.update);
    if (record.state == InstanceState.running) requireSecrets(record);
    return runner.enqueue(
      instanceId: id,
      kind: OperationKind.update,
      body: (context) => lifecycle.update(
        context,
        record.id,
        kind: OperationKind.update,
        validate: validateFiles,
        skipSnapshot: skipSnapshot,
      ),
    );
  }

  Operation validate(String id) {
    final record = _guarded(id, OperationKind.validate);
    if (record.state == InstanceState.running) requireSecrets(record);
    return runner.enqueue(
      instanceId: id,
      kind: OperationKind.validate,
      body: (context) => lifecycle.update(
        context,
        record.id,
        kind: OperationKind.validate,
        validate: true,
        skipSnapshot: false,
      ),
    );
  }

  Operation start(String id) {
    final record = _guarded(id, OperationKind.start);
    requireSecrets(record);
    return runner.enqueue(
      instanceId: id,
      kind: OperationKind.start,
      body: (context) => lifecycle.start(context, record.id),
    );
  }

  Operation stop(String id, {bool force = false}) {
    final record = _guarded(id, OperationKind.stop);
    cancelRestart(id);
    return runner.enqueue(
      instanceId: id,
      kind: OperationKind.stop,
      body: (context) => lifecycle.stop(context, record.id, force: force),
    );
  }

  Operation restart(String id) {
    final record = _guarded(id, OperationKind.restart);
    requireSecrets(record);
    return runner.enqueue(
      instanceId: id,
      kind: OperationKind.restart,
      body: (context) => lifecycle.restart(context, record.id),
    );
  }

  /// Deletes the instance as an operation on its queue (design D25). A wrong
  /// confirmation fails before an operation exists.
  Operation delete(
    String id, {
    bool deleteFiles = false,
    String confirmName = '',
    int? expectedRevision,
  }) {
    final record = _require(id);
    _checkRevision(record, expectedRevision);
    if (deleteFiles && confirmName != record.name) {
      throw YaguraException(
        'confirmation_mismatch',
        'deleting the files needs the instance name "${record.name}" as '
            'confirmation',
        details: {'instanceId': id},
      );
    }
    if (runner.hasActive(id)) {
      throw YaguraException(
        'invalid_state',
        'instance "${record.name}" has another operation queued or running; '
            'delete is refused until it ends',
        details: {'instanceId': id},
      );
    }
    checkAllowed(record, OperationKind.delete, execution: false);
    if (deleteFiles) requirePlugin(record);
    return _revised(
      record,
      () => runner.enqueue(
        instanceId: id,
        kind: OperationKind.delete,
        body: (context) =>
            lifecycle.delete(context, record.id, deleteFiles: deleteFiles),
      ),
    );
  }

  // ---- snapshots ----------------------------------------------------------

  /// The instance's snapshots, newest first.
  List<SnapshotInfo> listSnapshots(String id) {
    _require(id);
    return snapshotter.list(id);
  }

  /// The `pre_delete` snapshots of instances that no longer exist.
  List<SnapshotInfo> listOrphanSnapshots() =>
      snapshotter.listOrphans(_records.keys.toSet());

  /// Removes expired snapshots of deleted instances (startup, design D12).
  Future<void> purgeExpiredSnapshots() =>
      snapshotter.purgeExpired(_records.keys.toSet());

  /// Replaces the instance's data paths with a snapshot, as an operation on
  /// its queue (design D12). Allowed from `stopped` and from
  /// `error: restore_interrupted`.
  Operation restoreSnapshot(
    String id,
    String snapshotId, {
    int? expectedRevision,
  }) {
    _checkRevision(_require(id), expectedRevision);
    final record = _guarded(id, OperationKind.restore);
    if (!snapshotter.list(id).any((s) => s.id == snapshotId)) {
      throw YaguraException(
        'snapshot_not_found',
        'instance "${record.name}" has no snapshot $snapshotId',
        details: {'instanceId': id, 'snapshotId': snapshotId},
      );
    }
    return _revised(
      record,
      () => runner.enqueue(
        instanceId: id,
        kind: OperationKind.restore,
        body: (context) =>
            lifecycle.restoreSnapshot(context, record.id, snapshotId),
      ),
    );
  }

  /// Accepts an operation that changes the instance's configuration: the
  /// revision is incremented in a transaction of its own, then [enqueue]
  /// creates the operation. When [enqueue] refuses (`queue_full`), the
  /// increment is undone, so a refused call changes nothing.
  Operation _revised(InstanceRecord record, Operation Function() enqueue) {
    final before = record.revision;
    store.setRevision(record, before, before + 1);
    try {
      final operation = enqueue();
      _emitChanged(record);
      return operation;
    } on Object {
      store.setRevision(record, before + 1, before);
      rethrow;
    }
  }

  /// Clears an `error` after the cause was addressed (design D17).
  Instance acknowledge(String id) {
    final record = _require(id);
    if (record.state != InstanceState.error ||
        record.stateReason == settingsInvalidReason ||
        record.stateReason == pluginMissingReason) {
      throw YaguraException(
        'invalid_state',
        record.state == InstanceState.error
            ? 'Acknowledge does not apply to error ${record.stateReason}; '
                  '${record.stateReason == settingsInvalidReason ? 'save valid settings' : 'reload the plugin'}'
            : 'instance "${record.name}" is ${record.state.wireName}, not in error',
        details: {'instanceId': id},
      );
    }
    if (record.stateReason == restoreInterruptedReason) {
      snapshotter.clearInterruptedRestore(record.id);
    }
    if (record.stateReason == crashLoopReason) runs.clearCrashes(record.id);
    if (record.stateReason == runRecordRejectedReason) {
      // The run record named no verified server; nothing is terminated. The
      // run is over for the daemon, and the warning keeps the relay PID.
      for (final run in runs.unresolvedFor(record.id)) {
        runs.markEnded(run.runId, at: clock(), reason: runRecordRejectedReason);
      }
      record
        ..runId = ''
        ..server = null;
    }
    final warning = switch (record.stateReason) {
      crashLoopReason => '',
      runRecordRejectedReason =>
        record.warning.isEmpty
            ? 'the run record was rejected: no verified server'
            : record.warning,
      restoreInterruptedReason =>
        'the restore was interrupted: data paths may be mixed',
      _ => 'the update did not finish: files may be inconsistent',
    };
    _applyState(record, InstanceState.stopped);
    record.warning = warning;
    _commit(record);
    return view(record);
  }

  /// At request time an idle instance is checked against the state machine;
  /// when operations are queued or running, the check happens when the
  /// operation reaches the head of the queue.
  InstanceRecord _guarded(String id, OperationKind kind) {
    final record = _require(id);
    if (!runner.hasActive(id)) {
      checkAllowed(record, kind, execution: false);
    }
    return record;
  }

  /// Whether [kind] is allowed in the instance's state (design D17); throws
  /// `invalid_state` or a more specific reason otherwise. At [execution] time
  /// the specific reasons become `invalid_state`, and Stop never fails.
  void checkAllowed(
    InstanceRecord record,
    OperationKind kind, {
    required bool execution,
  }) {
    final state = record.state;
    final reason = record.stateReason;
    final described = state == InstanceState.error
        ? 'error ($reason)'
        : state.wireName;
    Never refuse(String specific, String why) => throw YaguraException(
      execution ? 'invalid_state' : specific,
      'instance "${record.name}" is $described: $why',
      details: {'instanceId': record.id, 'state': state.wireName},
    );

    switch (kind) {
      case OperationKind.install:
        if (state != InstanceState.notInstalled) {
          refuse('invalid_state', 'Install needs not_installed');
        }
      case OperationKind.update || OperationKind.validate:
        final ok =
            state == InstanceState.stopped ||
            state == InstanceState.running ||
            record.isUpdateFailure;
        if (!ok) {
          if (state == InstanceState.notInstalled) {
            refuse('not_installed', '${kind.name} needs an installed server');
          }
          refuse('invalid_state', '${kind.name} is not allowed');
        }
      case OperationKind.start:
        if (record.settingsInvalid) {
          refuse(
            'invalid_state',
            'Start is refused: its settings are invalid ($settingsInvalidReason)',
          );
        }
        final ok =
            state == InstanceState.stopped ||
            (state == InstanceState.error && reason == crashLoopReason);
        if (!ok) {
          if (state == InstanceState.notInstalled) {
            refuse('not_installed', 'install it first');
          }
          if (state == InstanceState.running ||
              state == InstanceState.starting) {
            refuse('instance_running', 'it is already running');
          }
          refuse('invalid_state', 'Start is not allowed');
        }
      case OperationKind.stop:
        if (execution) return;
        final ok =
            state == InstanceState.running ||
            state == InstanceState.starting ||
            state == InstanceState.stopping ||
            state == InstanceState.error;
        if (!ok) refuse('instance_not_running', 'there is nothing to stop');
      case OperationKind.restart:
        if (state != InstanceState.running) {
          refuse(
            state == InstanceState.notInstalled
                ? 'not_installed'
                : 'instance_not_running',
            'Restart needs a running instance',
          );
        }
      case OperationKind.restore:
        final ok =
            state == InstanceState.stopped ||
            (state == InstanceState.error &&
                reason == restoreInterruptedReason);
        if (!ok) {
          if (state == InstanceState.notInstalled) {
            refuse('not_installed', 'there is no server data to restore');
          }
          refuse('invalid_state', 'Restore needs it stopped');
        }
      case OperationKind.delete:
        final ok =
            state == InstanceState.stopped ||
            state == InstanceState.notInstalled ||
            state == InstanceState.error;
        if (!ok) refuse('invalid_state', 'Delete needs it stopped');
    }
  }

  // ---- state changes (used by the lifecycle and recovery) ------------------

  /// Sets the state, clearing the reason and warning unless given, and
  /// persists and announces it. A no-op once the manager is closed, so
  /// operations that outlive a killed daemon change nothing.
  void setState(
    InstanceRecord record,
    InstanceState state, {
    String reason = '',
    String warning = '',
  }) {
    if (_closed) return;
    _applyState(record, state, reason: reason, warning: warning);
    _commit(record);
  }

  void _applyState(
    InstanceRecord record,
    InstanceState state, {
    String reason = '',
    String warning = '',
  }) {
    record
      ..state = state
      ..stateReason = reason
      ..warning = warning
      ..stateChangedAt = clock();
    if (state != InstanceState.running) {
      record.health = InstanceHealth.unspecified;
    }
    if (state != InstanceState.running &&
        state != InstanceState.starting &&
        state != InstanceState.stopping) {
      record.server = null;
      record.runId = '';
      record.stopRequested = false;
    }
  }

  /// Persists and announces a change of [record] that is not a state change.
  void saveChanges(InstanceRecord record) {
    if (_closed) return;
    _commit(record);
  }

  /// Removes the instance's rows (design D25; operation rows stay).
  void removeRows(InstanceRecord record) {
    if (_closed) return;
    cancelRestart(record.id);
    store.delete(record.id);
    _records.remove(record.id);
    if (!_events.isClosed) _events.add(InstanceRemoved(record.id));
  }

  /// Persists [record]. With [revisedFrom] the write is a configuration
  /// change: it checks the stored revision and increments it in the same
  /// transaction (design D12).
  void _commit(InstanceRecord record, {int? revisedFrom}) {
    if (revisedFrom == null) {
      store.save(record);
    } else {
      store.saveRevised(record, revisedFrom);
    }
    writeInstanceFile(record);
    _emitChanged(record);
  }

  void _emitChanged(InstanceRecord record) {
    if (!_closed && !_events.isClosed) {
      _events.add(InstanceChanged(view(record)));
    }
  }

  /// Writes `instance.json`; a failure after the commit is a warning, not an
  /// error: the file is rewritten at the next change and at startup.
  void writeInstanceFile(InstanceRecord record) {
    if (_closed) return;
    try {
      InstanceFile.write(record, registry.find(record.pluginId)?.manifest);
    } on FileSystemException catch (e) {
      notice(
        record.id,
        'instance_file_stale',
        'instance.json could not be written: ${e.osError?.message ?? e.message}',
      );
    } on YaguraException catch (e) {
      // A link in the way (design D8): the file is not written.
      if (e.reason != 'sandbox_violation') rethrow;
      notice(
        record.id,
        'instance_file_stale',
        'instance.json could not be written: ${e.message}',
      );
    }
  }

  void notice(
    String instanceId,
    String kind,
    String message, {
    int exitCode = 0,
    List<String> lastLogLines = const [],
  }) {
    if (_closed || _events.isClosed) return;
    _events.add(
      InstanceNotice(
        instanceId,
        kind,
        message,
        exitCode: exitCode,
        lastLogLines: lastLogLines,
      ),
    );
  }

  LoadedPlugin _requirePlugin(InstanceRecord record) => requirePlugin(record);

  /// The loaded plugin of the instance; `plugin_missing` when there is none.
  LoadedPlugin requirePlugin(InstanceRecord record) =>
      registry.find(record.pluginId) ??
      (throw YaguraException(
        'plugin_missing',
        'plugin ${record.pluginId} of instance "${record.name}" is not loaded',
        details: {'pluginId': record.pluginId},
      ));

  // ---- plugins ------------------------------------------------------------

  /// Reloads plugins on explicit request and reconciles the instances with
  /// the result (design D17): running operations keep the manifest they
  /// started with.
  ///
  /// With [pluginIds] only those plugins are reloaded and only their instances
  /// reconciled; empty means all.
  Future<List<PluginReloadOutcome>> reloadPlugins({
    Set<String> pluginIds = const {},
  }) async {
    final outcomes = await registry.reload(pluginIds: pluginIds);
    reconcilePlugins(pluginIds: pluginIds);
    if (!_closed && !_pluginsReloaded.isClosed) _pluginsReloaded.add(null);
    return outcomes;
  }

  /// Fires after an explicit plugin reload has been reconciled, also when no
  /// instance changed (a plugin may have changed what it declares, such as
  /// its log sources).
  Stream<void> get pluginsReloaded => _pluginsReloaded.stream;

  /// Applies the plugin registry to every instance: `plugin_missing` for a
  /// stopped instance whose plugin is gone, back to `stopped` when it is
  /// restored, and settings re-validation against the loaded manifest.
  void reconcilePlugins({Set<String> pluginIds = const {}}) {
    for (final record in _records.values.toList()) {
      if (pluginIds.isNotEmpty && !pluginIds.contains(record.pluginId)) {
        continue;
      }
      final plugin = registry.find(record.pluginId);
      if (plugin == null) {
        if (record.state == InstanceState.stopped) {
          setState(record, InstanceState.error, reason: pluginMissingReason);
          notice(
            record.id,
            pluginMissingReason,
            'plugin ${record.pluginId} is not loaded',
          );
        }
        continue;
      }
      if (record.state == InstanceState.error &&
          record.stateReason == pluginMissingReason) {
        setState(record, InstanceState.stopped);
      }
      final validation = validateSettings(plugin.manifest, record.settings);
      if (validation.isValid) {
        // The normalized values carry the defaults of fields the plugin added.
        final normalized = validation.values;
        final changed = jsonEncode(normalized) != jsonEncode(record.settings);
        if (record.settingsInvalid ||
            changed ||
            record.pluginVersion != plugin.manifest.version) {
          record
            ..settingsInvalid = false
            ..settings = normalized
            ..pluginVersion = plugin.manifest.version;
          if (changed &&
              (record.state == InstanceState.running ||
                  record.state == InstanceState.starting)) {
            record.restartRequired = true;
          }
          saveChanges(record);
        }
        continue;
      }
      final message = validation.errors.join('; ');
      if (record.state == InstanceState.stopped) {
        setState(record, InstanceState.error, reason: settingsInvalidReason);
        notice(record.id, settingsInvalidReason, message);
      } else if (record.state != InstanceState.error &&
          !record.settingsInvalid) {
        record.settingsInvalid = true;
        saveChanges(record);
        notice(record.id, settingsInvalidReason, message);
      }
    }
  }

  // ---- recovery -----------------------------------------------------------

  /// Moves instances out of transient states after a daemon restart and marks
  /// unfinished operations `interrupted` (design D9). A starting, running or
  /// stopping instance is re-attached when its run record names a live process
  /// with the recorded PID, executable and start time; otherwise it is
  /// `stopped` with a `lost_while_daemon_down` notice. A run that recorded a
  /// stop request resumes as `stopping` (design D2).
  Future<void> recover() async {
    runner.recoverInterrupted();
    for (final record in _records.values.toList()) {
      switch (record.state) {
        case InstanceState.installing:
          setState(record, InstanceState.notInstalled);
          _recoveryNotice(
            record,
            'install_interrupted',
            'the daemon stopped during the install; start it again',
          );
        case InstanceState.updating:
          setState(
            record,
            InstanceState.error,
            reason: updateInterruptedReason,
          );
          _recoveryNotice(
            record,
            'update_interrupted',
            'the daemon stopped during the update; update again or acknowledge',
          );
        case InstanceState.starting ||
            InstanceState.running ||
            InstanceState.stopping:
          await _recoverRun(record);
        case InstanceState.error
            when record.stateReason == runRecordRejectedReason:
          // The rejected run stays unresolved until Stop verifies it again or
          // Acknowledge ends it.
          final rejected = runs.unresolvedFor(record.id).lastOrNull;
          if (rejected != null) record.runId = rejected.runId;
        case InstanceState.notInstalled ||
            InstanceState.stopped ||
            InstanceState.error:
          break;
      }
    }
    // A run nobody supervises is over: end it, and end its process when it is
    // still the process the run recorded.
    for (final run in runs.unresolved()) {
      if (_records[run.instanceId]?.runId == run.runId) continue;
      await _endLostRun(run);
    }
    for (final id in snapshotter.interruptedRestores()) {
      final record = _records[id];
      if (record == null) {
        snapshotter.clearInterruptedRestore(id);
        continue;
      }
      setState(record, InstanceState.error, reason: restoreInterruptedReason);
      _recoveryNotice(
        record,
        'restore_interrupted',
        'the daemon stopped during a restore; data paths may be mixed',
      );
    }
  }

  Future<void> _recoverRun(InstanceRecord record) async {
    RunningServer? server;
    RunRecord? adopted;
    RunRecord? rejectedRun;
    // Newest run first: it is the one the instance's state refers to.
    for (final run in runs.unresolvedFor(record.id).reversed) {
      if (adopted == null && rejectedRun == null) {
        try {
          final found = await _reattach(run);
          if (found != null) {
            server = found;
            adopted = run;
            continue;
          }
        } on YaguraException catch (e) {
          if (e.reason != runRecordRejectedReason) rethrow;
          _rejectRun(record, run, e.message);
          rejectedRun = run;
          continue;
        }
      }
      if (identical(run, rejectedRun)) continue;
      await _endLostRun(run);
    }

    if (rejectedRun != null) return;
    if (server == null || adopted == null) {
      // A stop the admin asked for before the daemon went down stays asked.
      final last = runs.all(record.id).lastOrNull;
      if (last != null &&
          last.stopRequestedAt != null &&
          last.stopClearsRequested) {
        record.lastRequestedRunning = false;
      }
      setState(record, InstanceState.stopped);
      // A server that exited while the daemon was down left its exit code in
      // the relay's exit record; _endLostRun stored it in the run.
      final exitCode = runs.all(record.id).lastOrNull?.exitCode;
      _recoveryNotice(
        record,
        'lost_while_daemon_down',
        exitCode == null
            ? 'the server was not re-attached after the daemon restarted'
            : 'the server exited with code $exitCode while the daemon was '
                  'down',
        exitCode: exitCode ?? 0,
      );
      return;
    }

    record
      ..server = server
      ..runId = adopted.runId;
    if (server.recordRejected) {
      _runRecordNotice(record, adopted, server);
    }
    if (adopted.state == RunState.pending) {
      runs.markRunning(
        adopted.runId,
        server: server.identity,
        relay: server.relay,
      );
    }
    if (adopted.stopRequestedAt != null) {
      record.stopRequested = true;
      setState(record, InstanceState.stopping);
      unawaited(_finishResumedStop(record, adopted, server));
    } else {
      record.lastRequestedRunning = true;
      setState(record, InstanceState.running);
      watchExit(record, server);
    }
  }

  /// Puts [record] in `error: run_record_rejected` for [run]: nothing was
  /// terminated, the run stays unresolved, and the warning names the relay.
  void _rejectRun(InstanceRecord record, RunRecord run, String message) {
    setState(
      record,
      InstanceState.error,
      reason: runRecordRejectedReason,
      warning: message,
    );
    record.runId = run.runId;
    _recoveryNotice(record, runRecordRejectedReason, message);
  }

  /// The notice for a server found by the fallback of a rejected run record.
  void _runRecordNotice(
    InstanceRecord record,
    RunRecord run,
    RunningServer server,
  ) {
    final message =
        'the run record of run ${run.runId} named no verified server; '
        'the relay ${server.relay?.pid ?? run.relay?.pid ?? 0} has server '
        '${server.pid}, which is now supervised';
    record.warning = message;
    _recoveryNotice(record, runRecordRejectedReason, message);
  }

  /// Verifies the unresolved run of an instance in `error: run_record_rejected`
  /// again (the Stop exit). Returns true when a verified server was adopted
  /// and the normal stop can go on; false when the process is gone (the run
  /// ended and the instance is `stopped`); throws `run_record_rejected` again
  /// when it is still not verified.
  Future<bool> retryRejectedRun(InstanceRecord record) async {
    final run = runs.unresolvedFor(record.id).lastOrNull;
    if (run == null) {
      setState(record, InstanceState.stopped);
      return false;
    }
    final RunningServer? server;
    try {
      server = await _reattach(run);
    } on YaguraException catch (e) {
      if (e.reason != runRecordRejectedReason) rethrow;
      record.warning = e.message;
      saveChanges(record);
      throw YaguraException(
        runRecordRejectedReason,
        e.message,
        details: {...e.details, 'instanceId': record.id},
      );
    }
    if (server == null) {
      await _endLostRun(run);
      record.server = null;
      record.runId = '';
      record.lastRequestedRunning = false;
      setState(record, InstanceState.stopped);
      return false;
    }
    record
      ..server = server
      ..runId = run.runId;
    if (run.state == RunState.pending) {
      runs.markRunning(run.runId, server: server.identity, relay: server.relay);
    }
    setState(record, InstanceState.running);
    watchExit(record, server);
    return true;
  }

  /// The live server a run recorded, or null when there is none: no process
  /// has exactly the recorded PID, executable and start time.
  Future<RunningServer?> _reattach(RunRecord run) async {
    final files = RunFiles.forRun(run.directory);
    var serverId = run.server;
    var relayId = run.relay;
    if (serverId == null) {
      // `pending`: the daemon died around `launch`. A live relay may still be
      // about to record its server.
      final deadline = clock().add(pendingRunWait);
      while (true) {
        final relay = files.readRelay();
        // The daemon's own record of the relay (the launcher reported it)
        // wins over relay.json, which the game-server account can rewrite.
        relayId ??= relay?.relay;
        if (relay?.server case final found?) {
          serverId = found;
          break;
        }
        if (relay == null ||
            !await processHost.isAlive(relayId ?? relay.relay) ||
            clock().isAfter(deadline)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (serverId == null) {
      // No recorded server. The daemon's own record of the relay (the file can
      // be rewritten by the game-server account) still names the relay, and
      // the relay's child running as the account is the server (design D9): a
      // live server is not left untracked.
      if (run.relay == null) return null;
      return processHost.reattach(
        null,
        relay: run.relay,
        runDirectory: run.directory,
      );
    }
    return processHost.reattach(
      serverId,
      relay: relayId,
      runDirectory: run.directory,
    );
  }

  Future<void> _endLostRun(RunRecord run) async {
    final identity = run.server;
    if (identity != null) {
      try {
        if (await processHost.isAlive(identity)) {
          await processHost.terminate(identity);
        }
      } on Object {
        // Best effort: the run is over either way.
      }
    }
    // A server that exited while the daemon was down: the relay recorded how.
    final exitCode = run.directory.isEmpty
        ? null
        : RunFiles.forRun(run.directory).readExitCode();
    runs.markEnded(
      run.runId,
      at: clock(),
      reason: exitCode == null ? 'lost' : 'exited_while_daemon_down',
      exitCode: exitCode,
    );
  }

  /// Waits out the rest of the grace period of a stop that was requested
  /// before the daemon went down, then kills; the server's exit ends it.
  Future<void> _finishResumedStop(
    InstanceRecord record,
    RunRecord run,
    RunningServer server,
  ) async {
    final remaining = run.stopGrace - clock().difference(run.stopRequestedAt!);
    final strategy =
        registry.find(record.pluginId)?.manifest.stop.strategy ??
        StopStrategy.signal;
    final plan = StopPlan(
      strategy: strategy,
      grace: remaining.isNegative ? Duration.zero : remaining,
      sendSignal: false,
    );
    StoppedBy by;
    try {
      by = await Future.any([
        processHost.stop(server, plan),
        server.exitCode.then((_) => StoppedBy.graceful),
      ]);
    } on Object {
      by = StoppedBy.kill;
    }
    final code = await server.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    if (_closed) return;
    runs.markEnded(
      run.runId,
      at: clock(),
      reason: 'stopped',
      stoppedBy: by.wireName,
      exitCode: code,
    );
    if (run.stopClearsRequested) record.lastRequestedRunning = false;
    setState(record, InstanceState.stopped);
  }

  // ---- supervision ---------------------------------------------------------

  /// Runs [change] on the run store unless the manager is closed (an
  /// operation that outlives a killed daemon records nothing).
  void withRuns(void Function(RunStore runs) change) {
    if (!_closed) change(runs);
  }

  /// Watches [server] for an exit nobody asked for: a crash.
  void watchExit(InstanceRecord record, RunningServer server) {
    server.exitCode.then<void>(
      (code) => _onExit(record, server, code),
      onError: (Object _) => _onExit(record, server, -1),
    );
  }

  Future<void> _onExit(
    InstanceRecord record,
    RunningServer server,
    int code,
  ) async {
    if (_closed || !identical(record.server, server)) return;
    // Starting and stopping are the operations' business; only a running
    // server with no stop request can crash.
    if (record.state != InstanceState.running || record.stopRequested) return;
    final now = clock();
    final runId = record.runId;
    if (runId.isNotEmpty) {
      runs.markEnded(runId, at: now, reason: 'crashed', exitCode: code);
    }
    runs.addCrash(record.id, now);
    final action = decideRestart(
      policy: record.restartPolicy,
      recentCrashes: runs.crashesSince(record.id, now.subtract(crashWindow)),
      now: now,
    );
    record.server = null;
    switch (action) {
      case RestartAction.restart:
        setState(record, InstanceState.stopped);
      case RestartAction.stay:
        record.lastRequestedRunning = false;
        setState(record, InstanceState.stopped);
      case RestartAction.crashLoop:
        record.lastRequestedRunning = false;
        setState(record, InstanceState.error, reason: crashLoopReason);
    }
    final lines = await _logTail(record.id);
    final message = 'the server exited with code $code without a stop request';
    notice(record.id, 'crashed', message, exitCode: code, lastLogLines: lines);
    if (action == RestartAction.crashLoop) {
      notice(
        record.id,
        'crash_loop',
        'the server crashed more than $maxRestarts times within '
            '${crashWindow.inMinutes} minutes and is not restarted again',
        exitCode: code,
        lastLogLines: lines,
      );
    }
    // The restart comes after the notice, so a client sees the crash first.
    if (action == RestartAction.restart) _scheduleRestart(record);
  }

  Future<List<String>> _logTail(String instanceId) async {
    try {
      return await logTail?.call(instanceId, 50) ?? const [];
    } on Object {
      return const [];
    }
  }

  void _scheduleRestart(InstanceRecord record) {
    cancelRestart(record.id);
    _restartTimers[record.id] = Timer(restartDelay, () {
      _restartTimers.remove(record.id);
      if (_closed ||
          !identical(_records[record.id], record) ||
          record.state != InstanceState.stopped ||
          !record.lastRequestedRunning) {
        return;
      }
      try {
        start(record.id);
      } on Object {
        if (!identical(_records[record.id], record)) return;
        record.lastRequestedRunning = false;
        saveChanges(record);
      }
    });
  }

  /// Drops a restart that is waiting out its delay.
  void cancelRestart(String instanceId) =>
      _restartTimers.remove(instanceId)?.cancel();

  /// Starts the instances that were running when the daemon went down, one
  /// after the other [autostartInterval] apart (design D14). An instance whose
  /// start fails is handled like any failed Start: stopped, and not started
  /// again by a later restart.
  void autostartInstances() {
    final ids = [
      for (final r in _records.values)
        if (r.state == InstanceState.stopped &&
            r.autostart &&
            r.lastRequestedRunning &&
            !r.settingsInvalid &&
            registry.find(r.pluginId) != null)
          r.id,
    ];
    if (ids.isEmpty) return;
    unawaited(() async {
      for (var i = 0; i < ids.length; i++) {
        if (i > 0) await Future<void>.delayed(autostartInterval);
        if (_closed) return;
        final record = _records[ids[i]];
        if (record == null || record.state != InstanceState.stopped) continue;
        try {
          final op = start(record.id);
          _recoveryNotice(
            record,
            'autostarted',
            'started again after the daemon restarted',
          );
          await runner.whenDone(op.id);
        } on Object {
          record.lastRequestedRunning = false;
          saveChanges(record);
        }
      }
    }());
  }

  void _recoveryNotice(
    InstanceRecord record,
    String kind,
    String message, {
    int exitCode = 0,
  }) {
    final notice = InstanceNotice(record.id, kind, message, exitCode: exitCode);
    _recoveryNotices.add(notice);
    if (!_events.isClosed) _events.add(notice);
  }

  /// Rewrites `instance.json` of every instance (ADR 0008: the file can be
  /// stale only when the daemon died between commit and write).
  void rewriteInstanceFiles() {
    for (final record in _records.values) {
      if (_directoryMayExist(record.directory)) writeInstanceFile(record);
    }
  }

  /// Whether the instance directory is there; a link in its place counts as
  /// there, so the write that follows reports it.
  bool _directoryMayExist(String directory) {
    try {
      return InstanceFs(directory).stat('') != null;
    } on YaguraException {
      return true;
    }
  }

  /// Finishes deletes interrupted by a crash (design D25): a directory under
  /// the instances root with a `.yagura/deleting` marker and no instance row
  /// is removed; a marker whose row still exists is removed alone, because
  /// the rows were never deleted. Instances may sit below grouping
  /// directories, so the walk goes down until it meets an instance root; it
  /// does not follow links.
  void sweepMarkedDirectories() {
    final root = Directory(dataDirectory.instancesPath);
    if (!root.existsSync()) return;
    _sweepMarked(root);
  }

  void _sweepMarked(Directory directory) {
    for (final entry
        in directory.listSync(followLinks: false).whereType<Directory>()) {
      final fs = InstanceFs(entry.path);
      final owner = _records.values.any(
        (r) => p.equals(p.normalize(p.absolute(r.directory)), entry.path),
      );
      final bool marked;
      try {
        marked = fs.exists(InstanceFs.deletingMarker);
      } on YaguraException {
        // A link under the directory: its marker cannot be read, and nothing
        // below it is entered.
        continue;
      }
      if (marked) {
        if (owner) {
          fs.delete(InstanceFs.deletingMarker);
        } else {
          fs.deleteTree('');
        }
      } else if (!owner) {
        _sweepMarked(entry);
      }
    }
  }

  /// Stops announcing changes. Operations still running change nothing more.
  Future<void> close() async {
    _closed = true;
    for (final timer in _restartTimers.values) {
      timer.cancel();
    }
    _restartTimers.clear();
    for (final record in _records.values) {
      if (record.server case final server?) processHost.release(server);
    }
    await _events.close();
    await _pluginsReloaded.close();
  }
}
