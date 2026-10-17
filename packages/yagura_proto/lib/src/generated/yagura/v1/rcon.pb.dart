// This is a generated file - do not edit.
//
// Generated from yagura/v1/rcon.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class ExecuteRequest extends $pb.GeneratedMessage {
  factory ExecuteRequest({
    $core.String? instanceId,
    $core.String? command,
  }) {
    final result = ExecuteRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (command != null) result.command = command;
    return result;
  }

  ExecuteRequest._();

  factory ExecuteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteRequest()..mergeFromBuffer(data, registry);
  factory ExecuteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExecuteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ExecuteRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'command')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteRequest copyWith(void Function(ExecuteRequest) updates) =>
      super.copyWith((message) => updates(message as ExecuteRequest))
          as ExecuteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ExecuteRequest() / ExecuteRequest.new instead')
  static ExecuteRequest create() => ExecuteRequest._();
  static $pb.GeneratedMessage $_createMessage() => ExecuteRequest._();
  @$core.override
  ExecuteRequest createEmptyInstance() => ExecuteRequest._();
  @$core.pragma('dart2js:noInline')
  static ExecuteRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExecuteRequest>(
          ExecuteRequest.$_createMessage);
  static ExecuteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get command => $_getSZ(1);
  @$pb.TagNumber(2)
  set command($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCommand() => $_has(1);
  @$pb.TagNumber(2)
  void clearCommand() => $_clearField(2);
}

class ExecuteResponse extends $pb.GeneratedMessage {
  factory ExecuteResponse({
    $core.String? response,
  }) {
    final result = ExecuteResponse._();
    if (response != null) result.response = response;
    return result;
  }

  ExecuteResponse._();

  factory ExecuteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteResponse()..mergeFromBuffer(data, registry);
  factory ExecuteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExecuteResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ExecuteResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'response')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteResponse copyWith(void Function(ExecuteResponse) updates) =>
      super.copyWith((message) => updates(message as ExecuteResponse))
          as ExecuteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ExecuteResponse() / ExecuteResponse.new instead')
  static ExecuteResponse create() => ExecuteResponse._();
  static $pb.GeneratedMessage $_createMessage() => ExecuteResponse._();
  @$core.override
  ExecuteResponse createEmptyInstance() => ExecuteResponse._();
  @$core.pragma('dart2js:noInline')
  static ExecuteResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExecuteResponse>(
          ExecuteResponse.$_createMessage);
  static ExecuteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get response => $_getSZ(0);
  @$pb.TagNumber(1)
  set response($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResponse() => $_has(0);
  @$pb.TagNumber(1)
  void clearResponse() => $_clearField(1);
}

class ConsoleInput extends $pb.GeneratedMessage {
  factory ConsoleInput({
    $core.String? instanceId,
    $core.String? command,
  }) {
    final result = ConsoleInput._();
    if (instanceId != null) result.instanceId = instanceId;
    if (command != null) result.command = command;
    return result;
  }

  ConsoleInput._();

  factory ConsoleInput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConsoleInput()..mergeFromBuffer(data, registry);
  factory ConsoleInput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConsoleInput()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConsoleInput',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ConsoleInput.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aOS(2, _omitFieldNames ? '' : 'command')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConsoleInput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConsoleInput copyWith(void Function(ConsoleInput) updates) =>
      super.copyWith((message) => updates(message as ConsoleInput))
          as ConsoleInput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ConsoleInput() / ConsoleInput.new instead')
  static ConsoleInput create() => ConsoleInput._();
  static $pb.GeneratedMessage $_createMessage() => ConsoleInput._();
  @$core.override
  ConsoleInput createEmptyInstance() => ConsoleInput._();
  @$core.pragma('dart2js:noInline')
  static ConsoleInput getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ConsoleInput>(
          ConsoleInput.$_createMessage);
  static ConsoleInput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get command => $_getSZ(1);
  @$pb.TagNumber(2)
  set command($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCommand() => $_has(1);
  @$pb.TagNumber(2)
  void clearCommand() => $_clearField(2);
}

enum ConsoleOutput_Event {
  serverMessage,
  command,
  response,
  connection,
  notSet
}

class ConsoleOutput extends $pb.GeneratedMessage {
  factory ConsoleOutput({
    $1.Timestamp? at,
    $core.String? serverMessage,
    CommandEcho? command,
    $core.String? response,
    $core.String? connection,
  }) {
    final result = ConsoleOutput._();
    if (at != null) result.at = at;
    if (serverMessage != null) result.serverMessage = serverMessage;
    if (command != null) result.command = command;
    if (response != null) result.response = response;
    if (connection != null) result.connection = connection;
    return result;
  }

  ConsoleOutput._();

  factory ConsoleOutput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConsoleOutput()..mergeFromBuffer(data, registry);
  factory ConsoleOutput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConsoleOutput()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ConsoleOutput_Event>
      _ConsoleOutput_EventByTag = {
    2: ConsoleOutput_Event.serverMessage,
    3: ConsoleOutput_Event.command,
    4: ConsoleOutput_Event.response,
    5: ConsoleOutput_Event.connection,
    0: ConsoleOutput_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConsoleOutput',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ConsoleOutput.$_createMessage)
    ..oo(0, [2, 3, 4, 5])
    ..aOM<$1.Timestamp>(1, _omitFieldNames ? '' : 'at',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'serverMessage')
    ..aOM<CommandEcho>(3, _omitFieldNames ? '' : 'command',
        subBuilder: CommandEcho.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'response')
    ..aOS(5, _omitFieldNames ? '' : 'connection')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConsoleOutput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConsoleOutput copyWith(void Function(ConsoleOutput) updates) =>
      super.copyWith((message) => updates(message as ConsoleOutput))
          as ConsoleOutput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ConsoleOutput() / ConsoleOutput.new instead')
  static ConsoleOutput create() => ConsoleOutput._();
  static $pb.GeneratedMessage $_createMessage() => ConsoleOutput._();
  @$core.override
  ConsoleOutput createEmptyInstance() => ConsoleOutput._();
  @$core.pragma('dart2js:noInline')
  static ConsoleOutput getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ConsoleOutput>(
          ConsoleOutput.$_createMessage);
  static ConsoleOutput? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  ConsoleOutput_Event whichEvent() =>
      _ConsoleOutput_EventByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearEvent() => $_clearField($_whichOneof(0));

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
  $core.String get serverMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set serverMessage($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  CommandEcho get command => $_getN(2);
  @$pb.TagNumber(3)
  set command(CommandEcho value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCommand() => $_has(2);
  @$pb.TagNumber(3)
  void clearCommand() => $_clearField(3);
  @$pb.TagNumber(3)
  CommandEcho ensureCommand() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get response => $_getSZ(3);
  @$pb.TagNumber(4)
  set response($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResponse() => $_has(3);
  @$pb.TagNumber(4)
  void clearResponse() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get connection => $_getSZ(4);
  @$pb.TagNumber(5)
  set connection($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasConnection() => $_has(4);
  @$pb.TagNumber(5)
  void clearConnection() => $_clearField(5);
}

class CommandEcho extends $pb.GeneratedMessage {
  factory CommandEcho({
    $core.String? deviceName,
    $core.String? command,
  }) {
    final result = CommandEcho._();
    if (deviceName != null) result.deviceName = deviceName;
    if (command != null) result.command = command;
    return result;
  }

  CommandEcho._();

  factory CommandEcho.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommandEcho()..mergeFromBuffer(data, registry);
  factory CommandEcho.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommandEcho()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommandEcho',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: CommandEcho.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceName')
    ..aOS(2, _omitFieldNames ? '' : 'command')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandEcho clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandEcho copyWith(void Function(CommandEcho) updates) =>
      super.copyWith((message) => updates(message as CommandEcho))
          as CommandEcho;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CommandEcho() / CommandEcho.new instead')
  static CommandEcho create() => CommandEcho._();
  static $pb.GeneratedMessage $_createMessage() => CommandEcho._();
  @$core.override
  CommandEcho createEmptyInstance() => CommandEcho._();
  @$core.pragma('dart2js:noInline')
  static CommandEcho getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CommandEcho>(
          CommandEcho.$_createMessage);
  static CommandEcho? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceName => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceName() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get command => $_getSZ(1);
  @$pb.TagNumber(2)
  set command($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCommand() => $_has(1);
  @$pb.TagNumber(2)
  void clearCommand() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
