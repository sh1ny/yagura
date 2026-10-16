// This is a generated file - do not edit.
//
// Generated from yagura/v1/logs.proto.

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

class LogSource extends $pb.GeneratedMessage {
  factory LogSource({
    $core.String? name,
    $core.String? kind,
    $core.String? status,
    $core.String? currentFile,
    $core.String? encoding,
    $core.String? lastError,
  }) {
    final result = LogSource._();
    if (name != null) result.name = name;
    if (kind != null) result.kind = kind;
    if (status != null) result.status = status;
    if (currentFile != null) result.currentFile = currentFile;
    if (encoding != null) result.encoding = encoding;
    if (lastError != null) result.lastError = lastError;
    return result;
  }

  LogSource._();

  factory LogSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogSource()..mergeFromBuffer(data, registry);
  factory LogSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogSource()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LogSource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: LogSource.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'kind')
    ..aOS(3, _omitFieldNames ? '' : 'status')
    ..aOS(4, _omitFieldNames ? '' : 'currentFile')
    ..aOS(5, _omitFieldNames ? '' : 'encoding')
    ..aOS(6, _omitFieldNames ? '' : 'lastError')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogSource copyWith(void Function(LogSource) updates) =>
      super.copyWith((message) => updates(message as LogSource)) as LogSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LogSource() / LogSource.new instead')
  static LogSource create() => LogSource._();
  static $pb.GeneratedMessage $_createMessage() => LogSource._();
  @$core.override
  LogSource createEmptyInstance() => LogSource._();
  @$core.pragma('dart2js:noInline')
  static LogSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LogSource>(LogSource.$_createMessage);
  static LogSource? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get kind => $_getSZ(1);
  @$pb.TagNumber(2)
  set kind($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get status => $_getSZ(2);
  @$pb.TagNumber(3)
  set status($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get currentFile => $_getSZ(3);
  @$pb.TagNumber(4)
  set currentFile($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrentFile() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrentFile() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get encoding => $_getSZ(4);
  @$pb.TagNumber(5)
  set encoding($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEncoding() => $_has(4);
  @$pb.TagNumber(5)
  void clearEncoding() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get lastError => $_getSZ(5);
  @$pb.TagNumber(6)
  set lastError($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLastError() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastError() => $_clearField(6);
}

class ListSourcesRequest extends $pb.GeneratedMessage {
  factory ListSourcesRequest({
    $core.String? instanceId,
  }) {
    final result = ListSourcesRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    return result;
  }

  ListSourcesRequest._();

  factory ListSourcesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSourcesRequest()..mergeFromBuffer(data, registry);
  factory ListSourcesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSourcesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSourcesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListSourcesRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSourcesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSourcesRequest copyWith(void Function(ListSourcesRequest) updates) =>
      super.copyWith((message) => updates(message as ListSourcesRequest))
          as ListSourcesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListSourcesRequest() / ListSourcesRequest.new instead')
  static ListSourcesRequest create() => ListSourcesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListSourcesRequest._();
  @$core.override
  ListSourcesRequest createEmptyInstance() => ListSourcesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListSourcesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSourcesRequest>(
          ListSourcesRequest.$_createMessage);
  static ListSourcesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);
}

class ListSourcesResponse extends $pb.GeneratedMessage {
  factory ListSourcesResponse({
    $core.Iterable<LogSource>? sources,
  }) {
    final result = ListSourcesResponse._();
    if (sources != null) result.sources.addAll(sources);
    return result;
  }

  ListSourcesResponse._();

  factory ListSourcesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSourcesResponse()..mergeFromBuffer(data, registry);
  factory ListSourcesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSourcesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSourcesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListSourcesResponse.$_createMessage)
    ..pPM<LogSource>(1, _omitFieldNames ? '' : 'sources',
        subBuilder: LogSource.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSourcesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSourcesResponse copyWith(void Function(ListSourcesResponse) updates) =>
      super.copyWith((message) => updates(message as ListSourcesResponse))
          as ListSourcesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListSourcesResponse() / ListSourcesResponse.new instead')
  static ListSourcesResponse create() => ListSourcesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListSourcesResponse._();
  @$core.override
  ListSourcesResponse createEmptyInstance() => ListSourcesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListSourcesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSourcesResponse>(
          ListSourcesResponse.$_createMessage);
  static ListSourcesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<LogSource> get sources => $_getList(0);
}

class BacklogRequest extends $pb.GeneratedMessage {
  factory BacklogRequest({
    $core.String? instanceId,
    $core.Iterable<$core.String>? sources,
    $core.int? lines,
  }) {
    final result = BacklogRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (sources != null) result.sources.addAll(sources);
    if (lines != null) result.lines = lines;
    return result;
  }

  BacklogRequest._();

  factory BacklogRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BacklogRequest()..mergeFromBuffer(data, registry);
  factory BacklogRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BacklogRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BacklogRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: BacklogRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..pPS(2, _omitFieldNames ? '' : 'sources')
    ..aI(3, _omitFieldNames ? '' : 'lines', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BacklogRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BacklogRequest copyWith(void Function(BacklogRequest) updates) =>
      super.copyWith((message) => updates(message as BacklogRequest))
          as BacklogRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BacklogRequest() / BacklogRequest.new instead')
  static BacklogRequest create() => BacklogRequest._();
  static $pb.GeneratedMessage $_createMessage() => BacklogRequest._();
  @$core.override
  BacklogRequest createEmptyInstance() => BacklogRequest._();
  @$core.pragma('dart2js:noInline')
  static BacklogRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BacklogRequest>(
          BacklogRequest.$_createMessage);
  static BacklogRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get sources => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get lines => $_getIZ(2);
  @$pb.TagNumber(3)
  set lines($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLines() => $_has(2);
  @$pb.TagNumber(3)
  void clearLines() => $_clearField(3);
}

class FollowRequest extends $pb.GeneratedMessage {
  factory FollowRequest({
    $core.String? instanceId,
    $core.Iterable<$core.String>? sources,
  }) {
    final result = FollowRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (sources != null) result.sources.addAll(sources);
    return result;
  }

  FollowRequest._();

  factory FollowRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FollowRequest()..mergeFromBuffer(data, registry);
  factory FollowRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FollowRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FollowRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: FollowRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..pPS(2, _omitFieldNames ? '' : 'sources')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FollowRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FollowRequest copyWith(void Function(FollowRequest) updates) =>
      super.copyWith((message) => updates(message as FollowRequest))
          as FollowRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FollowRequest() / FollowRequest.new instead')
  static FollowRequest create() => FollowRequest._();
  static $pb.GeneratedMessage $_createMessage() => FollowRequest._();
  @$core.override
  FollowRequest createEmptyInstance() => FollowRequest._();
  @$core.pragma('dart2js:noInline')
  static FollowRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FollowRequest>(
          FollowRequest.$_createMessage);
  static FollowRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get sources => $_getList(1);
}

class LogEntry extends $pb.GeneratedMessage {
  factory LogEntry({
    $core.String? source,
    $fixnum.Int64? sequence,
    $1.Timestamp? receivedAt,
    $core.String? text,
  }) {
    final result = LogEntry._();
    if (source != null) result.source = source;
    if (sequence != null) result.sequence = sequence;
    if (receivedAt != null) result.receivedAt = receivedAt;
    if (text != null) result.text = text;
    return result;
  }

  LogEntry._();

  factory LogEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogEntry()..mergeFromBuffer(data, registry);
  factory LogEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogEntry()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LogEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: LogEntry.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$1.Timestamp>(3, _omitFieldNames ? '' : 'receivedAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogEntry copyWith(void Function(LogEntry) updates) =>
      super.copyWith((message) => updates(message as LogEntry)) as LogEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LogEntry() / LogEntry.new instead')
  static LogEntry create() => LogEntry._();
  static $pb.GeneratedMessage $_createMessage() => LogEntry._();
  @$core.override
  LogEntry createEmptyInstance() => LogEntry._();
  @$core.pragma('dart2js:noInline')
  static LogEntry getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LogEntry>(LogEntry.$_createMessage);
  static LogEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sequence => $_getI64(1);
  @$pb.TagNumber(2)
  set sequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequence() => $_clearField(2);

  @$pb.TagNumber(3)
  $1.Timestamp get receivedAt => $_getN(2);
  @$pb.TagNumber(3)
  set receivedAt($1.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasReceivedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearReceivedAt() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.Timestamp ensureReceivedAt() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get text => $_getSZ(3);
  @$pb.TagNumber(4)
  set text($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasText() => $_has(3);
  @$pb.TagNumber(4)
  void clearText() => $_clearField(4);
}

class LogBatch extends $pb.GeneratedMessage {
  factory LogBatch({
    $core.Iterable<LogEntry>? entries,
    $fixnum.Int64? dropped,
    $core.bool? truncated,
    $core.String? sourceEvent,
  }) {
    final result = LogBatch._();
    if (entries != null) result.entries.addAll(entries);
    if (dropped != null) result.dropped = dropped;
    if (truncated != null) result.truncated = truncated;
    if (sourceEvent != null) result.sourceEvent = sourceEvent;
    return result;
  }

  LogBatch._();

  factory LogBatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogBatch()..mergeFromBuffer(data, registry);
  factory LogBatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogBatch()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LogBatch',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: LogBatch.$_createMessage)
    ..pPM<LogEntry>(1, _omitFieldNames ? '' : 'entries',
        subBuilder: LogEntry.$_createMessage)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'dropped', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(3, _omitFieldNames ? '' : 'truncated')
    ..aOS(4, _omitFieldNames ? '' : 'sourceEvent')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogBatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogBatch copyWith(void Function(LogBatch) updates) =>
      super.copyWith((message) => updates(message as LogBatch)) as LogBatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LogBatch() / LogBatch.new instead')
  static LogBatch create() => LogBatch._();
  static $pb.GeneratedMessage $_createMessage() => LogBatch._();
  @$core.override
  LogBatch createEmptyInstance() => LogBatch._();
  @$core.pragma('dart2js:noInline')
  static LogBatch getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LogBatch>(LogBatch.$_createMessage);
  static LogBatch? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<LogEntry> get entries => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get dropped => $_getI64(1);
  @$pb.TagNumber(2)
  set dropped($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDropped() => $_has(1);
  @$pb.TagNumber(2)
  void clearDropped() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get truncated => $_getBF(2);
  @$pb.TagNumber(3)
  set truncated($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTruncated() => $_has(2);
  @$pb.TagNumber(3)
  void clearTruncated() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sourceEvent => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceEvent($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceEvent() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceEvent() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
