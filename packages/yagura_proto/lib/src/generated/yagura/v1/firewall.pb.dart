// This is a generated file - do not edit.
//
// Generated from yagura/v1/firewall.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class FirewallRule extends $pb.GeneratedMessage {
  factory FirewallRule({
    $core.String? name,
    $core.String? instanceId,
    $core.String? portName,
    $core.int? port,
    $core.String? protocol,
    $core.bool? managed,
    $core.bool? present,
    $core.bool? inStep,
  }) {
    final result = FirewallRule._();
    if (name != null) result.name = name;
    if (instanceId != null) result.instanceId = instanceId;
    if (portName != null) result.portName = portName;
    if (port != null) result.port = port;
    if (protocol != null) result.protocol = protocol;
    if (managed != null) result.managed = managed;
    if (present != null) result.present = present;
    if (inStep != null) result.inStep = inStep;
    return result;
  }

  FirewallRule._();

  factory FirewallRule.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FirewallRule()..mergeFromBuffer(data, registry);
  factory FirewallRule.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FirewallRule()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FirewallRule',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: FirewallRule.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'instanceId')
    ..aOS(3, _omitFieldNames ? '' : 'portName')
    ..aI(4, _omitFieldNames ? '' : 'port', fieldType: $pb.PbFieldType.OU3)
    ..aOS(5, _omitFieldNames ? '' : 'protocol')
    ..aOB(6, _omitFieldNames ? '' : 'managed')
    ..aOB(7, _omitFieldNames ? '' : 'present')
    ..aOB(8, _omitFieldNames ? '' : 'inStep')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FirewallRule clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FirewallRule copyWith(void Function(FirewallRule) updates) =>
      super.copyWith((message) => updates(message as FirewallRule))
          as FirewallRule;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FirewallRule() / FirewallRule.new instead')
  static FirewallRule create() => FirewallRule._();
  static $pb.GeneratedMessage $_createMessage() => FirewallRule._();
  @$core.override
  FirewallRule createEmptyInstance() => FirewallRule._();
  @$core.pragma('dart2js:noInline')
  static FirewallRule getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FirewallRule>(
          FirewallRule.$_createMessage);
  static FirewallRule? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get instanceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set instanceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstanceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstanceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get portName => $_getSZ(2);
  @$pb.TagNumber(3)
  set portName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPortName() => $_has(2);
  @$pb.TagNumber(3)
  void clearPortName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get port => $_getIZ(3);
  @$pb.TagNumber(4)
  set port($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPort() => $_has(3);
  @$pb.TagNumber(4)
  void clearPort() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get protocol => $_getSZ(4);
  @$pb.TagNumber(5)
  set protocol($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasProtocol() => $_has(4);
  @$pb.TagNumber(5)
  void clearProtocol() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get managed => $_getBF(5);
  @$pb.TagNumber(6)
  set managed($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasManaged() => $_has(5);
  @$pb.TagNumber(6)
  void clearManaged() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get present => $_getBF(6);
  @$pb.TagNumber(7)
  set present($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPresent() => $_has(6);
  @$pb.TagNumber(7)
  void clearPresent() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get inStep => $_getBF(7);
  @$pb.TagNumber(8)
  set inStep($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasInStep() => $_has(7);
  @$pb.TagNumber(8)
  void clearInStep() => $_clearField(8);
}

class ListRulesRequest extends $pb.GeneratedMessage {
  factory ListRulesRequest() => ListRulesRequest._();

  ListRulesRequest._();

  factory ListRulesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRulesRequest()..mergeFromBuffer(data, registry);
  factory ListRulesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRulesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRulesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListRulesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRulesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRulesRequest copyWith(void Function(ListRulesRequest) updates) =>
      super.copyWith((message) => updates(message as ListRulesRequest))
          as ListRulesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListRulesRequest() / ListRulesRequest.new instead')
  static ListRulesRequest create() => ListRulesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListRulesRequest._();
  @$core.override
  ListRulesRequest createEmptyInstance() => ListRulesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListRulesRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListRulesRequest>(
          ListRulesRequest.$_createMessage);
  static ListRulesRequest? _defaultInstance;
}

class ListRulesResponse extends $pb.GeneratedMessage {
  factory ListRulesResponse({
    $core.Iterable<FirewallRule>? rules,
    $core.String? status,
  }) {
    final result = ListRulesResponse._();
    if (rules != null) result.rules.addAll(rules);
    if (status != null) result.status = status;
    return result;
  }

  ListRulesResponse._();

  factory ListRulesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRulesResponse()..mergeFromBuffer(data, registry);
  factory ListRulesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRulesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRulesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListRulesResponse.$_createMessage)
    ..pPM<FirewallRule>(1, _omitFieldNames ? '' : 'rules',
        subBuilder: FirewallRule.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'status')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRulesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRulesResponse copyWith(void Function(ListRulesResponse) updates) =>
      super.copyWith((message) => updates(message as ListRulesResponse))
          as ListRulesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListRulesResponse() / ListRulesResponse.new instead')
  static ListRulesResponse create() => ListRulesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListRulesResponse._();
  @$core.override
  ListRulesResponse createEmptyInstance() => ListRulesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListRulesResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListRulesResponse>(
          ListRulesResponse.$_createMessage);
  static ListRulesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<FirewallRule> get rules => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get status => $_getSZ(1);
  @$pb.TagNumber(2)
  set status($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);
}

class ReconcileRequest extends $pb.GeneratedMessage {
  factory ReconcileRequest() => ReconcileRequest._();

  ReconcileRequest._();

  factory ReconcileRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileRequest()..mergeFromBuffer(data, registry);
  factory ReconcileRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReconcileRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ReconcileRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileRequest copyWith(void Function(ReconcileRequest) updates) =>
      super.copyWith((message) => updates(message as ReconcileRequest))
          as ReconcileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReconcileRequest() / ReconcileRequest.new instead')
  static ReconcileRequest create() => ReconcileRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReconcileRequest._();
  @$core.override
  ReconcileRequest createEmptyInstance() => ReconcileRequest._();
  @$core.pragma('dart2js:noInline')
  static ReconcileRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReconcileRequest>(
          ReconcileRequest.$_createMessage);
  static ReconcileRequest? _defaultInstance;
}

class RuleChange extends $pb.GeneratedMessage {
  factory RuleChange({
    $core.String? name,
    $core.String? action,
    $core.String? error,
  }) {
    final result = RuleChange._();
    if (name != null) result.name = name;
    if (action != null) result.action = action;
    if (error != null) result.error = error;
    return result;
  }

  RuleChange._();

  factory RuleChange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuleChange()..mergeFromBuffer(data, registry);
  factory RuleChange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuleChange()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RuleChange',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: RuleChange.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'action')
    ..aOS(3, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuleChange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuleChange copyWith(void Function(RuleChange) updates) =>
      super.copyWith((message) => updates(message as RuleChange)) as RuleChange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RuleChange() / RuleChange.new instead')
  static RuleChange create() => RuleChange._();
  static $pb.GeneratedMessage $_createMessage() => RuleChange._();
  @$core.override
  RuleChange createEmptyInstance() => RuleChange._();
  @$core.pragma('dart2js:noInline')
  static RuleChange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RuleChange>(RuleChange.$_createMessage);
  static RuleChange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get action => $_getSZ(1);
  @$pb.TagNumber(2)
  set action($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAction() => $_has(1);
  @$pb.TagNumber(2)
  void clearAction() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
}

class ReconcileResponse extends $pb.GeneratedMessage {
  factory ReconcileResponse({
    $core.Iterable<RuleChange>? changes,
  }) {
    final result = ReconcileResponse._();
    if (changes != null) result.changes.addAll(changes);
    return result;
  }

  ReconcileResponse._();

  factory ReconcileResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileResponse()..mergeFromBuffer(data, registry);
  factory ReconcileResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconcileResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReconcileResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ReconcileResponse.$_createMessage)
    ..pPM<RuleChange>(1, _omitFieldNames ? '' : 'changes',
        subBuilder: RuleChange.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconcileResponse copyWith(void Function(ReconcileResponse) updates) =>
      super.copyWith((message) => updates(message as ReconcileResponse))
          as ReconcileResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReconcileResponse() / ReconcileResponse.new instead')
  static ReconcileResponse create() => ReconcileResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReconcileResponse._();
  @$core.override
  ReconcileResponse createEmptyInstance() => ReconcileResponse._();
  @$core.pragma('dart2js:noInline')
  static ReconcileResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReconcileResponse>(
          ReconcileResponse.$_createMessage);
  static ReconcileResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<RuleChange> get changes => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
