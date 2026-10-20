// This is a generated file - do not edit.
//
// Generated from yagura/v1/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'common.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'common.pbenum.dart';

/// Machine-readable error detail attached to every non-OK status
/// (packed into google.rpc.Status.details). `reason` values are stable and
/// listed in docs/protocol.md; a reason is never reused for another meaning.
class ErrorDetail extends $pb.GeneratedMessage {
  factory ErrorDetail({
    $core.String? reason,
    $core.String? message,
    $core.Iterable<FieldViolation>? fieldViolations,
    $core.String? incidentId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = ErrorDetail._();
    if (reason != null) result.reason = reason;
    if (message != null) result.message = message;
    if (fieldViolations != null) result.fieldViolations.addAll(fieldViolations);
    if (incidentId != null) result.incidentId = incidentId;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  ErrorDetail._();

  factory ErrorDetail.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorDetail()..mergeFromBuffer(data, registry);
  factory ErrorDetail.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorDetail()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorDetail',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ErrorDetail.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'reason')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..pPM<FieldViolation>(3, _omitFieldNames ? '' : 'fieldViolations',
        subBuilder: FieldViolation.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'incidentId')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'ErrorDetail.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('yagura.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorDetail clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorDetail copyWith(void Function(ErrorDetail) updates) =>
      super.copyWith((message) => updates(message as ErrorDetail))
          as ErrorDetail;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ErrorDetail() / ErrorDetail.new instead')
  static ErrorDetail create() => ErrorDetail._();
  static $pb.GeneratedMessage $_createMessage() => ErrorDetail._();
  @$core.override
  ErrorDetail createEmptyInstance() => ErrorDetail._();
  @$core.pragma('dart2js:noInline')
  static ErrorDetail getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErrorDetail>(
          ErrorDetail.$_createMessage);
  static ErrorDetail? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reason => $_getSZ(0);
  @$pb.TagNumber(1)
  set reason($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<FieldViolation> get fieldViolations => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get incidentId => $_getSZ(3);
  @$pb.TagNumber(4)
  set incidentId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIncidentId() => $_has(3);
  @$pb.TagNumber(4)
  void clearIncidentId() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);
}

class FieldViolation extends $pb.GeneratedMessage {
  factory FieldViolation({
    $core.String? field_1,
    $core.String? description,
  }) {
    final result = FieldViolation._();
    if (field_1 != null) result.field_1 = field_1;
    if (description != null) result.description = description;
    return result;
  }

  FieldViolation._();

  factory FieldViolation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FieldViolation()..mergeFromBuffer(data, registry);
  factory FieldViolation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FieldViolation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FieldViolation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: FieldViolation.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'field')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FieldViolation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FieldViolation copyWith(void Function(FieldViolation) updates) =>
      super.copyWith((message) => updates(message as FieldViolation))
          as FieldViolation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FieldViolation() / FieldViolation.new instead')
  static FieldViolation create() => FieldViolation._();
  static $pb.GeneratedMessage $_createMessage() => FieldViolation._();
  @$core.override
  FieldViolation createEmptyInstance() => FieldViolation._();
  @$core.pragma('dart2js:noInline')
  static FieldViolation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FieldViolation>(
          FieldViolation.$_createMessage);
  static FieldViolation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get field_1 => $_getSZ(0);
  @$pb.TagNumber(1)
  set field_1($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasField_1() => $_has(0);
  @$pb.TagNumber(1)
  void clearField_1() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => $_clearField(2);
}

/// Plugin-shaped data travels as JSON text with the version of the schema it
/// was produced for (ADR 0006).
class JsonDocument extends $pb.GeneratedMessage {
  factory JsonDocument({
    $core.String? json,
    $core.int? schemaVersion,
  }) {
    final result = JsonDocument._();
    if (json != null) result.json = json;
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    return result;
  }

  JsonDocument._();

  factory JsonDocument.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JsonDocument()..mergeFromBuffer(data, registry);
  factory JsonDocument.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JsonDocument()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JsonDocument',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: JsonDocument.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'json')
    ..aI(2, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JsonDocument clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JsonDocument copyWith(void Function(JsonDocument) updates) =>
      super.copyWith((message) => updates(message as JsonDocument))
          as JsonDocument;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JsonDocument() / JsonDocument.new instead')
  static JsonDocument create() => JsonDocument._();
  static $pb.GeneratedMessage $_createMessage() => JsonDocument._();
  @$core.override
  JsonDocument createEmptyInstance() => JsonDocument._();
  @$core.pragma('dart2js:noInline')
  static JsonDocument getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JsonDocument>(
          JsonDocument.$_createMessage);
  static JsonDocument? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get json => $_getSZ(0);
  @$pb.TagNumber(1)
  set json($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearJson() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get schemaVersion => $_getIZ(1);
  @$pb.TagNumber(2)
  set schemaVersion($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSchemaVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearSchemaVersion() => $_clearField(2);
}

class Port extends $pb.GeneratedMessage {
  factory Port({
    $core.String? name,
    $core.int? number,
    Protocol? protocol,
    $core.String? purpose,
    $core.bool? exposed,
  }) {
    final result = Port._();
    if (name != null) result.name = name;
    if (number != null) result.number = number;
    if (protocol != null) result.protocol = protocol;
    if (purpose != null) result.purpose = purpose;
    if (exposed != null) result.exposed = exposed;
    return result;
  }

  Port._();

  factory Port.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Port()..mergeFromBuffer(data, registry);
  factory Port.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Port()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Port',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Port.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aI(2, _omitFieldNames ? '' : 'number', fieldType: $pb.PbFieldType.OU3)
    ..aE<Protocol>(3, _omitFieldNames ? '' : 'protocol',
        enumValues: Protocol.values)
    ..aOS(4, _omitFieldNames ? '' : 'purpose')
    ..aOB(5, _omitFieldNames ? '' : 'exposed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Port clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Port copyWith(void Function(Port) updates) =>
      super.copyWith((message) => updates(message as Port)) as Port;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Port() / Port.new instead')
  static Port create() => Port._();
  static $pb.GeneratedMessage $_createMessage() => Port._();
  @$core.override
  Port createEmptyInstance() => Port._();
  @$core.pragma('dart2js:noInline')
  static Port getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Port>(Port.$_createMessage);
  static Port? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get number => $_getIZ(1);
  @$pb.TagNumber(2)
  set number($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearNumber() => $_clearField(2);

  @$pb.TagNumber(3)
  Protocol get protocol => $_getN(2);
  @$pb.TagNumber(3)
  set protocol(Protocol value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocol() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocol() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get purpose => $_getSZ(3);
  @$pb.TagNumber(4)
  set purpose($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPurpose() => $_has(3);
  @$pb.TagNumber(4)
  void clearPurpose() => $_clearField(4);

  /// Firewall rule wanted. In UpdateSettings the daemon honors it for a port of
  /// purpose rcon only, the per-instance choice to open it: every other port
  /// follows the plugin. A request that names the rcon port always sets it from
  /// this field, so an unset (false) value closes the port; a request that does
  /// not name the rcon port leaves the choice as it is.
  @$pb.TagNumber(5)
  $core.bool get exposed => $_getBF(4);
  @$pb.TagNumber(5)
  set exposed($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasExposed() => $_has(4);
  @$pb.TagNumber(5)
  void clearExposed() => $_clearField(5);
}

class Empty extends $pb.GeneratedMessage {
  factory Empty() => Empty._();

  Empty._();

  factory Empty.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Empty()..mergeFromBuffer(data, registry);
  factory Empty.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Empty()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Empty',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Empty.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty copyWith(void Function(Empty) updates) =>
      super.copyWith((message) => updates(message as Empty)) as Empty;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Empty() / Empty.new instead')
  static Empty create() => Empty._();
  static $pb.GeneratedMessage $_createMessage() => Empty._();
  @$core.override
  Empty createEmptyInstance() => Empty._();
  @$core.pragma('dart2js:noInline')
  static Empty getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Empty>(Empty.$_createMessage);
  static Empty? _defaultInstance;
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
