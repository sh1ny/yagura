// This is a generated file - do not edit.
//
// Generated from yagura/v1/system.proto.

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
    as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GetInfoRequest extends $pb.GeneratedMessage {
  factory GetInfoRequest() => GetInfoRequest._();

  GetInfoRequest._();

  factory GetInfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetInfoRequest()..mergeFromBuffer(data, registry);
  factory GetInfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetInfoRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetInfoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: GetInfoRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetInfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetInfoRequest copyWith(void Function(GetInfoRequest) updates) =>
      super.copyWith((message) => updates(message as GetInfoRequest))
          as GetInfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetInfoRequest() / GetInfoRequest.new instead')
  static GetInfoRequest create() => GetInfoRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetInfoRequest._();
  @$core.override
  GetInfoRequest createEmptyInstance() => GetInfoRequest._();
  @$core.pragma('dart2js:noInline')
  static GetInfoRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetInfoRequest>(
          GetInfoRequest.$_createMessage);
  static GetInfoRequest? _defaultInstance;
}

class DaemonInfo extends $pb.GeneratedMessage {
  factory DaemonInfo({
    $core.String? daemonVersion,
    $core.String? apiVersion,
    $core.String? hostName,
    $core.String? os,
    $core.String? osVersion,
    $core.String? dataDir,
    $1.Timestamp? startedAt,
    $core.bool? devMode,
    $core.Iterable<$core.String>? apiVersions,
  }) {
    final result = DaemonInfo._();
    if (daemonVersion != null) result.daemonVersion = daemonVersion;
    if (apiVersion != null) result.apiVersion = apiVersion;
    if (hostName != null) result.hostName = hostName;
    if (os != null) result.os = os;
    if (osVersion != null) result.osVersion = osVersion;
    if (dataDir != null) result.dataDir = dataDir;
    if (startedAt != null) result.startedAt = startedAt;
    if (devMode != null) result.devMode = devMode;
    if (apiVersions != null) result.apiVersions.addAll(apiVersions);
    return result;
  }

  DaemonInfo._();

  factory DaemonInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DaemonInfo()..mergeFromBuffer(data, registry);
  factory DaemonInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DaemonInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DaemonInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: DaemonInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'daemonVersion')
    ..aOS(2, _omitFieldNames ? '' : 'apiVersion')
    ..aOS(3, _omitFieldNames ? '' : 'hostName')
    ..aOS(4, _omitFieldNames ? '' : 'os')
    ..aOS(5, _omitFieldNames ? '' : 'osVersion')
    ..aOS(6, _omitFieldNames ? '' : 'dataDir')
    ..aOM<$1.Timestamp>(7, _omitFieldNames ? '' : 'startedAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOB(8, _omitFieldNames ? '' : 'devMode')
    ..pPS(9, _omitFieldNames ? '' : 'apiVersions')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DaemonInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DaemonInfo copyWith(void Function(DaemonInfo) updates) =>
      super.copyWith((message) => updates(message as DaemonInfo)) as DaemonInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DaemonInfo() / DaemonInfo.new instead')
  static DaemonInfo create() => DaemonInfo._();
  static $pb.GeneratedMessage $_createMessage() => DaemonInfo._();
  @$core.override
  DaemonInfo createEmptyInstance() => DaemonInfo._();
  @$core.pragma('dart2js:noInline')
  static DaemonInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DaemonInfo>(DaemonInfo.$_createMessage);
  static DaemonInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get daemonVersion => $_getSZ(0);
  @$pb.TagNumber(1)
  set daemonVersion($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDaemonVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearDaemonVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get apiVersion => $_getSZ(1);
  @$pb.TagNumber(2)
  set apiVersion($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasApiVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearApiVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get hostName => $_getSZ(2);
  @$pb.TagNumber(3)
  set hostName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHostName() => $_has(2);
  @$pb.TagNumber(3)
  void clearHostName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get os => $_getSZ(3);
  @$pb.TagNumber(4)
  set os($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOs() => $_has(3);
  @$pb.TagNumber(4)
  void clearOs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get osVersion => $_getSZ(4);
  @$pb.TagNumber(5)
  set osVersion($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOsVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearOsVersion() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get dataDir => $_getSZ(5);
  @$pb.TagNumber(6)
  set dataDir($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDataDir() => $_has(5);
  @$pb.TagNumber(6)
  void clearDataDir() => $_clearField(6);

  @$pb.TagNumber(7)
  $1.Timestamp get startedAt => $_getN(6);
  @$pb.TagNumber(7)
  set startedAt($1.Timestamp value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasStartedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearStartedAt() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.Timestamp ensureStartedAt() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.bool get devMode => $_getBF(7);
  @$pb.TagNumber(8)
  set devMode($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDevMode() => $_has(7);
  @$pb.TagNumber(8)
  void clearDevMode() => $_clearField(8);

  @$pb.TagNumber(9)
  $pb.PbList<$core.String> get apiVersions => $_getList(8);
}

class GetHealthRequest extends $pb.GeneratedMessage {
  factory GetHealthRequest() => GetHealthRequest._();

  GetHealthRequest._();

  factory GetHealthRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetHealthRequest()..mergeFromBuffer(data, registry);
  factory GetHealthRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetHealthRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetHealthRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: GetHealthRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetHealthRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetHealthRequest copyWith(void Function(GetHealthRequest) updates) =>
      super.copyWith((message) => updates(message as GetHealthRequest))
          as GetHealthRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetHealthRequest() / GetHealthRequest.new instead')
  static GetHealthRequest create() => GetHealthRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetHealthRequest._();
  @$core.override
  GetHealthRequest createEmptyInstance() => GetHealthRequest._();
  @$core.pragma('dart2js:noInline')
  static GetHealthRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetHealthRequest>(
          GetHealthRequest.$_createMessage);
  static GetHealthRequest? _defaultInstance;
}

class DaemonHealth extends $pb.GeneratedMessage {
  factory DaemonHealth({
    $core.bool? databaseOk,
    $core.bool? secretStoreOk,
    $core.bool? firewallOk,
    $fixnum.Int64? dataVolumeFreeBytes,
    $core.int? runningInstances,
    $core.int? queuedOperations,
    $core.int? leakedHookWorkers,
    $core.bool? hooksDegraded,
    $core.bool? pluginsOk,
    $core.Iterable<$core.String>? notBuilt,
    $core.bool? adminChannelOk,
    $core.bool? serviceAccountsOk,
    $1.Timestamp? serverCertNotAfter,
  }) {
    final result = DaemonHealth._();
    if (databaseOk != null) result.databaseOk = databaseOk;
    if (secretStoreOk != null) result.secretStoreOk = secretStoreOk;
    if (firewallOk != null) result.firewallOk = firewallOk;
    if (dataVolumeFreeBytes != null)
      result.dataVolumeFreeBytes = dataVolumeFreeBytes;
    if (runningInstances != null) result.runningInstances = runningInstances;
    if (queuedOperations != null) result.queuedOperations = queuedOperations;
    if (leakedHookWorkers != null) result.leakedHookWorkers = leakedHookWorkers;
    if (hooksDegraded != null) result.hooksDegraded = hooksDegraded;
    if (pluginsOk != null) result.pluginsOk = pluginsOk;
    if (notBuilt != null) result.notBuilt.addAll(notBuilt);
    if (adminChannelOk != null) result.adminChannelOk = adminChannelOk;
    if (serviceAccountsOk != null) result.serviceAccountsOk = serviceAccountsOk;
    if (serverCertNotAfter != null)
      result.serverCertNotAfter = serverCertNotAfter;
    return result;
  }

  DaemonHealth._();

  factory DaemonHealth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DaemonHealth()..mergeFromBuffer(data, registry);
  factory DaemonHealth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DaemonHealth()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DaemonHealth',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: DaemonHealth.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'databaseOk')
    ..aOB(2, _omitFieldNames ? '' : 'secretStoreOk')
    ..aOB(3, _omitFieldNames ? '' : 'firewallOk')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'dataVolumeFreeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(5, _omitFieldNames ? '' : 'runningInstances',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'queuedOperations',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'leakedHookWorkers',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(8, _omitFieldNames ? '' : 'hooksDegraded')
    ..aOB(9, _omitFieldNames ? '' : 'pluginsOk')
    ..pPS(10, _omitFieldNames ? '' : 'notBuilt')
    ..aOB(11, _omitFieldNames ? '' : 'adminChannelOk')
    ..aOB(12, _omitFieldNames ? '' : 'serviceAccountsOk')
    ..aOM<$1.Timestamp>(13, _omitFieldNames ? '' : 'serverCertNotAfter',
        subBuilder: $1.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DaemonHealth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DaemonHealth copyWith(void Function(DaemonHealth) updates) =>
      super.copyWith((message) => updates(message as DaemonHealth))
          as DaemonHealth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DaemonHealth() / DaemonHealth.new instead')
  static DaemonHealth create() => DaemonHealth._();
  static $pb.GeneratedMessage $_createMessage() => DaemonHealth._();
  @$core.override
  DaemonHealth createEmptyInstance() => DaemonHealth._();
  @$core.pragma('dart2js:noInline')
  static DaemonHealth getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DaemonHealth>(
          DaemonHealth.$_createMessage);
  static DaemonHealth? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get databaseOk => $_getBF(0);
  @$pb.TagNumber(1)
  set databaseOk($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDatabaseOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearDatabaseOk() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get secretStoreOk => $_getBF(1);
  @$pb.TagNumber(2)
  set secretStoreOk($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSecretStoreOk() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecretStoreOk() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get firewallOk => $_getBF(2);
  @$pb.TagNumber(3)
  set firewallOk($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFirewallOk() => $_has(2);
  @$pb.TagNumber(3)
  void clearFirewallOk() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get dataVolumeFreeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set dataVolumeFreeBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDataVolumeFreeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearDataVolumeFreeBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get runningInstances => $_getIZ(4);
  @$pb.TagNumber(5)
  set runningInstances($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRunningInstances() => $_has(4);
  @$pb.TagNumber(5)
  void clearRunningInstances() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get queuedOperations => $_getIZ(5);
  @$pb.TagNumber(6)
  set queuedOperations($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasQueuedOperations() => $_has(5);
  @$pb.TagNumber(6)
  void clearQueuedOperations() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get leakedHookWorkers => $_getIZ(6);
  @$pb.TagNumber(7)
  set leakedHookWorkers($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLeakedHookWorkers() => $_has(6);
  @$pb.TagNumber(7)
  void clearLeakedHookWorkers() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get hooksDegraded => $_getBF(7);
  @$pb.TagNumber(8)
  set hooksDegraded($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHooksDegraded() => $_has(7);
  @$pb.TagNumber(8)
  void clearHooksDegraded() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get pluginsOk => $_getBF(8);
  @$pb.TagNumber(9)
  set pluginsOk($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPluginsOk() => $_has(8);
  @$pb.TagNumber(9)
  void clearPluginsOk() => $_clearField(9);

  /// Components this daemon version does not have (for example "secret_store",
  /// "firewall" in M1); their *_ok fields are false and carry no meaning.
  @$pb.TagNumber(10)
  $pb.PbList<$core.String> get notBuilt => $_getList(9);

  /// Service mode only. False when the named pipe of the admin channel is
  /// squatted by another process (notice admin_channel_squatted) or not served.
  @$pb.TagNumber(11)
  $core.bool get adminChannelOk => $_getBF(10);
  @$pb.TagNumber(11)
  set adminChannelOk($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasAdminChannelOk() => $_has(10);
  @$pb.TagNumber(11)
  void clearAdminChannelOk() => $_clearField(11);

  /// The yagura-srv and yagura-steam accounts exist, are configured and their
  /// ACLs are in place (service mode).
  @$pb.TagNumber(12)
  $core.bool get serviceAccountsOk => $_getBF(11);
  @$pb.TagNumber(12)
  set serviceAccountsOk($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasServiceAccountsOk() => $_has(11);
  @$pb.TagNumber(12)
  void clearServiceAccountsOk() => $_clearField(12);

  /// End of the server certificate; unset in dev mode, which serves plaintext.
  @$pb.TagNumber(13)
  $1.Timestamp get serverCertNotAfter => $_getN(12);
  @$pb.TagNumber(13)
  set serverCertNotAfter($1.Timestamp value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasServerCertNotAfter() => $_has(12);
  @$pb.TagNumber(13)
  void clearServerCertNotAfter() => $_clearField(13);
  @$pb.TagNumber(13)
  $1.Timestamp ensureServerCertNotAfter() => $_ensure(12);
}

class ListAuditRequest extends $pb.GeneratedMessage {
  factory ListAuditRequest({
    $core.int? pageSize,
    $core.String? pageToken,
  }) {
    final result = ListAuditRequest._();
    if (pageSize != null) result.pageSize = pageSize;
    if (pageToken != null) result.pageToken = pageToken;
    return result;
  }

  ListAuditRequest._();

  factory ListAuditRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAuditRequest()..mergeFromBuffer(data, registry);
  factory ListAuditRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAuditRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListAuditRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListAuditRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'pageSize', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'pageToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAuditRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAuditRequest copyWith(void Function(ListAuditRequest) updates) =>
      super.copyWith((message) => updates(message as ListAuditRequest))
          as ListAuditRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListAuditRequest() / ListAuditRequest.new instead')
  static ListAuditRequest create() => ListAuditRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListAuditRequest._();
  @$core.override
  ListAuditRequest createEmptyInstance() => ListAuditRequest._();
  @$core.pragma('dart2js:noInline')
  static ListAuditRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListAuditRequest>(
          ListAuditRequest.$_createMessage);
  static ListAuditRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get pageSize => $_getIZ(0);
  @$pb.TagNumber(1)
  set pageSize($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPageSize() => $_has(0);
  @$pb.TagNumber(1)
  void clearPageSize() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get pageToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set pageToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPageToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageToken() => $_clearField(2);
}

class AuditEntry extends $pb.GeneratedMessage {
  factory AuditEntry({
    $1.Timestamp? at,
    $core.String? deviceId,
    $core.String? remoteAddress,
    $core.String? method,
    $core.String? target,
    $core.String? result,
  }) {
    final result$ = AuditEntry._();
    if (at != null) result$.at = at;
    if (deviceId != null) result$.deviceId = deviceId;
    if (remoteAddress != null) result$.remoteAddress = remoteAddress;
    if (method != null) result$.method = method;
    if (target != null) result$.target = target;
    if (result != null) result$.result = result;
    return result$;
  }

  AuditEntry._();

  factory AuditEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AuditEntry()..mergeFromBuffer(data, registry);
  factory AuditEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AuditEntry()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuditEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: AuditEntry.$_createMessage)
    ..aOM<$1.Timestamp>(1, _omitFieldNames ? '' : 'at',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'deviceId')
    ..aOS(3, _omitFieldNames ? '' : 'remoteAddress')
    ..aOS(4, _omitFieldNames ? '' : 'method')
    ..aOS(5, _omitFieldNames ? '' : 'target')
    ..aOS(6, _omitFieldNames ? '' : 'result')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditEntry copyWith(void Function(AuditEntry) updates) =>
      super.copyWith((message) => updates(message as AuditEntry)) as AuditEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AuditEntry() / AuditEntry.new instead')
  static AuditEntry create() => AuditEntry._();
  static $pb.GeneratedMessage $_createMessage() => AuditEntry._();
  @$core.override
  AuditEntry createEmptyInstance() => AuditEntry._();
  @$core.pragma('dart2js:noInline')
  static AuditEntry getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AuditEntry>(AuditEntry.$_createMessage);
  static AuditEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Timestamp get at => $_getN(0);
  @$pb.TagNumber(1)
  set at($1.Timestamp value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAt() => $_has(0);
  @$pb.TagNumber(1)
  void clearAt() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Timestamp ensureAt() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get deviceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get remoteAddress => $_getSZ(2);
  @$pb.TagNumber(3)
  set remoteAddress($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRemoteAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearRemoteAddress() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get method => $_getSZ(3);
  @$pb.TagNumber(4)
  set method($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMethod() => $_has(3);
  @$pb.TagNumber(4)
  void clearMethod() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get target => $_getSZ(4);
  @$pb.TagNumber(5)
  set target($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTarget() => $_has(4);
  @$pb.TagNumber(5)
  void clearTarget() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get result => $_getSZ(5);
  @$pb.TagNumber(6)
  set result($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasResult() => $_has(5);
  @$pb.TagNumber(6)
  void clearResult() => $_clearField(6);
}

class ListAuditResponse extends $pb.GeneratedMessage {
  factory ListAuditResponse({
    $core.Iterable<AuditEntry>? entries,
    $core.String? nextPageToken,
  }) {
    final result = ListAuditResponse._();
    if (entries != null) result.entries.addAll(entries);
    if (nextPageToken != null) result.nextPageToken = nextPageToken;
    return result;
  }

  ListAuditResponse._();

  factory ListAuditResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAuditResponse()..mergeFromBuffer(data, registry);
  factory ListAuditResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAuditResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListAuditResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListAuditResponse.$_createMessage)
    ..pPM<AuditEntry>(1, _omitFieldNames ? '' : 'entries',
        subBuilder: AuditEntry.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'nextPageToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAuditResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAuditResponse copyWith(void Function(ListAuditResponse) updates) =>
      super.copyWith((message) => updates(message as ListAuditResponse))
          as ListAuditResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListAuditResponse() / ListAuditResponse.new instead')
  static ListAuditResponse create() => ListAuditResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListAuditResponse._();
  @$core.override
  ListAuditResponse createEmptyInstance() => ListAuditResponse._();
  @$core.pragma('dart2js:noInline')
  static ListAuditResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListAuditResponse>(
          ListAuditResponse.$_createMessage);
  static ListAuditResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<AuditEntry> get entries => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get nextPageToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set nextPageToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNextPageToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearNextPageToken() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
