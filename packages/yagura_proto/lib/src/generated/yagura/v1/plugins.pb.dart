// This is a generated file - do not edit.
//
// Generated from yagura/v1/plugins.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'common.pb.dart' as $1;
import 'plugins.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'plugins.pbenum.dart';

class PluginProblem extends $pb.GeneratedMessage {
  factory PluginProblem({
    $core.String? reason,
    $core.String? path,
    $core.String? file,
    $core.int? line,
    $core.String? message,
  }) {
    final result = PluginProblem._();
    if (reason != null) result.reason = reason;
    if (path != null) result.path = path;
    if (file != null) result.file = file;
    if (line != null) result.line = line;
    if (message != null) result.message = message;
    return result;
  }

  PluginProblem._();

  factory PluginProblem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginProblem()..mergeFromBuffer(data, registry);
  factory PluginProblem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginProblem()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PluginProblem',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PluginProblem.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'reason')
    ..aOS(2, _omitFieldNames ? '' : 'path')
    ..aOS(3, _omitFieldNames ? '' : 'file')
    ..aI(4, _omitFieldNames ? '' : 'line', fieldType: $pb.PbFieldType.OU3)
    ..aOS(5, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginProblem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginProblem copyWith(void Function(PluginProblem) updates) =>
      super.copyWith((message) => updates(message as PluginProblem))
          as PluginProblem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PluginProblem() / PluginProblem.new instead')
  static PluginProblem create() => PluginProblem._();
  static $pb.GeneratedMessage $_createMessage() => PluginProblem._();
  @$core.override
  PluginProblem createEmptyInstance() => PluginProblem._();
  @$core.pragma('dart2js:noInline')
  static PluginProblem getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PluginProblem>(
          PluginProblem.$_createMessage);
  static PluginProblem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reason => $_getSZ(0);
  @$pb.TagNumber(1)
  set reason($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get path => $_getSZ(1);
  @$pb.TagNumber(2)
  set path($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearPath() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get file => $_getSZ(2);
  @$pb.TagNumber(3)
  set file($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFile() => $_has(2);
  @$pb.TagNumber(3)
  void clearFile() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get line => $_getIZ(3);
  @$pb.TagNumber(4)
  set line($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLine() => $_has(3);
  @$pb.TagNumber(4)
  void clearLine() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get message => $_getSZ(4);
  @$pb.TagNumber(5)
  set message($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearMessage() => $_clearField(5);
}

class PluginSummary extends $pb.GeneratedMessage {
  factory PluginSummary({
    $core.String? id,
    $core.String? name,
    $core.String? version,
    $core.int? manifestVersion,
    PluginStatus? status,
    $core.Iterable<$core.String>? platforms,
    $core.Iterable<PluginProblem>? problems,
    $core.bool? hasHooks,
    $core.bool? supportsMods,
    $core.String? rconProtocol,
    $core.String? steamLogin,
  }) {
    final result = PluginSummary._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (version != null) result.version = version;
    if (manifestVersion != null) result.manifestVersion = manifestVersion;
    if (status != null) result.status = status;
    if (platforms != null) result.platforms.addAll(platforms);
    if (problems != null) result.problems.addAll(problems);
    if (hasHooks != null) result.hasHooks = hasHooks;
    if (supportsMods != null) result.supportsMods = supportsMods;
    if (rconProtocol != null) result.rconProtocol = rconProtocol;
    if (steamLogin != null) result.steamLogin = steamLogin;
    return result;
  }

  PluginSummary._();

  factory PluginSummary.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginSummary()..mergeFromBuffer(data, registry);
  factory PluginSummary.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginSummary()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PluginSummary',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PluginSummary.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'version')
    ..aI(4, _omitFieldNames ? '' : 'manifestVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aE<PluginStatus>(5, _omitFieldNames ? '' : 'status',
        enumValues: PluginStatus.values)
    ..pPS(6, _omitFieldNames ? '' : 'platforms')
    ..pPM<PluginProblem>(7, _omitFieldNames ? '' : 'problems',
        subBuilder: PluginProblem.$_createMessage)
    ..aOB(8, _omitFieldNames ? '' : 'hasHooks')
    ..aOB(9, _omitFieldNames ? '' : 'supportsMods')
    ..aOS(10, _omitFieldNames ? '' : 'rconProtocol')
    ..aOS(11, _omitFieldNames ? '' : 'steamLogin')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginSummary clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginSummary copyWith(void Function(PluginSummary) updates) =>
      super.copyWith((message) => updates(message as PluginSummary))
          as PluginSummary;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PluginSummary() / PluginSummary.new instead')
  static PluginSummary create() => PluginSummary._();
  static $pb.GeneratedMessage $_createMessage() => PluginSummary._();
  @$core.override
  PluginSummary createEmptyInstance() => PluginSummary._();
  @$core.pragma('dart2js:noInline')
  static PluginSummary getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PluginSummary>(
          PluginSummary.$_createMessage);
  static PluginSummary? _defaultInstance;

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
  $core.String get version => $_getSZ(2);
  @$pb.TagNumber(3)
  set version($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get manifestVersion => $_getIZ(3);
  @$pb.TagNumber(4)
  set manifestVersion($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasManifestVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearManifestVersion() => $_clearField(4);

  @$pb.TagNumber(5)
  PluginStatus get status => $_getN(4);
  @$pb.TagNumber(5)
  set status(PluginStatus value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasStatus() => $_has(4);
  @$pb.TagNumber(5)
  void clearStatus() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get platforms => $_getList(5);

  @$pb.TagNumber(7)
  $pb.PbList<PluginProblem> get problems => $_getList(6);

  @$pb.TagNumber(8)
  $core.bool get hasHooks => $_getBF(7);
  @$pb.TagNumber(8)
  set hasHooks($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHasHooks() => $_has(7);
  @$pb.TagNumber(8)
  void clearHasHooks() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get supportsMods => $_getBF(8);
  @$pb.TagNumber(9)
  set supportsMods($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSupportsMods() => $_has(8);
  @$pb.TagNumber(9)
  void clearSupportsMods() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get rconProtocol => $_getSZ(9);
  @$pb.TagNumber(10)
  set rconProtocol($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRconProtocol() => $_has(9);
  @$pb.TagNumber(10)
  void clearRconProtocol() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get steamLogin => $_getSZ(10);
  @$pb.TagNumber(11)
  set steamLogin($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSteamLogin() => $_has(10);
  @$pb.TagNumber(11)
  void clearSteamLogin() => $_clearField(11);
}

class ListPluginsRequest extends $pb.GeneratedMessage {
  factory ListPluginsRequest() => ListPluginsRequest._();

  ListPluginsRequest._();

  factory ListPluginsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPluginsRequest()..mergeFromBuffer(data, registry);
  factory ListPluginsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPluginsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPluginsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListPluginsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPluginsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPluginsRequest copyWith(void Function(ListPluginsRequest) updates) =>
      super.copyWith((message) => updates(message as ListPluginsRequest))
          as ListPluginsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListPluginsRequest() / ListPluginsRequest.new instead')
  static ListPluginsRequest create() => ListPluginsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListPluginsRequest._();
  @$core.override
  ListPluginsRequest createEmptyInstance() => ListPluginsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListPluginsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPluginsRequest>(
          ListPluginsRequest.$_createMessage);
  static ListPluginsRequest? _defaultInstance;
}

class ListPluginsResponse extends $pb.GeneratedMessage {
  factory ListPluginsResponse({
    $core.Iterable<PluginSummary>? plugins,
  }) {
    final result = ListPluginsResponse._();
    if (plugins != null) result.plugins.addAll(plugins);
    return result;
  }

  ListPluginsResponse._();

  factory ListPluginsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPluginsResponse()..mergeFromBuffer(data, registry);
  factory ListPluginsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPluginsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPluginsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListPluginsResponse.$_createMessage)
    ..pPM<PluginSummary>(1, _omitFieldNames ? '' : 'plugins',
        subBuilder: PluginSummary.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPluginsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPluginsResponse copyWith(void Function(ListPluginsResponse) updates) =>
      super.copyWith((message) => updates(message as ListPluginsResponse))
          as ListPluginsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListPluginsResponse() / ListPluginsResponse.new instead')
  static ListPluginsResponse create() => ListPluginsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListPluginsResponse._();
  @$core.override
  ListPluginsResponse createEmptyInstance() => ListPluginsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListPluginsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPluginsResponse>(
          ListPluginsResponse.$_createMessage);
  static ListPluginsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PluginSummary> get plugins => $_getList(0);
}

class GetPluginRequest extends $pb.GeneratedMessage {
  factory GetPluginRequest({
    $core.String? pluginId,
  }) {
    final result = GetPluginRequest._();
    if (pluginId != null) result.pluginId = pluginId;
    return result;
  }

  GetPluginRequest._();

  factory GetPluginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPluginRequest()..mergeFromBuffer(data, registry);
  factory GetPluginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPluginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPluginRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: GetPluginRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'pluginId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPluginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPluginRequest copyWith(void Function(GetPluginRequest) updates) =>
      super.copyWith((message) => updates(message as GetPluginRequest))
          as GetPluginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetPluginRequest() / GetPluginRequest.new instead')
  static GetPluginRequest create() => GetPluginRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetPluginRequest._();
  @$core.override
  GetPluginRequest createEmptyInstance() => GetPluginRequest._();
  @$core.pragma('dart2js:noInline')
  static GetPluginRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPluginRequest>(
          GetPluginRequest.$_createMessage);
  static GetPluginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pluginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set pluginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPluginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPluginId() => $_clearField(1);
}

class PluginDetail extends $pb.GeneratedMessage {
  factory PluginDetail({
    PluginSummary? summary,
    $1.JsonDocument? settingsSchema,
    $core.Iterable<$1.Port>? defaultPorts,
    $core.Iterable<$core.String>? modRoles,
    $core.Iterable<$core.String>? logSources,
  }) {
    final result = PluginDetail._();
    if (summary != null) result.summary = summary;
    if (settingsSchema != null) result.settingsSchema = settingsSchema;
    if (defaultPorts != null) result.defaultPorts.addAll(defaultPorts);
    if (modRoles != null) result.modRoles.addAll(modRoles);
    if (logSources != null) result.logSources.addAll(logSources);
    return result;
  }

  PluginDetail._();

  factory PluginDetail.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginDetail()..mergeFromBuffer(data, registry);
  factory PluginDetail.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginDetail()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PluginDetail',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PluginDetail.$_createMessage)
    ..aOM<PluginSummary>(1, _omitFieldNames ? '' : 'summary',
        subBuilder: PluginSummary.$_createMessage)
    ..aOM<$1.JsonDocument>(2, _omitFieldNames ? '' : 'settingsSchema',
        subBuilder: $1.JsonDocument.$_createMessage)
    ..pPM<$1.Port>(3, _omitFieldNames ? '' : 'defaultPorts',
        subBuilder: $1.Port.$_createMessage)
    ..pPS(4, _omitFieldNames ? '' : 'modRoles')
    ..pPS(5, _omitFieldNames ? '' : 'logSources')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginDetail clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginDetail copyWith(void Function(PluginDetail) updates) =>
      super.copyWith((message) => updates(message as PluginDetail))
          as PluginDetail;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PluginDetail() / PluginDetail.new instead')
  static PluginDetail create() => PluginDetail._();
  static $pb.GeneratedMessage $_createMessage() => PluginDetail._();
  @$core.override
  PluginDetail createEmptyInstance() => PluginDetail._();
  @$core.pragma('dart2js:noInline')
  static PluginDetail getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PluginDetail>(
          PluginDetail.$_createMessage);
  static PluginDetail? _defaultInstance;

  @$pb.TagNumber(1)
  PluginSummary get summary => $_getN(0);
  @$pb.TagNumber(1)
  set summary(PluginSummary value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSummary() => $_has(0);
  @$pb.TagNumber(1)
  void clearSummary() => $_clearField(1);
  @$pb.TagNumber(1)
  PluginSummary ensureSummary() => $_ensure(0);

  /// Settings schema (types, constraints, groups) as JSON; schema_version
  /// changes whenever the plugin's settings schema changes.
  @$pb.TagNumber(2)
  $1.JsonDocument get settingsSchema => $_getN(1);
  @$pb.TagNumber(2)
  set settingsSchema($1.JsonDocument value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSettingsSchema() => $_has(1);
  @$pb.TagNumber(2)
  void clearSettingsSchema() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.JsonDocument ensureSettingsSchema() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<$1.Port> get defaultPorts => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get modRoles => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get logSources => $_getList(4);
}

class ReloadPluginsRequest extends $pb.GeneratedMessage {
  factory ReloadPluginsRequest({
    $core.Iterable<$core.String>? pluginIds,
  }) {
    final result = ReloadPluginsRequest._();
    if (pluginIds != null) result.pluginIds.addAll(pluginIds);
    return result;
  }

  ReloadPluginsRequest._();

  factory ReloadPluginsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReloadPluginsRequest()..mergeFromBuffer(data, registry);
  factory ReloadPluginsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReloadPluginsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReloadPluginsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ReloadPluginsRequest.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'pluginIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReloadPluginsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReloadPluginsRequest copyWith(void Function(ReloadPluginsRequest) updates) =>
      super.copyWith((message) => updates(message as ReloadPluginsRequest))
          as ReloadPluginsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReloadPluginsRequest() / ReloadPluginsRequest.new instead')
  static ReloadPluginsRequest create() => ReloadPluginsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReloadPluginsRequest._();
  @$core.override
  ReloadPluginsRequest createEmptyInstance() => ReloadPluginsRequest._();
  @$core.pragma('dart2js:noInline')
  static ReloadPluginsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReloadPluginsRequest>(
          ReloadPluginsRequest.$_createMessage);
  static ReloadPluginsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get pluginIds => $_getList(0);
}

class PluginReloadResult extends $pb.GeneratedMessage {
  factory PluginReloadResult({
    $core.String? pluginId,
    $core.String? outcome,
    $core.Iterable<PluginProblem>? problems,
  }) {
    final result = PluginReloadResult._();
    if (pluginId != null) result.pluginId = pluginId;
    if (outcome != null) result.outcome = outcome;
    if (problems != null) result.problems.addAll(problems);
    return result;
  }

  PluginReloadResult._();

  factory PluginReloadResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginReloadResult()..mergeFromBuffer(data, registry);
  factory PluginReloadResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PluginReloadResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PluginReloadResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PluginReloadResult.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'pluginId')
    ..aOS(2, _omitFieldNames ? '' : 'outcome')
    ..pPM<PluginProblem>(3, _omitFieldNames ? '' : 'problems',
        subBuilder: PluginProblem.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginReloadResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginReloadResult copyWith(void Function(PluginReloadResult) updates) =>
      super.copyWith((message) => updates(message as PluginReloadResult))
          as PluginReloadResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PluginReloadResult() / PluginReloadResult.new instead')
  static PluginReloadResult create() => PluginReloadResult._();
  static $pb.GeneratedMessage $_createMessage() => PluginReloadResult._();
  @$core.override
  PluginReloadResult createEmptyInstance() => PluginReloadResult._();
  @$core.pragma('dart2js:noInline')
  static PluginReloadResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PluginReloadResult>(
          PluginReloadResult.$_createMessage);
  static PluginReloadResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pluginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set pluginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPluginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPluginId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get outcome => $_getSZ(1);
  @$pb.TagNumber(2)
  set outcome($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOutcome() => $_has(1);
  @$pb.TagNumber(2)
  void clearOutcome() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<PluginProblem> get problems => $_getList(2);
}

class ReloadPluginsResponse extends $pb.GeneratedMessage {
  factory ReloadPluginsResponse({
    $core.Iterable<PluginReloadResult>? results,
  }) {
    final result = ReloadPluginsResponse._();
    if (results != null) result.results.addAll(results);
    return result;
  }

  ReloadPluginsResponse._();

  factory ReloadPluginsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReloadPluginsResponse()..mergeFromBuffer(data, registry);
  factory ReloadPluginsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReloadPluginsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReloadPluginsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ReloadPluginsResponse.$_createMessage)
    ..pPM<PluginReloadResult>(1, _omitFieldNames ? '' : 'results',
        subBuilder: PluginReloadResult.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReloadPluginsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReloadPluginsResponse copyWith(
          void Function(ReloadPluginsResponse) updates) =>
      super.copyWith((message) => updates(message as ReloadPluginsResponse))
          as ReloadPluginsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReloadPluginsResponse() / ReloadPluginsResponse.new instead')
  static ReloadPluginsResponse create() => ReloadPluginsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReloadPluginsResponse._();
  @$core.override
  ReloadPluginsResponse createEmptyInstance() => ReloadPluginsResponse._();
  @$core.pragma('dart2js:noInline')
  static ReloadPluginsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReloadPluginsResponse>(
          ReloadPluginsResponse.$_createMessage);
  static ReloadPluginsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PluginReloadResult> get results => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
