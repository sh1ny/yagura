// This is a generated file - do not edit.
//
// Generated from yagura/v1/instances.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $3;

import 'common.pb.dart' as $2;
import 'instances.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'instances.pbenum.dart';

class Instance extends $pb.GeneratedMessage {
  factory Instance({
    $core.String? id,
    $core.String? name,
    $core.String? pluginId,
    $core.String? pluginVersion,
    $core.String? directory,
    InstanceState? state,
    $core.String? stateReason,
    Health? health,
    $core.Iterable<$2.Port>? ports,
    $2.JsonDocument? settings,
    $core.String? steamAccountId,
    $core.String? restartPolicy,
    $core.String? firewallStatus,
    $core.String? activeOperationId,
    $core.int? queuedOperations,
    $3.Timestamp? createdAt,
    $3.Timestamp? stateChangedAt,
    $core.int? pid,
    $fixnum.Int64? revision,
    $core.bool? restartRequired,
    $core.bool? autostart,
    $core.bool? settingsInvalid,
    $core.int? modsUpdateAvailable,
    $core.bool? settingsOmitted,
  }) {
    final result = Instance._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (pluginId != null) result.pluginId = pluginId;
    if (pluginVersion != null) result.pluginVersion = pluginVersion;
    if (directory != null) result.directory = directory;
    if (state != null) result.state = state;
    if (stateReason != null) result.stateReason = stateReason;
    if (health != null) result.health = health;
    if (ports != null) result.ports.addAll(ports);
    if (settings != null) result.settings = settings;
    if (steamAccountId != null) result.steamAccountId = steamAccountId;
    if (restartPolicy != null) result.restartPolicy = restartPolicy;
    if (firewallStatus != null) result.firewallStatus = firewallStatus;
    if (activeOperationId != null) result.activeOperationId = activeOperationId;
    if (queuedOperations != null) result.queuedOperations = queuedOperations;
    if (createdAt != null) result.createdAt = createdAt;
    if (stateChangedAt != null) result.stateChangedAt = stateChangedAt;
    if (pid != null) result.pid = pid;
    if (revision != null) result.revision = revision;
    if (restartRequired != null) result.restartRequired = restartRequired;
    if (autostart != null) result.autostart = autostart;
    if (settingsInvalid != null) result.settingsInvalid = settingsInvalid;
    if (modsUpdateAvailable != null)
      result.modsUpdateAvailable = modsUpdateAvailable;
    if (settingsOmitted != null) result.settingsOmitted = settingsOmitted;
    return result;
  }

  Instance._();

  factory Instance.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Instance()..mergeFromBuffer(data, registry);
  factory Instance.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Instance()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Instance',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Instance.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'pluginId')
    ..aOS(4, _omitFieldNames ? '' : 'pluginVersion')
    ..aOS(5, _omitFieldNames ? '' : 'directory')
    ..aE<InstanceState>(6, _omitFieldNames ? '' : 'state',
        enumValues: InstanceState.values)
    ..aOS(7, _omitFieldNames ? '' : 'stateReason')
    ..aE<Health>(8, _omitFieldNames ? '' : 'health', enumValues: Health.values)
    ..pPM<$2.Port>(9, _omitFieldNames ? '' : 'ports',
        subBuilder: $2.Port.$_createMessage)
    ..aOM<$2.JsonDocument>(10, _omitFieldNames ? '' : 'settings',
        subBuilder: $2.JsonDocument.$_createMessage)
    ..aOS(11, _omitFieldNames ? '' : 'steamAccountId')
    ..aOS(12, _omitFieldNames ? '' : 'restartPolicy')
    ..aOS(13, _omitFieldNames ? '' : 'firewallStatus')
    ..aOS(14, _omitFieldNames ? '' : 'activeOperationId')
    ..aI(15, _omitFieldNames ? '' : 'queuedOperations',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<$3.Timestamp>(16, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $3.Timestamp.$_createMessage)
    ..aOM<$3.Timestamp>(17, _omitFieldNames ? '' : 'stateChangedAt',
        subBuilder: $3.Timestamp.$_createMessage)
    ..aI(18, _omitFieldNames ? '' : 'pid', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        19, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(20, _omitFieldNames ? '' : 'restartRequired')
    ..aOB(21, _omitFieldNames ? '' : 'autostart')
    ..aOB(22, _omitFieldNames ? '' : 'settingsInvalid')
    ..aI(23, _omitFieldNames ? '' : 'modsUpdateAvailable',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(24, _omitFieldNames ? '' : 'settingsOmitted')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Instance clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Instance copyWith(void Function(Instance) updates) =>
      super.copyWith((message) => updates(message as Instance)) as Instance;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Instance() / Instance.new instead')
  static Instance create() => Instance._();
  static $pb.GeneratedMessage $_createMessage() => Instance._();
  @$core.override
  Instance createEmptyInstance() => Instance._();
  @$core.pragma('dart2js:noInline')
  static Instance getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Instance>(Instance.$_createMessage);
  static Instance? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get pluginId => $_getSZ(2);
  @$pb.TagNumber(3)
  set pluginId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPluginId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPluginId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get pluginVersion => $_getSZ(3);
  @$pb.TagNumber(4)
  set pluginVersion($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPluginVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearPluginVersion() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get directory => $_getSZ(4);
  @$pb.TagNumber(5)
  set directory($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDirectory() => $_has(4);
  @$pb.TagNumber(5)
  void clearDirectory() => $_clearField(5);

  @$pb.TagNumber(6)
  InstanceState get state => $_getN(5);
  @$pb.TagNumber(6)
  set state(InstanceState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasState() => $_has(5);
  @$pb.TagNumber(6)
  void clearState() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get stateReason => $_getSZ(6);
  @$pb.TagNumber(7)
  set stateReason($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStateReason() => $_has(6);
  @$pb.TagNumber(7)
  void clearStateReason() => $_clearField(7);

  @$pb.TagNumber(8)
  Health get health => $_getN(7);
  @$pb.TagNumber(8)
  set health(Health value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasHealth() => $_has(7);
  @$pb.TagNumber(8)
  void clearHealth() => $_clearField(8);

  @$pb.TagNumber(9)
  $pb.PbList<$2.Port> get ports => $_getList(8);

  /// Settings values; secrets appear as {"secret": true, "set": bool}.
  @$pb.TagNumber(10)
  $2.JsonDocument get settings => $_getN(9);
  @$pb.TagNumber(10)
  set settings($2.JsonDocument value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasSettings() => $_has(9);
  @$pb.TagNumber(10)
  void clearSettings() => $_clearField(10);
  @$pb.TagNumber(10)
  $2.JsonDocument ensureSettings() => $_ensure(9);

  @$pb.TagNumber(11)
  $core.String get steamAccountId => $_getSZ(10);
  @$pb.TagNumber(11)
  set steamAccountId($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSteamAccountId() => $_has(10);
  @$pb.TagNumber(11)
  void clearSteamAccountId() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get restartPolicy => $_getSZ(11);
  @$pb.TagNumber(12)
  set restartPolicy($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasRestartPolicy() => $_has(11);
  @$pb.TagNumber(12)
  void clearRestartPolicy() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get firewallStatus => $_getSZ(12);
  @$pb.TagNumber(13)
  set firewallStatus($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasFirewallStatus() => $_has(12);
  @$pb.TagNumber(13)
  void clearFirewallStatus() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get activeOperationId => $_getSZ(13);
  @$pb.TagNumber(14)
  set activeOperationId($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasActiveOperationId() => $_has(13);
  @$pb.TagNumber(14)
  void clearActiveOperationId() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get queuedOperations => $_getIZ(14);
  @$pb.TagNumber(15)
  set queuedOperations($core.int value) => $_setUnsignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasQueuedOperations() => $_has(14);
  @$pb.TagNumber(15)
  void clearQueuedOperations() => $_clearField(15);

  @$pb.TagNumber(16)
  $3.Timestamp get createdAt => $_getN(15);
  @$pb.TagNumber(16)
  set createdAt($3.Timestamp value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasCreatedAt() => $_has(15);
  @$pb.TagNumber(16)
  void clearCreatedAt() => $_clearField(16);
  @$pb.TagNumber(16)
  $3.Timestamp ensureCreatedAt() => $_ensure(15);

  @$pb.TagNumber(17)
  $3.Timestamp get stateChangedAt => $_getN(16);
  @$pb.TagNumber(17)
  set stateChangedAt($3.Timestamp value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasStateChangedAt() => $_has(16);
  @$pb.TagNumber(17)
  void clearStateChangedAt() => $_clearField(17);
  @$pb.TagNumber(17)
  $3.Timestamp ensureStateChangedAt() => $_ensure(16);

  @$pb.TagNumber(18)
  $core.int get pid => $_getIZ(17);
  @$pb.TagNumber(18)
  set pid($core.int value) => $_setUnsignedInt32(17, value);
  @$pb.TagNumber(18)
  $core.bool hasPid() => $_has(17);
  @$pb.TagNumber(18)
  void clearPid() => $_clearField(18);

  /// Incremented only on configuration changes (settings, ports, secrets, mods,
  /// restart policy, autostart, Steam account, snapshot restore), never on state, health,
  /// pid or queue changes. Mutating calls send expected_revision and
  /// get FAILED_PRECONDITION revision_conflict when it is stale.
  @$pb.TagNumber(19)
  $fixnum.Int64 get revision => $_getI64(18);
  @$pb.TagNumber(19)
  set revision($fixnum.Int64 value) => $_setInt64(18, value);
  @$pb.TagNumber(19)
  $core.bool hasRevision() => $_has(18);
  @$pb.TagNumber(19)
  void clearRevision() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.bool get restartRequired => $_getBF(19);
  @$pb.TagNumber(20)
  set restartRequired($core.bool value) => $_setBool(19, value);
  @$pb.TagNumber(20)
  $core.bool hasRestartRequired() => $_has(19);
  @$pb.TagNumber(20)
  void clearRestartRequired() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.bool get autostart => $_getBF(20);
  @$pb.TagNumber(21)
  set autostart($core.bool value) => $_setBool(20, value);
  @$pb.TagNumber(21)
  $core.bool hasAutostart() => $_has(20);
  @$pb.TagNumber(21)
  void clearAutostart() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.bool get settingsInvalid => $_getBF(21);
  @$pb.TagNumber(22)
  set settingsInvalid($core.bool value) => $_setBool(21, value);
  @$pb.TagNumber(22)
  $core.bool hasSettingsInvalid() => $_has(21);
  @$pb.TagNumber(22)
  void clearSettingsInvalid() => $_clearField(22);

  @$pb.TagNumber(23)
  $core.int get modsUpdateAvailable => $_getIZ(22);
  @$pb.TagNumber(23)
  set modsUpdateAvailable($core.int value) => $_setUnsignedInt32(22, value);
  @$pb.TagNumber(23)
  $core.bool hasModsUpdateAvailable() => $_has(22);
  @$pb.TagNumber(23)
  void clearModsUpdateAvailable() => $_clearField(23);

  /// true on deltas where settings did not change; fetch with GetInstance.
  @$pb.TagNumber(24)
  $core.bool get settingsOmitted => $_getBF(23);
  @$pb.TagNumber(24)
  set settingsOmitted($core.bool value) => $_setBool(23, value);
  @$pb.TagNumber(24)
  $core.bool hasSettingsOmitted() => $_has(23);
  @$pb.TagNumber(24)
  void clearSettingsOmitted() => $_clearField(24);
}

class ListInstancesRequest extends $pb.GeneratedMessage {
  factory ListInstancesRequest() => ListInstancesRequest._();

  ListInstancesRequest._();

  factory ListInstancesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListInstancesRequest()..mergeFromBuffer(data, registry);
  factory ListInstancesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListInstancesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListInstancesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListInstancesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInstancesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInstancesRequest copyWith(void Function(ListInstancesRequest) updates) =>
      super.copyWith((message) => updates(message as ListInstancesRequest))
          as ListInstancesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListInstancesRequest() / ListInstancesRequest.new instead')
  static ListInstancesRequest create() => ListInstancesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListInstancesRequest._();
  @$core.override
  ListInstancesRequest createEmptyInstance() => ListInstancesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListInstancesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListInstancesRequest>(
          ListInstancesRequest.$_createMessage);
  static ListInstancesRequest? _defaultInstance;
}

class ListInstancesResponse extends $pb.GeneratedMessage {
  factory ListInstancesResponse({
    $core.Iterable<Instance>? instances,
  }) {
    final result = ListInstancesResponse._();
    if (instances != null) result.instances.addAll(instances);
    return result;
  }

  ListInstancesResponse._();

  factory ListInstancesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListInstancesResponse()..mergeFromBuffer(data, registry);
  factory ListInstancesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListInstancesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListInstancesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListInstancesResponse.$_createMessage)
    ..pPM<Instance>(1, _omitFieldNames ? '' : 'instances',
        subBuilder: Instance.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInstancesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInstancesResponse copyWith(
          void Function(ListInstancesResponse) updates) =>
      super.copyWith((message) => updates(message as ListInstancesResponse))
          as ListInstancesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListInstancesResponse() / ListInstancesResponse.new instead')
  static ListInstancesResponse create() => ListInstancesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListInstancesResponse._();
  @$core.override
  ListInstancesResponse createEmptyInstance() => ListInstancesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListInstancesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListInstancesResponse>(
          ListInstancesResponse.$_createMessage);
  static ListInstancesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Instance> get instances => $_getList(0);
}

class GetInstanceRequest extends $pb.GeneratedMessage {
  factory GetInstanceRequest({
    $core.String? instanceId,
  }) {
    final result = GetInstanceRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    return result;
  }

  GetInstanceRequest._();

  factory GetInstanceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetInstanceRequest()..mergeFromBuffer(data, registry);
  factory GetInstanceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetInstanceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetInstanceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: GetInstanceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetInstanceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetInstanceRequest copyWith(void Function(GetInstanceRequest) updates) =>
      super.copyWith((message) => updates(message as GetInstanceRequest))
          as GetInstanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetInstanceRequest() / GetInstanceRequest.new instead')
  static GetInstanceRequest create() => GetInstanceRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetInstanceRequest._();
  @$core.override
  GetInstanceRequest createEmptyInstance() => GetInstanceRequest._();
  @$core.pragma('dart2js:noInline')
  static GetInstanceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetInstanceRequest>(
          GetInstanceRequest.$_createMessage);
  static GetInstanceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);
}

class WatchInstancesRequest extends $pb.GeneratedMessage {
  factory WatchInstancesRequest() => WatchInstancesRequest._();

  WatchInstancesRequest._();

  factory WatchInstancesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchInstancesRequest()..mergeFromBuffer(data, registry);
  factory WatchInstancesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchInstancesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchInstancesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: WatchInstancesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchInstancesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchInstancesRequest copyWith(
          void Function(WatchInstancesRequest) updates) =>
      super.copyWith((message) => updates(message as WatchInstancesRequest))
          as WatchInstancesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchInstancesRequest() / WatchInstancesRequest.new instead')
  static WatchInstancesRequest create() => WatchInstancesRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchInstancesRequest._();
  @$core.override
  WatchInstancesRequest createEmptyInstance() => WatchInstancesRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchInstancesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchInstancesRequest>(
          WatchInstancesRequest.$_createMessage);
  static WatchInstancesRequest? _defaultInstance;
}

enum InstanceEvent_Event {
  snapshot,
  changed,
  removedInstanceId,
  resyncRequired,
  notice,
  notSet
}

class InstanceEvent extends $pb.GeneratedMessage {
  factory InstanceEvent({
    InstanceSnapshot? snapshot,
    Instance? changed,
    $core.String? removedInstanceId,
    ResyncRequired? resyncRequired,
    InstanceNotice? notice,
  }) {
    final result = InstanceEvent._();
    if (snapshot != null) result.snapshot = snapshot;
    if (changed != null) result.changed = changed;
    if (removedInstanceId != null) result.removedInstanceId = removedInstanceId;
    if (resyncRequired != null) result.resyncRequired = resyncRequired;
    if (notice != null) result.notice = notice;
    return result;
  }

  InstanceEvent._();

  factory InstanceEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstanceEvent()..mergeFromBuffer(data, registry);
  factory InstanceEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstanceEvent()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, InstanceEvent_Event>
      _InstanceEvent_EventByTag = {
    1: InstanceEvent_Event.snapshot,
    2: InstanceEvent_Event.changed,
    3: InstanceEvent_Event.removedInstanceId,
    4: InstanceEvent_Event.resyncRequired,
    5: InstanceEvent_Event.notice,
    0: InstanceEvent_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InstanceEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: InstanceEvent.$_createMessage)
    ..oo(0, [1, 2, 3, 4, 5])
    ..aOM<InstanceSnapshot>(1, _omitFieldNames ? '' : 'snapshot',
        subBuilder: InstanceSnapshot.$_createMessage)
    ..aOM<Instance>(2, _omitFieldNames ? '' : 'changed',
        subBuilder: Instance.$_createMessage)
    ..aOS(3, _omitFieldNames ? '' : 'removedInstanceId')
    ..aOM<ResyncRequired>(4, _omitFieldNames ? '' : 'resyncRequired',
        subBuilder: ResyncRequired.$_createMessage)
    ..aOM<InstanceNotice>(5, _omitFieldNames ? '' : 'notice',
        subBuilder: InstanceNotice.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstanceEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstanceEvent copyWith(void Function(InstanceEvent) updates) =>
      super.copyWith((message) => updates(message as InstanceEvent))
          as InstanceEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use InstanceEvent() / InstanceEvent.new instead')
  static InstanceEvent create() => InstanceEvent._();
  static $pb.GeneratedMessage $_createMessage() => InstanceEvent._();
  @$core.override
  InstanceEvent createEmptyInstance() => InstanceEvent._();
  @$core.pragma('dart2js:noInline')
  static InstanceEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InstanceEvent>(
          InstanceEvent.$_createMessage);
  static InstanceEvent? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  InstanceEvent_Event whichEvent() =>
      _InstanceEvent_EventByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearEvent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  InstanceSnapshot get snapshot => $_getN(0);
  @$pb.TagNumber(1)
  set snapshot(InstanceSnapshot value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshot() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshot() => $_clearField(1);
  @$pb.TagNumber(1)
  InstanceSnapshot ensureSnapshot() => $_ensure(0);

  @$pb.TagNumber(2)
  Instance get changed => $_getN(1);
  @$pb.TagNumber(2)
  set changed(Instance value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasChanged() => $_has(1);
  @$pb.TagNumber(2)
  void clearChanged() => $_clearField(2);
  @$pb.TagNumber(2)
  Instance ensureChanged() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get removedInstanceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set removedInstanceId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRemovedInstanceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRemovedInstanceId() => $_clearField(3);

  @$pb.TagNumber(4)
  ResyncRequired get resyncRequired => $_getN(3);
  @$pb.TagNumber(4)
  set resyncRequired(ResyncRequired value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasResyncRequired() => $_has(3);
  @$pb.TagNumber(4)
  void clearResyncRequired() => $_clearField(4);
  @$pb.TagNumber(4)
  ResyncRequired ensureResyncRequired() => $_ensure(3);

  @$pb.TagNumber(5)
  InstanceNotice get notice => $_getN(4);
  @$pb.TagNumber(5)
  set notice(InstanceNotice value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasNotice() => $_has(4);
  @$pb.TagNumber(5)
  void clearNotice() => $_clearField(5);
  @$pb.TagNumber(5)
  InstanceNotice ensureNotice() => $_ensure(4);
}

class InstanceSnapshot extends $pb.GeneratedMessage {
  factory InstanceSnapshot({
    $core.Iterable<Instance>? instances,
  }) {
    final result = InstanceSnapshot._();
    if (instances != null) result.instances.addAll(instances);
    return result;
  }

  InstanceSnapshot._();

  factory InstanceSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstanceSnapshot()..mergeFromBuffer(data, registry);
  factory InstanceSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstanceSnapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InstanceSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: InstanceSnapshot.$_createMessage)
    ..pPM<Instance>(1, _omitFieldNames ? '' : 'instances',
        subBuilder: Instance.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstanceSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstanceSnapshot copyWith(void Function(InstanceSnapshot) updates) =>
      super.copyWith((message) => updates(message as InstanceSnapshot))
          as InstanceSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use InstanceSnapshot() / InstanceSnapshot.new instead')
  static InstanceSnapshot create() => InstanceSnapshot._();
  static $pb.GeneratedMessage $_createMessage() => InstanceSnapshot._();
  @$core.override
  InstanceSnapshot createEmptyInstance() => InstanceSnapshot._();
  @$core.pragma('dart2js:noInline')
  static InstanceSnapshot getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InstanceSnapshot>(
          InstanceSnapshot.$_createMessage);
  static InstanceSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Instance> get instances => $_getList(0);
}

class ResyncRequired extends $pb.GeneratedMessage {
  factory ResyncRequired() => ResyncRequired._();

  ResyncRequired._();

  factory ResyncRequired.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResyncRequired()..mergeFromBuffer(data, registry);
  factory ResyncRequired.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResyncRequired()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResyncRequired',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ResyncRequired.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResyncRequired clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResyncRequired copyWith(void Function(ResyncRequired) updates) =>
      super.copyWith((message) => updates(message as ResyncRequired))
          as ResyncRequired;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ResyncRequired() / ResyncRequired.new instead')
  static ResyncRequired create() => ResyncRequired._();
  static $pb.GeneratedMessage $_createMessage() => ResyncRequired._();
  @$core.override
  ResyncRequired createEmptyInstance() => ResyncRequired._();
  @$core.pragma('dart2js:noInline')
  static ResyncRequired getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ResyncRequired>(
          ResyncRequired.$_createMessage);
  static ResyncRequired? _defaultInstance;
}

class InstanceNotice extends $pb.GeneratedMessage {
  factory InstanceNotice({
    $core.String? instanceId,
    $core.String? kind,
    $core.String? message,
    $core.int? exitCode,
    $core.Iterable<$core.String>? lastLogLines,
    $3.Timestamp? at,
  }) {
    final result = InstanceNotice._();
    if (instanceId != null) result.instanceId = instanceId;
    if (kind != null) result.kind = kind;
    if (message != null) result.message = message;
    if (exitCode != null) result.exitCode = exitCode;
    if (lastLogLines != null) result.lastLogLines.addAll(lastLogLines);
    if (at != null) result.at = at;
    return result;
  }

  InstanceNotice._();

  factory InstanceNotice.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstanceNotice()..mergeFromBuffer(data, registry);
  factory InstanceNotice.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstanceNotice()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InstanceNotice',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: InstanceNotice.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'kind')
    ..aOS(3, _omitFieldNames ? '' : 'message')
    ..aI(4, _omitFieldNames ? '' : 'exitCode')
    ..pPS(5, _omitFieldNames ? '' : 'lastLogLines')
    ..aOM<$3.Timestamp>(6, _omitFieldNames ? '' : 'at',
        subBuilder: $3.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstanceNotice clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstanceNotice copyWith(void Function(InstanceNotice) updates) =>
      super.copyWith((message) => updates(message as InstanceNotice))
          as InstanceNotice;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use InstanceNotice() / InstanceNotice.new instead')
  static InstanceNotice create() => InstanceNotice._();
  static $pb.GeneratedMessage $_createMessage() => InstanceNotice._();
  @$core.override
  InstanceNotice createEmptyInstance() => InstanceNotice._();
  @$core.pragma('dart2js:noInline')
  static InstanceNotice getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InstanceNotice>(
          InstanceNotice.$_createMessage);
  static InstanceNotice? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get kind => $_getSZ(1);
  @$pb.TagNumber(2)
  set kind($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get exitCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set exitCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExitCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearExitCode() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get lastLogLines => $_getList(4);

  @$pb.TagNumber(6)
  $3.Timestamp get at => $_getN(5);
  @$pb.TagNumber(6)
  set at($3.Timestamp value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearAt() => $_clearField(6);
  @$pb.TagNumber(6)
  $3.Timestamp ensureAt() => $_ensure(5);
}

class CreateInstanceRequest extends $pb.GeneratedMessage {
  factory CreateInstanceRequest({
    $core.String? pluginId,
    $core.String? name,
    $core.String? directory,
    $2.JsonDocument? settings,
    $core.Iterable<$2.Port>? ports,
    $core.String? steamAccountId,
  }) {
    final result = CreateInstanceRequest._();
    if (pluginId != null) result.pluginId = pluginId;
    if (name != null) result.name = name;
    if (directory != null) result.directory = directory;
    if (settings != null) result.settings = settings;
    if (ports != null) result.ports.addAll(ports);
    if (steamAccountId != null) result.steamAccountId = steamAccountId;
    return result;
  }

  CreateInstanceRequest._();

  factory CreateInstanceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateInstanceRequest()..mergeFromBuffer(data, registry);
  factory CreateInstanceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateInstanceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateInstanceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: CreateInstanceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'pluginId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'directory')
    ..aOM<$2.JsonDocument>(4, _omitFieldNames ? '' : 'settings',
        subBuilder: $2.JsonDocument.$_createMessage)
    ..pPM<$2.Port>(5, _omitFieldNames ? '' : 'ports',
        subBuilder: $2.Port.$_createMessage)
    ..aOS(6, _omitFieldNames ? '' : 'steamAccountId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateInstanceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateInstanceRequest copyWith(
          void Function(CreateInstanceRequest) updates) =>
      super.copyWith((message) => updates(message as CreateInstanceRequest))
          as CreateInstanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateInstanceRequest() / CreateInstanceRequest.new instead')
  static CreateInstanceRequest create() => CreateInstanceRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateInstanceRequest._();
  @$core.override
  CreateInstanceRequest createEmptyInstance() => CreateInstanceRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateInstanceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateInstanceRequest>(
          CreateInstanceRequest.$_createMessage);
  static CreateInstanceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pluginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set pluginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPluginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPluginId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get directory => $_getSZ(2);
  @$pb.TagNumber(3)
  set directory($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDirectory() => $_has(2);
  @$pb.TagNumber(3)
  void clearDirectory() => $_clearField(3);

  @$pb.TagNumber(4)
  $2.JsonDocument get settings => $_getN(3);
  @$pb.TagNumber(4)
  set settings($2.JsonDocument value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSettings() => $_has(3);
  @$pb.TagNumber(4)
  void clearSettings() => $_clearField(4);
  @$pb.TagNumber(4)
  $2.JsonDocument ensureSettings() => $_ensure(3);

  @$pb.TagNumber(5)
  $pb.PbList<$2.Port> get ports => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get steamAccountId => $_getSZ(5);
  @$pb.TagNumber(6)
  set steamAccountId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSteamAccountId() => $_has(5);
  @$pb.TagNumber(6)
  void clearSteamAccountId() => $_clearField(6);
}

class UpdateSettingsRequest extends $pb.GeneratedMessage {
  factory UpdateSettingsRequest({
    $core.String? instanceId,
    $2.JsonDocument? settings,
    $core.Iterable<$2.Port>? ports,
    $core.String? restartPolicy,
    $core.String? steamAccountId,
    $fixnum.Int64? expectedRevision,
    $core.bool? autostart,
  }) {
    final result = UpdateSettingsRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (settings != null) result.settings = settings;
    if (ports != null) result.ports.addAll(ports);
    if (restartPolicy != null) result.restartPolicy = restartPolicy;
    if (steamAccountId != null) result.steamAccountId = steamAccountId;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (autostart != null) result.autostart = autostart;
    return result;
  }

  UpdateSettingsRequest._();

  factory UpdateSettingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateSettingsRequest()..mergeFromBuffer(data, registry);
  factory UpdateSettingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateSettingsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateSettingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: UpdateSettingsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOM<$2.JsonDocument>(2, _omitFieldNames ? '' : 'settings',
        subBuilder: $2.JsonDocument.$_createMessage)
    ..pPM<$2.Port>(3, _omitFieldNames ? '' : 'ports',
        subBuilder: $2.Port.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'restartPolicy')
    ..aOS(5, _omitFieldNames ? '' : 'steamAccountId')
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(7, _omitFieldNames ? '' : 'autostart')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateSettingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateSettingsRequest copyWith(
          void Function(UpdateSettingsRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateSettingsRequest))
          as UpdateSettingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use UpdateSettingsRequest() / UpdateSettingsRequest.new instead')
  static UpdateSettingsRequest create() => UpdateSettingsRequest._();
  static $pb.GeneratedMessage $_createMessage() => UpdateSettingsRequest._();
  @$core.override
  UpdateSettingsRequest createEmptyInstance() => UpdateSettingsRequest._();
  @$core.pragma('dart2js:noInline')
  static UpdateSettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateSettingsRequest>(
          UpdateSettingsRequest.$_createMessage);
  static UpdateSettingsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $2.JsonDocument get settings => $_getN(1);
  @$pb.TagNumber(2)
  set settings($2.JsonDocument value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSettings() => $_has(1);
  @$pb.TagNumber(2)
  void clearSettings() => $_clearField(2);
  @$pb.TagNumber(2)
  $2.JsonDocument ensureSettings() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<$2.Port> get ports => $_getList(2);

  /// unset = unchanged; empty steam_account_id = unlink
  @$pb.TagNumber(4)
  $core.String get restartPolicy => $_getSZ(3);
  @$pb.TagNumber(4)
  set restartPolicy($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRestartPolicy() => $_has(3);
  @$pb.TagNumber(4)
  void clearRestartPolicy() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get steamAccountId => $_getSZ(4);
  @$pb.TagNumber(5)
  set steamAccountId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSteamAccountId() => $_has(4);
  @$pb.TagNumber(5)
  void clearSteamAccountId() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get expectedRevision => $_getI64(5);
  @$pb.TagNumber(6)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasExpectedRevision() => $_has(5);
  @$pb.TagNumber(6)
  void clearExpectedRevision() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get autostart => $_getBF(6);
  @$pb.TagNumber(7)
  set autostart($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAutostart() => $_has(6);
  @$pb.TagNumber(7)
  void clearAutostart() => $_clearField(7);
}

class SetSecretRequest extends $pb.GeneratedMessage {
  factory SetSecretRequest({
    $core.String? instanceId,
    $core.String? key,
    $core.String? value,
    $fixnum.Int64? expectedRevision,
  }) {
    final result = SetSecretRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    return result;
  }

  SetSecretRequest._();

  factory SetSecretRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetSecretRequest()..mergeFromBuffer(data, registry);
  factory SetSecretRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetSecretRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetSecretRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: SetSecretRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'key')
    ..aOS(3, _omitFieldNames ? '' : 'value')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSecretRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSecretRequest copyWith(void Function(SetSecretRequest) updates) =>
      super.copyWith((message) => updates(message as SetSecretRequest))
          as SetSecretRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetSecretRequest() / SetSecretRequest.new instead')
  static SetSecretRequest create() => SetSecretRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetSecretRequest._();
  @$core.override
  SetSecretRequest createEmptyInstance() => SetSecretRequest._();
  @$core.pragma('dart2js:noInline')
  static SetSecretRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetSecretRequest>(
          SetSecretRequest.$_createMessage);
  static SetSecretRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get key => $_getSZ(1);
  @$pb.TagNumber(2)
  set key($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get value => $_getSZ(2);
  @$pb.TagNumber(3)
  set value($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasValue() => $_has(2);
  @$pb.TagNumber(3)
  void clearValue() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get expectedRevision => $_getI64(3);
  @$pb.TagNumber(4)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpectedRevision() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpectedRevision() => $_clearField(4);
}

class DeleteSecretRequest extends $pb.GeneratedMessage {
  factory DeleteSecretRequest({
    $core.String? instanceId,
    $core.String? key,
    $fixnum.Int64? expectedRevision,
  }) {
    final result = DeleteSecretRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (key != null) result.key = key;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    return result;
  }

  DeleteSecretRequest._();

  factory DeleteSecretRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteSecretRequest()..mergeFromBuffer(data, registry);
  factory DeleteSecretRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteSecretRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteSecretRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: DeleteSecretRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'key')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteSecretRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteSecretRequest copyWith(void Function(DeleteSecretRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteSecretRequest))
          as DeleteSecretRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use DeleteSecretRequest() / DeleteSecretRequest.new instead')
  static DeleteSecretRequest create() => DeleteSecretRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeleteSecretRequest._();
  @$core.override
  DeleteSecretRequest createEmptyInstance() => DeleteSecretRequest._();
  @$core.pragma('dart2js:noInline')
  static DeleteSecretRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteSecretRequest>(
          DeleteSecretRequest.$_createMessage);
  static DeleteSecretRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get key => $_getSZ(1);
  @$pb.TagNumber(2)
  set key($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expectedRevision => $_getI64(2);
  @$pb.TagNumber(3)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedRevision() => $_clearField(3);
}

class DeleteInstanceRequest extends $pb.GeneratedMessage {
  factory DeleteInstanceRequest({
    $core.String? instanceId,
    $core.bool? deleteFiles,
    $core.String? confirmName,
    $fixnum.Int64? expectedRevision,
  }) {
    final result = DeleteInstanceRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (deleteFiles != null) result.deleteFiles = deleteFiles;
    if (confirmName != null) result.confirmName = confirmName;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    return result;
  }

  DeleteInstanceRequest._();

  factory DeleteInstanceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteInstanceRequest()..mergeFromBuffer(data, registry);
  factory DeleteInstanceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteInstanceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteInstanceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: DeleteInstanceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOB(2, _omitFieldNames ? '' : 'deleteFiles')
    ..aOS(3, _omitFieldNames ? '' : 'confirmName')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteInstanceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteInstanceRequest copyWith(
          void Function(DeleteInstanceRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteInstanceRequest))
          as DeleteInstanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeleteInstanceRequest() / DeleteInstanceRequest.new instead')
  static DeleteInstanceRequest create() => DeleteInstanceRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeleteInstanceRequest._();
  @$core.override
  DeleteInstanceRequest createEmptyInstance() => DeleteInstanceRequest._();
  @$core.pragma('dart2js:noInline')
  static DeleteInstanceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteInstanceRequest>(
          DeleteInstanceRequest.$_createMessage);
  static DeleteInstanceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get deleteFiles => $_getBF(1);
  @$pb.TagNumber(2)
  set deleteFiles($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeleteFiles() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeleteFiles() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get confirmName => $_getSZ(2);
  @$pb.TagNumber(3)
  set confirmName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConfirmName() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfirmName() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get expectedRevision => $_getI64(3);
  @$pb.TagNumber(4)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpectedRevision() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpectedRevision() => $_clearField(4);
}

class ImportInstanceRequest extends $pb.GeneratedMessage {
  factory ImportInstanceRequest({
    $core.String? directory,
    $core.String? name,
  }) {
    final result = ImportInstanceRequest._();
    if (directory != null) result.directory = directory;
    if (name != null) result.name = name;
    return result;
  }

  ImportInstanceRequest._();

  factory ImportInstanceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImportInstanceRequest()..mergeFromBuffer(data, registry);
  factory ImportInstanceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImportInstanceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImportInstanceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ImportInstanceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'directory')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportInstanceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportInstanceRequest copyWith(
          void Function(ImportInstanceRequest) updates) =>
      super.copyWith((message) => updates(message as ImportInstanceRequest))
          as ImportInstanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ImportInstanceRequest() / ImportInstanceRequest.new instead')
  static ImportInstanceRequest create() => ImportInstanceRequest._();
  static $pb.GeneratedMessage $_createMessage() => ImportInstanceRequest._();
  @$core.override
  ImportInstanceRequest createEmptyInstance() => ImportInstanceRequest._();
  @$core.pragma('dart2js:noInline')
  static ImportInstanceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImportInstanceRequest>(
          ImportInstanceRequest.$_createMessage);
  static ImportInstanceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get directory => $_getSZ(0);
  @$pb.TagNumber(1)
  set directory($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDirectory() => $_has(0);
  @$pb.TagNumber(1)
  void clearDirectory() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);
}

class ImportInstanceResponse extends $pb.GeneratedMessage {
  factory ImportInstanceResponse({
    Instance? instance,
    $core.Iterable<$core.String>? secretsToSet,
  }) {
    final result = ImportInstanceResponse._();
    if (instance != null) result.instance = instance;
    if (secretsToSet != null) result.secretsToSet.addAll(secretsToSet);
    return result;
  }

  ImportInstanceResponse._();

  factory ImportInstanceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImportInstanceResponse()..mergeFromBuffer(data, registry);
  factory ImportInstanceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImportInstanceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImportInstanceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ImportInstanceResponse.$_createMessage)
    ..aOM<Instance>(1, _omitFieldNames ? '' : 'instance',
        subBuilder: Instance.$_createMessage)
    ..pPS(2, _omitFieldNames ? '' : 'secretsToSet')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportInstanceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportInstanceResponse copyWith(
          void Function(ImportInstanceResponse) updates) =>
      super.copyWith((message) => updates(message as ImportInstanceResponse))
          as ImportInstanceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ImportInstanceResponse() / ImportInstanceResponse.new instead')
  static ImportInstanceResponse create() => ImportInstanceResponse._();
  static $pb.GeneratedMessage $_createMessage() => ImportInstanceResponse._();
  @$core.override
  ImportInstanceResponse createEmptyInstance() => ImportInstanceResponse._();
  @$core.pragma('dart2js:noInline')
  static ImportInstanceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImportInstanceResponse>(
          ImportInstanceResponse.$_createMessage);
  static ImportInstanceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Instance get instance => $_getN(0);
  @$pb.TagNumber(1)
  set instance(Instance value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasInstance() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstance() => $_clearField(1);
  @$pb.TagNumber(1)
  Instance ensureInstance() => $_ensure(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get secretsToSet => $_getList(1);
}

class ExportInstanceRequest extends $pb.GeneratedMessage {
  factory ExportInstanceRequest({
    $core.String? instanceId,
  }) {
    final result = ExportInstanceRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    return result;
  }

  ExportInstanceRequest._();

  factory ExportInstanceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExportInstanceRequest()..mergeFromBuffer(data, registry);
  factory ExportInstanceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExportInstanceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExportInstanceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ExportInstanceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportInstanceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportInstanceRequest copyWith(
          void Function(ExportInstanceRequest) updates) =>
      super.copyWith((message) => updates(message as ExportInstanceRequest))
          as ExportInstanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ExportInstanceRequest() / ExportInstanceRequest.new instead')
  static ExportInstanceRequest create() => ExportInstanceRequest._();
  static $pb.GeneratedMessage $_createMessage() => ExportInstanceRequest._();
  @$core.override
  ExportInstanceRequest createEmptyInstance() => ExportInstanceRequest._();
  @$core.pragma('dart2js:noInline')
  static ExportInstanceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExportInstanceRequest>(
          ExportInstanceRequest.$_createMessage);
  static ExportInstanceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);
}

class ExportInstanceResponse extends $pb.GeneratedMessage {
  factory ExportInstanceResponse({
    $core.String? instanceJson,
  }) {
    final result = ExportInstanceResponse._();
    if (instanceJson != null) result.instanceJson = instanceJson;
    return result;
  }

  ExportInstanceResponse._();

  factory ExportInstanceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExportInstanceResponse()..mergeFromBuffer(data, registry);
  factory ExportInstanceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExportInstanceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExportInstanceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ExportInstanceResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportInstanceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportInstanceResponse copyWith(
          void Function(ExportInstanceResponse) updates) =>
      super.copyWith((message) => updates(message as ExportInstanceResponse))
          as ExportInstanceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ExportInstanceResponse() / ExportInstanceResponse.new instead')
  static ExportInstanceResponse create() => ExportInstanceResponse._();
  static $pb.GeneratedMessage $_createMessage() => ExportInstanceResponse._();
  @$core.override
  ExportInstanceResponse createEmptyInstance() => ExportInstanceResponse._();
  @$core.pragma('dart2js:noInline')
  static ExportInstanceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExportInstanceResponse>(
          ExportInstanceResponse.$_createMessage);
  static ExportInstanceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceJson => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceJson($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceJson() => $_clearField(1);
}

class LifecycleRequest extends $pb.GeneratedMessage {
  factory LifecycleRequest({
    $core.String? instanceId,
    $core.bool? validateFiles,
    $core.bool? force,
    $core.bool? skipSnapshot,
  }) {
    final result = LifecycleRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (validateFiles != null) result.validateFiles = validateFiles;
    if (force != null) result.force = force;
    if (skipSnapshot != null) result.skipSnapshot = skipSnapshot;
    return result;
  }

  LifecycleRequest._();

  factory LifecycleRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LifecycleRequest()..mergeFromBuffer(data, registry);
  factory LifecycleRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LifecycleRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LifecycleRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: LifecycleRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOB(2, _omitFieldNames ? '' : 'validateFiles')
    ..aOB(3, _omitFieldNames ? '' : 'force')
    ..aOB(4, _omitFieldNames ? '' : 'skipSnapshot')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LifecycleRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LifecycleRequest copyWith(void Function(LifecycleRequest) updates) =>
      super.copyWith((message) => updates(message as LifecycleRequest))
          as LifecycleRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LifecycleRequest() / LifecycleRequest.new instead')
  static LifecycleRequest create() => LifecycleRequest._();
  static $pb.GeneratedMessage $_createMessage() => LifecycleRequest._();
  @$core.override
  LifecycleRequest createEmptyInstance() => LifecycleRequest._();
  @$core.pragma('dart2js:noInline')
  static LifecycleRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LifecycleRequest>(
          LifecycleRequest.$_createMessage);
  static LifecycleRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get validateFiles => $_getBF(1);
  @$pb.TagNumber(2)
  set validateFiles($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValidateFiles() => $_has(1);
  @$pb.TagNumber(2)
  void clearValidateFiles() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get force => $_getBF(2);
  @$pb.TagNumber(3)
  set force($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasForce() => $_has(2);
  @$pb.TagNumber(3)
  void clearForce() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get skipSnapshot => $_getBF(3);
  @$pb.TagNumber(4)
  set skipSnapshot($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSkipSnapshot() => $_has(3);
  @$pb.TagNumber(4)
  void clearSkipSnapshot() => $_clearField(4);
}

class Snapshot extends $pb.GeneratedMessage {
  factory Snapshot({
    $core.String? id,
    $core.String? reason,
    $3.Timestamp? createdAt,
    $fixnum.Int64? sizeBytes,
    $core.String? instanceId,
    $core.String? instanceName,
  }) {
    final result = Snapshot._();
    if (id != null) result.id = id;
    if (reason != null) result.reason = reason;
    if (createdAt != null) result.createdAt = createdAt;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (instanceId != null) result.instanceId = instanceId;
    if (instanceName != null) result.instanceName = instanceName;
    return result;
  }

  Snapshot._();

  factory Snapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Snapshot()..mergeFromBuffer(data, registry);
  factory Snapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Snapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Snapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Snapshot.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..aOM<$3.Timestamp>(3, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $3.Timestamp.$_createMessage)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'sizeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(5, _omitFieldNames ? '' : 'instanceId')
    ..aOS(6, _omitFieldNames ? '' : 'instanceName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Snapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Snapshot copyWith(void Function(Snapshot) updates) =>
      super.copyWith((message) => updates(message as Snapshot)) as Snapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Snapshot() / Snapshot.new instead')
  static Snapshot create() => Snapshot._();
  static $pb.GeneratedMessage $_createMessage() => Snapshot._();
  @$core.override
  Snapshot createEmptyInstance() => Snapshot._();
  @$core.pragma('dart2js:noInline')
  static Snapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Snapshot>(Snapshot.$_createMessage);
  static Snapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);

  @$pb.TagNumber(3)
  $3.Timestamp get createdAt => $_getN(2);
  @$pb.TagNumber(3)
  set createdAt($3.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCreatedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatedAt() => $_clearField(3);
  @$pb.TagNumber(3)
  $3.Timestamp ensureCreatedAt() => $_ensure(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearSizeBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get instanceId => $_getSZ(4);
  @$pb.TagNumber(5)
  set instanceId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasInstanceId() => $_has(4);
  @$pb.TagNumber(5)
  void clearInstanceId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get instanceName => $_getSZ(5);
  @$pb.TagNumber(6)
  set instanceName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasInstanceName() => $_has(5);
  @$pb.TagNumber(6)
  void clearInstanceName() => $_clearField(6);
}

class ListSnapshotsResponse extends $pb.GeneratedMessage {
  factory ListSnapshotsResponse({
    $core.Iterable<Snapshot>? snapshots,
  }) {
    final result = ListSnapshotsResponse._();
    if (snapshots != null) result.snapshots.addAll(snapshots);
    return result;
  }

  ListSnapshotsResponse._();

  factory ListSnapshotsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSnapshotsResponse()..mergeFromBuffer(data, registry);
  factory ListSnapshotsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSnapshotsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSnapshotsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListSnapshotsResponse.$_createMessage)
    ..pPM<Snapshot>(1, _omitFieldNames ? '' : 'snapshots',
        subBuilder: Snapshot.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSnapshotsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSnapshotsResponse copyWith(
          void Function(ListSnapshotsResponse) updates) =>
      super.copyWith((message) => updates(message as ListSnapshotsResponse))
          as ListSnapshotsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListSnapshotsResponse() / ListSnapshotsResponse.new instead')
  static ListSnapshotsResponse create() => ListSnapshotsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListSnapshotsResponse._();
  @$core.override
  ListSnapshotsResponse createEmptyInstance() => ListSnapshotsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListSnapshotsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSnapshotsResponse>(
          ListSnapshotsResponse.$_createMessage);
  static ListSnapshotsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Snapshot> get snapshots => $_getList(0);
}

class RestoreSnapshotRequest extends $pb.GeneratedMessage {
  factory RestoreSnapshotRequest({
    $core.String? instanceId,
    $core.String? snapshotId,
    $fixnum.Int64? expectedRevision,
  }) {
    final result = RestoreSnapshotRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (snapshotId != null) result.snapshotId = snapshotId;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    return result;
  }

  RestoreSnapshotRequest._();

  factory RestoreSnapshotRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RestoreSnapshotRequest()..mergeFromBuffer(data, registry);
  factory RestoreSnapshotRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RestoreSnapshotRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RestoreSnapshotRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: RestoreSnapshotRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'snapshotId')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RestoreSnapshotRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RestoreSnapshotRequest copyWith(
          void Function(RestoreSnapshotRequest) updates) =>
      super.copyWith((message) => updates(message as RestoreSnapshotRequest))
          as RestoreSnapshotRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RestoreSnapshotRequest() / RestoreSnapshotRequest.new instead')
  static RestoreSnapshotRequest create() => RestoreSnapshotRequest._();
  static $pb.GeneratedMessage $_createMessage() => RestoreSnapshotRequest._();
  @$core.override
  RestoreSnapshotRequest createEmptyInstance() => RestoreSnapshotRequest._();
  @$core.pragma('dart2js:noInline')
  static RestoreSnapshotRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RestoreSnapshotRequest>(
          RestoreSnapshotRequest.$_createMessage);
  static RestoreSnapshotRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get snapshotId => $_getSZ(1);
  @$pb.TagNumber(2)
  set snapshotId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSnapshotId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnapshotId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expectedRevision => $_getI64(2);
  @$pb.TagNumber(3)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedRevision() => $_clearField(3);
}

class ListOrphanSnapshotsRequest extends $pb.GeneratedMessage {
  factory ListOrphanSnapshotsRequest() => ListOrphanSnapshotsRequest._();

  ListOrphanSnapshotsRequest._();

  factory ListOrphanSnapshotsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListOrphanSnapshotsRequest()..mergeFromBuffer(data, registry);
  factory ListOrphanSnapshotsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListOrphanSnapshotsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListOrphanSnapshotsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListOrphanSnapshotsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOrphanSnapshotsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOrphanSnapshotsRequest copyWith(
          void Function(ListOrphanSnapshotsRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ListOrphanSnapshotsRequest))
          as ListOrphanSnapshotsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListOrphanSnapshotsRequest() / ListOrphanSnapshotsRequest.new instead')
  static ListOrphanSnapshotsRequest create() => ListOrphanSnapshotsRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ListOrphanSnapshotsRequest._();
  @$core.override
  ListOrphanSnapshotsRequest createEmptyInstance() =>
      ListOrphanSnapshotsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListOrphanSnapshotsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListOrphanSnapshotsRequest>(
          ListOrphanSnapshotsRequest.$_createMessage);
  static ListOrphanSnapshotsRequest? _defaultInstance;
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
