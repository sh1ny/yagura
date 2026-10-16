// This is a generated file - do not edit.
//
// Generated from yagura/v1/mods.proto.

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
    as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Mod extends $pb.GeneratedMessage {
  factory Mod({
    $core.String? source,
    $core.String? itemId,
    $core.String? name,
    $core.String? role,
    $core.int? position,
    $core.String? status,
    $core.String? stagedName,
    $fixnum.Int64? sizeBytes,
    $2.Timestamp? localUpdated,
    $2.Timestamp? remoteUpdated,
    $core.bool? updateAvailable,
    $core.String? lastError,
    $core.String? desiredVersion,
    $core.String? stagedVersion,
  }) {
    final result = Mod._();
    if (source != null) result.source = source;
    if (itemId != null) result.itemId = itemId;
    if (name != null) result.name = name;
    if (role != null) result.role = role;
    if (position != null) result.position = position;
    if (status != null) result.status = status;
    if (stagedName != null) result.stagedName = stagedName;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (localUpdated != null) result.localUpdated = localUpdated;
    if (remoteUpdated != null) result.remoteUpdated = remoteUpdated;
    if (updateAvailable != null) result.updateAvailable = updateAvailable;
    if (lastError != null) result.lastError = lastError;
    if (desiredVersion != null) result.desiredVersion = desiredVersion;
    if (stagedVersion != null) result.stagedVersion = stagedVersion;
    return result;
  }

  Mod._();

  factory Mod.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Mod()..mergeFromBuffer(data, registry);
  factory Mod.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Mod()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Mod',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Mod.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..aOS(2, _omitFieldNames ? '' : 'itemId')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aOS(4, _omitFieldNames ? '' : 'role')
    ..aI(5, _omitFieldNames ? '' : 'position', fieldType: $pb.PbFieldType.OU3)
    ..aOS(6, _omitFieldNames ? '' : 'status')
    ..aOS(7, _omitFieldNames ? '' : 'stagedName')
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'sizeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$2.Timestamp>(9, _omitFieldNames ? '' : 'localUpdated',
        subBuilder: $2.Timestamp.$_createMessage)
    ..aOM<$2.Timestamp>(10, _omitFieldNames ? '' : 'remoteUpdated',
        subBuilder: $2.Timestamp.$_createMessage)
    ..aOB(11, _omitFieldNames ? '' : 'updateAvailable')
    ..aOS(12, _omitFieldNames ? '' : 'lastError')
    ..aOS(13, _omitFieldNames ? '' : 'desiredVersion')
    ..aOS(14, _omitFieldNames ? '' : 'stagedVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mod clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mod copyWith(void Function(Mod) updates) =>
      super.copyWith((message) => updates(message as Mod)) as Mod;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Mod() / Mod.new instead')
  static Mod create() => Mod._();
  static $pb.GeneratedMessage $_createMessage() => Mod._();
  @$core.override
  Mod createEmptyInstance() => Mod._();
  @$core.pragma('dart2js:noInline')
  static Mod getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Mod>(Mod.$_createMessage);
  static Mod? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get itemId => $_getSZ(1);
  @$pb.TagNumber(2)
  set itemId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasItemId() => $_has(1);
  @$pb.TagNumber(2)
  void clearItemId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get role => $_getSZ(3);
  @$pb.TagNumber(4)
  set role($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRole() => $_has(3);
  @$pb.TagNumber(4)
  void clearRole() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get position => $_getIZ(4);
  @$pb.TagNumber(5)
  set position($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPosition() => $_has(4);
  @$pb.TagNumber(5)
  void clearPosition() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get status => $_getSZ(5);
  @$pb.TagNumber(6)
  set status($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatus() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get stagedName => $_getSZ(6);
  @$pb.TagNumber(7)
  set stagedName($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStagedName() => $_has(6);
  @$pb.TagNumber(7)
  void clearStagedName() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get sizeBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSizeBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearSizeBytes() => $_clearField(8);

  @$pb.TagNumber(9)
  $2.Timestamp get localUpdated => $_getN(8);
  @$pb.TagNumber(9)
  set localUpdated($2.Timestamp value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasLocalUpdated() => $_has(8);
  @$pb.TagNumber(9)
  void clearLocalUpdated() => $_clearField(9);
  @$pb.TagNumber(9)
  $2.Timestamp ensureLocalUpdated() => $_ensure(8);

  @$pb.TagNumber(10)
  $2.Timestamp get remoteUpdated => $_getN(9);
  @$pb.TagNumber(10)
  set remoteUpdated($2.Timestamp value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasRemoteUpdated() => $_has(9);
  @$pb.TagNumber(10)
  void clearRemoteUpdated() => $_clearField(10);
  @$pb.TagNumber(10)
  $2.Timestamp ensureRemoteUpdated() => $_ensure(9);

  @$pb.TagNumber(11)
  $core.bool get updateAvailable => $_getBF(10);
  @$pb.TagNumber(11)
  set updateAvailable($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasUpdateAvailable() => $_has(10);
  @$pb.TagNumber(11)
  void clearUpdateAvailable() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get lastError => $_getSZ(11);
  @$pb.TagNumber(12)
  set lastError($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasLastError() => $_has(11);
  @$pb.TagNumber(12)
  void clearLastError() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get desiredVersion => $_getSZ(12);
  @$pb.TagNumber(13)
  set desiredVersion($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasDesiredVersion() => $_has(12);
  @$pb.TagNumber(13)
  void clearDesiredVersion() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get stagedVersion => $_getSZ(13);
  @$pb.TagNumber(14)
  set stagedVersion($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasStagedVersion() => $_has(13);
  @$pb.TagNumber(14)
  void clearStagedVersion() => $_clearField(14);
}

class ListModsRequest extends $pb.GeneratedMessage {
  factory ListModsRequest({
    $core.String? instanceId,
  }) {
    final result = ListModsRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    return result;
  }

  ListModsRequest._();

  factory ListModsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListModsRequest()..mergeFromBuffer(data, registry);
  factory ListModsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListModsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListModsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListModsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListModsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListModsRequest copyWith(void Function(ListModsRequest) updates) =>
      super.copyWith((message) => updates(message as ListModsRequest))
          as ListModsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListModsRequest() / ListModsRequest.new instead')
  static ListModsRequest create() => ListModsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListModsRequest._();
  @$core.override
  ListModsRequest createEmptyInstance() => ListModsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListModsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListModsRequest>(
          ListModsRequest.$_createMessage);
  static ListModsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);
}

class ListModsResponse extends $pb.GeneratedMessage {
  factory ListModsResponse({
    $core.Iterable<Mod>? mods,
    $core.String? updateCheck,
    $2.Timestamp? checkedAt,
  }) {
    final result = ListModsResponse._();
    if (mods != null) result.mods.addAll(mods);
    if (updateCheck != null) result.updateCheck = updateCheck;
    if (checkedAt != null) result.checkedAt = checkedAt;
    return result;
  }

  ListModsResponse._();

  factory ListModsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListModsResponse()..mergeFromBuffer(data, registry);
  factory ListModsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListModsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListModsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListModsResponse.$_createMessage)
    ..pPM<Mod>(1, _omitFieldNames ? '' : 'mods',
        subBuilder: Mod.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'updateCheck')
    ..aOM<$2.Timestamp>(3, _omitFieldNames ? '' : 'checkedAt',
        subBuilder: $2.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListModsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListModsResponse copyWith(void Function(ListModsResponse) updates) =>
      super.copyWith((message) => updates(message as ListModsResponse))
          as ListModsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListModsResponse() / ListModsResponse.new instead')
  static ListModsResponse create() => ListModsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListModsResponse._();
  @$core.override
  ListModsResponse createEmptyInstance() => ListModsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListModsResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListModsResponse>(
          ListModsResponse.$_createMessage);
  static ListModsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Mod> get mods => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get updateCheck => $_getSZ(1);
  @$pb.TagNumber(2)
  set updateCheck($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUpdateCheck() => $_has(1);
  @$pb.TagNumber(2)
  void clearUpdateCheck() => $_clearField(2);

  @$pb.TagNumber(3)
  $2.Timestamp get checkedAt => $_getN(2);
  @$pb.TagNumber(3)
  set checkedAt($2.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCheckedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearCheckedAt() => $_clearField(3);
  @$pb.TagNumber(3)
  $2.Timestamp ensureCheckedAt() => $_ensure(2);
}

class ModRef extends $pb.GeneratedMessage {
  factory ModRef({
    $core.String? source,
    $core.String? itemId,
    $core.String? role,
  }) {
    final result = ModRef._();
    if (source != null) result.source = source;
    if (itemId != null) result.itemId = itemId;
    if (role != null) result.role = role;
    return result;
  }

  ModRef._();

  factory ModRef.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ModRef()..mergeFromBuffer(data, registry);
  factory ModRef.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ModRef()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModRef',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ModRef.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..aOS(2, _omitFieldNames ? '' : 'itemId')
    ..aOS(3, _omitFieldNames ? '' : 'role')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModRef clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModRef copyWith(void Function(ModRef) updates) =>
      super.copyWith((message) => updates(message as ModRef)) as ModRef;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ModRef() / ModRef.new instead')
  static ModRef create() => ModRef._();
  static $pb.GeneratedMessage $_createMessage() => ModRef._();
  @$core.override
  ModRef createEmptyInstance() => ModRef._();
  @$core.pragma('dart2js:noInline')
  static ModRef getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModRef>(ModRef.$_createMessage);
  static ModRef? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get itemId => $_getSZ(1);
  @$pb.TagNumber(2)
  set itemId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasItemId() => $_has(1);
  @$pb.TagNumber(2)
  void clearItemId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get role => $_getSZ(2);
  @$pb.TagNumber(3)
  set role($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => $_clearField(3);
}

class SetModsRequest extends $pb.GeneratedMessage {
  factory SetModsRequest({
    $core.String? instanceId,
    $core.Iterable<ModRef>? mods,
    $fixnum.Int64? expectedRevision,
  }) {
    final result = SetModsRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (mods != null) result.mods.addAll(mods);
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    return result;
  }

  SetModsRequest._();

  factory SetModsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetModsRequest()..mergeFromBuffer(data, registry);
  factory SetModsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetModsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetModsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: SetModsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..pPM<ModRef>(2, _omitFieldNames ? '' : 'mods',
        subBuilder: ModRef.$_createMessage)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetModsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetModsRequest copyWith(void Function(SetModsRequest) updates) =>
      super.copyWith((message) => updates(message as SetModsRequest))
          as SetModsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetModsRequest() / SetModsRequest.new instead')
  static SetModsRequest create() => SetModsRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetModsRequest._();
  @$core.override
  SetModsRequest createEmptyInstance() => SetModsRequest._();
  @$core.pragma('dart2js:noInline')
  static SetModsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetModsRequest>(
          SetModsRequest.$_createMessage);
  static SetModsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ModRef> get mods => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expectedRevision => $_getI64(2);
  @$pb.TagNumber(3)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedRevision() => $_clearField(3);
}

class ApplyModsRequest extends $pb.GeneratedMessage {
  factory ApplyModsRequest({
    $core.String? instanceId,
  }) {
    final result = ApplyModsRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    return result;
  }

  ApplyModsRequest._();

  factory ApplyModsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApplyModsRequest()..mergeFromBuffer(data, registry);
  factory ApplyModsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApplyModsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApplyModsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ApplyModsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApplyModsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApplyModsRequest copyWith(void Function(ApplyModsRequest) updates) =>
      super.copyWith((message) => updates(message as ApplyModsRequest))
          as ApplyModsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ApplyModsRequest() / ApplyModsRequest.new instead')
  static ApplyModsRequest create() => ApplyModsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ApplyModsRequest._();
  @$core.override
  ApplyModsRequest createEmptyInstance() => ApplyModsRequest._();
  @$core.pragma('dart2js:noInline')
  static ApplyModsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ApplyModsRequest>(
          ApplyModsRequest.$_createMessage);
  static ApplyModsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);
}

class CheckModUpdatesRequest extends $pb.GeneratedMessage {
  factory CheckModUpdatesRequest({
    $core.String? instanceId,
  }) {
    final result = CheckModUpdatesRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    return result;
  }

  CheckModUpdatesRequest._();

  factory CheckModUpdatesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckModUpdatesRequest()..mergeFromBuffer(data, registry);
  factory CheckModUpdatesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckModUpdatesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckModUpdatesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: CheckModUpdatesRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckModUpdatesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckModUpdatesRequest copyWith(
          void Function(CheckModUpdatesRequest) updates) =>
      super.copyWith((message) => updates(message as CheckModUpdatesRequest))
          as CheckModUpdatesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CheckModUpdatesRequest() / CheckModUpdatesRequest.new instead')
  static CheckModUpdatesRequest create() => CheckModUpdatesRequest._();
  static $pb.GeneratedMessage $_createMessage() => CheckModUpdatesRequest._();
  @$core.override
  CheckModUpdatesRequest createEmptyInstance() => CheckModUpdatesRequest._();
  @$core.pragma('dart2js:noInline')
  static CheckModUpdatesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckModUpdatesRequest>(
          CheckModUpdatesRequest.$_createMessage);
  static CheckModUpdatesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);
}

class UpdateModsRequest extends $pb.GeneratedMessage {
  factory UpdateModsRequest({
    $core.String? instanceId,
    $core.Iterable<$core.String>? itemIds,
  }) {
    final result = UpdateModsRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (itemIds != null) result.itemIds.addAll(itemIds);
    return result;
  }

  UpdateModsRequest._();

  factory UpdateModsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateModsRequest()..mergeFromBuffer(data, registry);
  factory UpdateModsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateModsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateModsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: UpdateModsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..pPS(2, _omitFieldNames ? '' : 'itemIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateModsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateModsRequest copyWith(void Function(UpdateModsRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateModsRequest))
          as UpdateModsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UpdateModsRequest() / UpdateModsRequest.new instead')
  static UpdateModsRequest create() => UpdateModsRequest._();
  static $pb.GeneratedMessage $_createMessage() => UpdateModsRequest._();
  @$core.override
  UpdateModsRequest createEmptyInstance() => UpdateModsRequest._();
  @$core.pragma('dart2js:noInline')
  static UpdateModsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UpdateModsRequest>(
          UpdateModsRequest.$_createMessage);
  static UpdateModsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get itemIds => $_getList(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
