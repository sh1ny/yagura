// This is a generated file - do not edit.
//
// Generated from yagura/v1/operations.proto.

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

import 'operations.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'operations.pbenum.dart';

class Operation extends $pb.GeneratedMessage {
  factory Operation({
    $core.String? id,
    $core.String? instanceId,
    $core.String? kind,
    OperationStatus? status,
    $core.int? queuePosition,
    $core.String? currentStep,
    $1.Timestamp? createdAt,
    $1.Timestamp? startedAt,
    $1.Timestamp? endedAt,
    $core.String? requestedByDeviceId,
    $core.String? resultReason,
    $core.String? resultMessage,
    $core.Iterable<$core.String>? warnings,
    Prompt? pendingPrompt,
    $fixnum.Int64? lastSequence,
  }) {
    final result = Operation._();
    if (id != null) result.id = id;
    if (instanceId != null) result.instanceId = instanceId;
    if (kind != null) result.kind = kind;
    if (status != null) result.status = status;
    if (queuePosition != null) result.queuePosition = queuePosition;
    if (currentStep != null) result.currentStep = currentStep;
    if (createdAt != null) result.createdAt = createdAt;
    if (startedAt != null) result.startedAt = startedAt;
    if (endedAt != null) result.endedAt = endedAt;
    if (requestedByDeviceId != null)
      result.requestedByDeviceId = requestedByDeviceId;
    if (resultReason != null) result.resultReason = resultReason;
    if (resultMessage != null) result.resultMessage = resultMessage;
    if (warnings != null) result.warnings.addAll(warnings);
    if (pendingPrompt != null) result.pendingPrompt = pendingPrompt;
    if (lastSequence != null) result.lastSequence = lastSequence;
    return result;
  }

  Operation._();

  factory Operation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Operation()..mergeFromBuffer(data, registry);
  factory Operation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Operation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Operation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Operation.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'instanceId')
    ..aOS(3, _omitFieldNames ? '' : 'kind')
    ..aE<OperationStatus>(4, _omitFieldNames ? '' : 'status',
        enumValues: OperationStatus.values)
    ..aI(5, _omitFieldNames ? '' : 'queuePosition',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(6, _omitFieldNames ? '' : 'currentStep')
    ..aOM<$1.Timestamp>(7, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOM<$1.Timestamp>(8, _omitFieldNames ? '' : 'startedAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOM<$1.Timestamp>(9, _omitFieldNames ? '' : 'endedAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOS(10, _omitFieldNames ? '' : 'requestedByDeviceId')
    ..aOS(11, _omitFieldNames ? '' : 'resultReason')
    ..aOS(12, _omitFieldNames ? '' : 'resultMessage')
    ..pPS(13, _omitFieldNames ? '' : 'warnings')
    ..aOM<Prompt>(14, _omitFieldNames ? '' : 'pendingPrompt',
        subBuilder: Prompt.$_createMessage)
    ..a<$fixnum.Int64>(
        15, _omitFieldNames ? '' : 'lastSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Operation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Operation copyWith(void Function(Operation) updates) =>
      super.copyWith((message) => updates(message as Operation)) as Operation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Operation() / Operation.new instead')
  static Operation create() => Operation._();
  static $pb.GeneratedMessage $_createMessage() => Operation._();
  @$core.override
  Operation createEmptyInstance() => Operation._();
  @$core.pragma('dart2js:noInline')
  static Operation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Operation>(Operation.$_createMessage);
  static Operation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get instanceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set instanceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstanceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstanceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get kind => $_getSZ(2);
  @$pb.TagNumber(3)
  set kind($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);

  @$pb.TagNumber(4)
  OperationStatus get status => $_getN(3);
  @$pb.TagNumber(4)
  set status(OperationStatus value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get queuePosition => $_getIZ(4);
  @$pb.TagNumber(5)
  set queuePosition($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasQueuePosition() => $_has(4);
  @$pb.TagNumber(5)
  void clearQueuePosition() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get currentStep => $_getSZ(5);
  @$pb.TagNumber(6)
  set currentStep($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCurrentStep() => $_has(5);
  @$pb.TagNumber(6)
  void clearCurrentStep() => $_clearField(6);

  @$pb.TagNumber(7)
  $1.Timestamp get createdAt => $_getN(6);
  @$pb.TagNumber(7)
  set createdAt($1.Timestamp value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasCreatedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearCreatedAt() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.Timestamp ensureCreatedAt() => $_ensure(6);

  @$pb.TagNumber(8)
  $1.Timestamp get startedAt => $_getN(7);
  @$pb.TagNumber(8)
  set startedAt($1.Timestamp value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasStartedAt() => $_has(7);
  @$pb.TagNumber(8)
  void clearStartedAt() => $_clearField(8);
  @$pb.TagNumber(8)
  $1.Timestamp ensureStartedAt() => $_ensure(7);

  @$pb.TagNumber(9)
  $1.Timestamp get endedAt => $_getN(8);
  @$pb.TagNumber(9)
  set endedAt($1.Timestamp value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasEndedAt() => $_has(8);
  @$pb.TagNumber(9)
  void clearEndedAt() => $_clearField(9);
  @$pb.TagNumber(9)
  $1.Timestamp ensureEndedAt() => $_ensure(8);

  @$pb.TagNumber(10)
  $core.String get requestedByDeviceId => $_getSZ(9);
  @$pb.TagNumber(10)
  set requestedByDeviceId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRequestedByDeviceId() => $_has(9);
  @$pb.TagNumber(10)
  void clearRequestedByDeviceId() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get resultReason => $_getSZ(10);
  @$pb.TagNumber(11)
  set resultReason($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasResultReason() => $_has(10);
  @$pb.TagNumber(11)
  void clearResultReason() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get resultMessage => $_getSZ(11);
  @$pb.TagNumber(12)
  set resultMessage($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasResultMessage() => $_has(11);
  @$pb.TagNumber(12)
  void clearResultMessage() => $_clearField(12);

  @$pb.TagNumber(13)
  $pb.PbList<$core.String> get warnings => $_getList(12);

  @$pb.TagNumber(14)
  Prompt get pendingPrompt => $_getN(13);
  @$pb.TagNumber(14)
  set pendingPrompt(Prompt value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasPendingPrompt() => $_has(13);
  @$pb.TagNumber(14)
  void clearPendingPrompt() => $_clearField(14);
  @$pb.TagNumber(14)
  Prompt ensurePendingPrompt() => $_ensure(13);

  @$pb.TagNumber(15)
  $fixnum.Int64 get lastSequence => $_getI64(14);
  @$pb.TagNumber(15)
  set lastSequence($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(15)
  $core.bool hasLastSequence() => $_has(14);
  @$pb.TagNumber(15)
  void clearLastSequence() => $_clearField(15);
}

class Prompt extends $pb.GeneratedMessage {
  factory Prompt({
    $core.String? id,
    $core.String? kind,
    $core.String? message,
    $core.String? steamAccount,
    $1.Timestamp? expiresAt,
  }) {
    final result = Prompt._();
    if (id != null) result.id = id;
    if (kind != null) result.kind = kind;
    if (message != null) result.message = message;
    if (steamAccount != null) result.steamAccount = steamAccount;
    if (expiresAt != null) result.expiresAt = expiresAt;
    return result;
  }

  Prompt._();

  factory Prompt.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Prompt()..mergeFromBuffer(data, registry);
  factory Prompt.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Prompt()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Prompt',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Prompt.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'kind')
    ..aOS(3, _omitFieldNames ? '' : 'message')
    ..aOS(4, _omitFieldNames ? '' : 'steamAccount')
    ..aOM<$1.Timestamp>(5, _omitFieldNames ? '' : 'expiresAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Prompt clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Prompt copyWith(void Function(Prompt) updates) =>
      super.copyWith((message) => updates(message as Prompt)) as Prompt;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Prompt() / Prompt.new instead')
  static Prompt create() => Prompt._();
  static $pb.GeneratedMessage $_createMessage() => Prompt._();
  @$core.override
  Prompt createEmptyInstance() => Prompt._();
  @$core.pragma('dart2js:noInline')
  static Prompt getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Prompt>(Prompt.$_createMessage);
  static Prompt? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

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
  $core.String get steamAccount => $_getSZ(3);
  @$pb.TagNumber(4)
  set steamAccount($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSteamAccount() => $_has(3);
  @$pb.TagNumber(4)
  void clearSteamAccount() => $_clearField(4);

  @$pb.TagNumber(5)
  $1.Timestamp get expiresAt => $_getN(4);
  @$pb.TagNumber(5)
  set expiresAt($1.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasExpiresAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearExpiresAt() => $_clearField(5);
  @$pb.TagNumber(5)
  $1.Timestamp ensureExpiresAt() => $_ensure(4);
}

enum OperationEvent_Event {
  stepStarted,
  progress,
  log,
  prompt,
  promptResolved,
  finished,
  eventsDropped,
  snapshot,
  notSet
}

class OperationEvent extends $pb.GeneratedMessage {
  factory OperationEvent({
    $fixnum.Int64? sequence,
    $1.Timestamp? at,
    StepStarted? stepStarted,
    Progress? progress,
    LogLine? log,
    Prompt? prompt,
    PromptResolved? promptResolved,
    Operation? finished,
    EventsDropped? eventsDropped,
    Operation? snapshot,
  }) {
    final result = OperationEvent._();
    if (sequence != null) result.sequence = sequence;
    if (at != null) result.at = at;
    if (stepStarted != null) result.stepStarted = stepStarted;
    if (progress != null) result.progress = progress;
    if (log != null) result.log = log;
    if (prompt != null) result.prompt = prompt;
    if (promptResolved != null) result.promptResolved = promptResolved;
    if (finished != null) result.finished = finished;
    if (eventsDropped != null) result.eventsDropped = eventsDropped;
    if (snapshot != null) result.snapshot = snapshot;
    return result;
  }

  OperationEvent._();

  factory OperationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OperationEvent()..mergeFromBuffer(data, registry);
  factory OperationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OperationEvent()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, OperationEvent_Event>
      _OperationEvent_EventByTag = {
    3: OperationEvent_Event.stepStarted,
    4: OperationEvent_Event.progress,
    5: OperationEvent_Event.log,
    6: OperationEvent_Event.prompt,
    7: OperationEvent_Event.promptResolved,
    8: OperationEvent_Event.finished,
    9: OperationEvent_Event.eventsDropped,
    10: OperationEvent_Event.snapshot,
    0: OperationEvent_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OperationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: OperationEvent.$_createMessage)
    ..oo(0, [3, 4, 5, 6, 7, 8, 9, 10])
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$1.Timestamp>(2, _omitFieldNames ? '' : 'at',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOM<StepStarted>(3, _omitFieldNames ? '' : 'stepStarted',
        subBuilder: StepStarted.$_createMessage)
    ..aOM<Progress>(4, _omitFieldNames ? '' : 'progress',
        subBuilder: Progress.$_createMessage)
    ..aOM<LogLine>(5, _omitFieldNames ? '' : 'log',
        subBuilder: LogLine.$_createMessage)
    ..aOM<Prompt>(6, _omitFieldNames ? '' : 'prompt',
        subBuilder: Prompt.$_createMessage)
    ..aOM<PromptResolved>(7, _omitFieldNames ? '' : 'promptResolved',
        subBuilder: PromptResolved.$_createMessage)
    ..aOM<Operation>(8, _omitFieldNames ? '' : 'finished',
        subBuilder: Operation.$_createMessage)
    ..aOM<EventsDropped>(9, _omitFieldNames ? '' : 'eventsDropped',
        subBuilder: EventsDropped.$_createMessage)
    ..aOM<Operation>(10, _omitFieldNames ? '' : 'snapshot',
        subBuilder: Operation.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OperationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OperationEvent copyWith(void Function(OperationEvent) updates) =>
      super.copyWith((message) => updates(message as OperationEvent))
          as OperationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OperationEvent() / OperationEvent.new instead')
  static OperationEvent create() => OperationEvent._();
  static $pb.GeneratedMessage $_createMessage() => OperationEvent._();
  @$core.override
  OperationEvent createEmptyInstance() => OperationEvent._();
  @$core.pragma('dart2js:noInline')
  static OperationEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OperationEvent>(
          OperationEvent.$_createMessage);
  static OperationEvent? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  OperationEvent_Event whichEvent() =>
      _OperationEvent_EventByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  void clearEvent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get sequence => $_getI64(0);
  @$pb.TagNumber(1)
  set sequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearSequence() => $_clearField(1);

  @$pb.TagNumber(2)
  $1.Timestamp get at => $_getN(1);
  @$pb.TagNumber(2)
  set at($1.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearAt() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Timestamp ensureAt() => $_ensure(1);

  @$pb.TagNumber(3)
  StepStarted get stepStarted => $_getN(2);
  @$pb.TagNumber(3)
  set stepStarted(StepStarted value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasStepStarted() => $_has(2);
  @$pb.TagNumber(3)
  void clearStepStarted() => $_clearField(3);
  @$pb.TagNumber(3)
  StepStarted ensureStepStarted() => $_ensure(2);

  @$pb.TagNumber(4)
  Progress get progress => $_getN(3);
  @$pb.TagNumber(4)
  set progress(Progress value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearProgress() => $_clearField(4);
  @$pb.TagNumber(4)
  Progress ensureProgress() => $_ensure(3);

  @$pb.TagNumber(5)
  LogLine get log => $_getN(4);
  @$pb.TagNumber(5)
  set log(LogLine value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasLog() => $_has(4);
  @$pb.TagNumber(5)
  void clearLog() => $_clearField(5);
  @$pb.TagNumber(5)
  LogLine ensureLog() => $_ensure(4);

  @$pb.TagNumber(6)
  Prompt get prompt => $_getN(5);
  @$pb.TagNumber(6)
  set prompt(Prompt value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearPrompt() => $_clearField(6);
  @$pb.TagNumber(6)
  Prompt ensurePrompt() => $_ensure(5);

  @$pb.TagNumber(7)
  PromptResolved get promptResolved => $_getN(6);
  @$pb.TagNumber(7)
  set promptResolved(PromptResolved value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPromptResolved() => $_has(6);
  @$pb.TagNumber(7)
  void clearPromptResolved() => $_clearField(7);
  @$pb.TagNumber(7)
  PromptResolved ensurePromptResolved() => $_ensure(6);

  @$pb.TagNumber(8)
  Operation get finished => $_getN(7);
  @$pb.TagNumber(8)
  set finished(Operation value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasFinished() => $_has(7);
  @$pb.TagNumber(8)
  void clearFinished() => $_clearField(8);
  @$pb.TagNumber(8)
  Operation ensureFinished() => $_ensure(7);

  @$pb.TagNumber(9)
  EventsDropped get eventsDropped => $_getN(8);
  @$pb.TagNumber(9)
  set eventsDropped(EventsDropped value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasEventsDropped() => $_has(8);
  @$pb.TagNumber(9)
  void clearEventsDropped() => $_clearField(9);
  @$pb.TagNumber(9)
  EventsDropped ensureEventsDropped() => $_ensure(8);

  @$pb.TagNumber(10)
  Operation get snapshot => $_getN(9);
  @$pb.TagNumber(10)
  set snapshot(Operation value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasSnapshot() => $_has(9);
  @$pb.TagNumber(10)
  void clearSnapshot() => $_clearField(10);
  @$pb.TagNumber(10)
  Operation ensureSnapshot() => $_ensure(9);
}

class EventsDropped extends $pb.GeneratedMessage {
  factory EventsDropped({
    $fixnum.Int64? fromSequence,
    $fixnum.Int64? toSequence,
  }) {
    final result = EventsDropped._();
    if (fromSequence != null) result.fromSequence = fromSequence;
    if (toSequence != null) result.toSequence = toSequence;
    return result;
  }

  EventsDropped._();

  factory EventsDropped.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EventsDropped()..mergeFromBuffer(data, registry);
  factory EventsDropped.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EventsDropped()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EventsDropped',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: EventsDropped.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'fromSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'toSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EventsDropped clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EventsDropped copyWith(void Function(EventsDropped) updates) =>
      super.copyWith((message) => updates(message as EventsDropped))
          as EventsDropped;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EventsDropped() / EventsDropped.new instead')
  static EventsDropped create() => EventsDropped._();
  static $pb.GeneratedMessage $_createMessage() => EventsDropped._();
  @$core.override
  EventsDropped createEmptyInstance() => EventsDropped._();
  @$core.pragma('dart2js:noInline')
  static EventsDropped getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EventsDropped>(
          EventsDropped.$_createMessage);
  static EventsDropped? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get fromSequence => $_getI64(0);
  @$pb.TagNumber(1)
  set fromSequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFromSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearFromSequence() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get toSequence => $_getI64(1);
  @$pb.TagNumber(2)
  set toSequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasToSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearToSequence() => $_clearField(2);
}

class StepStarted extends $pb.GeneratedMessage {
  factory StepStarted({
    $core.String? step,
  }) {
    final result = StepStarted._();
    if (step != null) result.step = step;
    return result;
  }

  StepStarted._();

  factory StepStarted.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StepStarted()..mergeFromBuffer(data, registry);
  factory StepStarted.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StepStarted()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StepStarted',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: StepStarted.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'step')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StepStarted clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StepStarted copyWith(void Function(StepStarted) updates) =>
      super.copyWith((message) => updates(message as StepStarted))
          as StepStarted;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StepStarted() / StepStarted.new instead')
  static StepStarted create() => StepStarted._();
  static $pb.GeneratedMessage $_createMessage() => StepStarted._();
  @$core.override
  StepStarted createEmptyInstance() => StepStarted._();
  @$core.pragma('dart2js:noInline')
  static StepStarted getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StepStarted>(
          StepStarted.$_createMessage);
  static StepStarted? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get step => $_getSZ(0);
  @$pb.TagNumber(1)
  set step($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStep() => $_has(0);
  @$pb.TagNumber(1)
  void clearStep() => $_clearField(1);
}

class Progress extends $pb.GeneratedMessage {
  factory Progress({
    $core.String? step,
    $core.double? percent,
    $fixnum.Int64? bytesDone,
    $fixnum.Int64? bytesTotal,
  }) {
    final result = Progress._();
    if (step != null) result.step = step;
    if (percent != null) result.percent = percent;
    if (bytesDone != null) result.bytesDone = bytesDone;
    if (bytesTotal != null) result.bytesTotal = bytesTotal;
    return result;
  }

  Progress._();

  factory Progress.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Progress()..mergeFromBuffer(data, registry);
  factory Progress.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Progress()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Progress',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Progress.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'step')
    ..aD(2, _omitFieldNames ? '' : 'percent')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'bytesDone', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'bytesTotal', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Progress clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Progress copyWith(void Function(Progress) updates) =>
      super.copyWith((message) => updates(message as Progress)) as Progress;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Progress() / Progress.new instead')
  static Progress create() => Progress._();
  static $pb.GeneratedMessage $_createMessage() => Progress._();
  @$core.override
  Progress createEmptyInstance() => Progress._();
  @$core.pragma('dart2js:noInline')
  static Progress getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Progress>(Progress.$_createMessage);
  static Progress? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get step => $_getSZ(0);
  @$pb.TagNumber(1)
  set step($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStep() => $_has(0);
  @$pb.TagNumber(1)
  void clearStep() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get percent => $_getN(1);
  @$pb.TagNumber(2)
  set percent($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPercent() => $_has(1);
  @$pb.TagNumber(2)
  void clearPercent() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytesDone => $_getI64(2);
  @$pb.TagNumber(3)
  set bytesDone($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBytesDone() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytesDone() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get bytesTotal => $_getI64(3);
  @$pb.TagNumber(4)
  set bytesTotal($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBytesTotal() => $_has(3);
  @$pb.TagNumber(4)
  void clearBytesTotal() => $_clearField(4);
}

class LogLine extends $pb.GeneratedMessage {
  factory LogLine({
    $core.String? text,
  }) {
    final result = LogLine._();
    if (text != null) result.text = text;
    return result;
  }

  LogLine._();

  factory LogLine.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogLine()..mergeFromBuffer(data, registry);
  factory LogLine.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LogLine()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LogLine',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: LogLine.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogLine clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogLine copyWith(void Function(LogLine) updates) =>
      super.copyWith((message) => updates(message as LogLine)) as LogLine;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LogLine() / LogLine.new instead')
  static LogLine create() => LogLine._();
  static $pb.GeneratedMessage $_createMessage() => LogLine._();
  @$core.override
  LogLine createEmptyInstance() => LogLine._();
  @$core.pragma('dart2js:noInline')
  static LogLine getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LogLine>(LogLine.$_createMessage);
  static LogLine? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);
}

class PromptResolved extends $pb.GeneratedMessage {
  factory PromptResolved({
    $core.String? promptId,
    $core.String? byDeviceId,
    $core.String? outcome,
  }) {
    final result = PromptResolved._();
    if (promptId != null) result.promptId = promptId;
    if (byDeviceId != null) result.byDeviceId = byDeviceId;
    if (outcome != null) result.outcome = outcome;
    return result;
  }

  PromptResolved._();

  factory PromptResolved.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptResolved()..mergeFromBuffer(data, registry);
  factory PromptResolved.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptResolved()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PromptResolved',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PromptResolved.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'promptId')
    ..aOS(2, _omitFieldNames ? '' : 'byDeviceId')
    ..aOS(3, _omitFieldNames ? '' : 'outcome')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptResolved clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptResolved copyWith(void Function(PromptResolved) updates) =>
      super.copyWith((message) => updates(message as PromptResolved))
          as PromptResolved;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PromptResolved() / PromptResolved.new instead')
  static PromptResolved create() => PromptResolved._();
  static $pb.GeneratedMessage $_createMessage() => PromptResolved._();
  @$core.override
  PromptResolved createEmptyInstance() => PromptResolved._();
  @$core.pragma('dart2js:noInline')
  static PromptResolved getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PromptResolved>(
          PromptResolved.$_createMessage);
  static PromptResolved? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get promptId => $_getSZ(0);
  @$pb.TagNumber(1)
  set promptId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPromptId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPromptId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get byDeviceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set byDeviceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasByDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearByDeviceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get outcome => $_getSZ(2);
  @$pb.TagNumber(3)
  set outcome($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOutcome() => $_has(2);
  @$pb.TagNumber(3)
  void clearOutcome() => $_clearField(3);
}

class GetOperationRequest extends $pb.GeneratedMessage {
  factory GetOperationRequest({
    $core.String? operationId,
  }) {
    final result = GetOperationRequest._();
    if (operationId != null) result.operationId = operationId;
    return result;
  }

  GetOperationRequest._();

  factory GetOperationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetOperationRequest()..mergeFromBuffer(data, registry);
  factory GetOperationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetOperationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetOperationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: GetOperationRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOperationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOperationRequest copyWith(void Function(GetOperationRequest) updates) =>
      super.copyWith((message) => updates(message as GetOperationRequest))
          as GetOperationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use GetOperationRequest() / GetOperationRequest.new instead')
  static GetOperationRequest create() => GetOperationRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetOperationRequest._();
  @$core.override
  GetOperationRequest createEmptyInstance() => GetOperationRequest._();
  @$core.pragma('dart2js:noInline')
  static GetOperationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetOperationRequest>(
          GetOperationRequest.$_createMessage);
  static GetOperationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);
}

class ListOperationsRequest extends $pb.GeneratedMessage {
  factory ListOperationsRequest({
    $core.String? instanceId,
    $core.int? pageSize,
    $core.String? pageToken,
  }) {
    final result = ListOperationsRequest._();
    if (instanceId != null) result.instanceId = instanceId;
    if (pageSize != null) result.pageSize = pageSize;
    if (pageToken != null) result.pageToken = pageToken;
    return result;
  }

  ListOperationsRequest._();

  factory ListOperationsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListOperationsRequest()..mergeFromBuffer(data, registry);
  factory ListOperationsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListOperationsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListOperationsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListOperationsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'instanceId')
    ..aI(2, _omitFieldNames ? '' : 'pageSize', fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'pageToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOperationsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOperationsRequest copyWith(
          void Function(ListOperationsRequest) updates) =>
      super.copyWith((message) => updates(message as ListOperationsRequest))
          as ListOperationsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListOperationsRequest() / ListOperationsRequest.new instead')
  static ListOperationsRequest create() => ListOperationsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListOperationsRequest._();
  @$core.override
  ListOperationsRequest createEmptyInstance() => ListOperationsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListOperationsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListOperationsRequest>(
          ListOperationsRequest.$_createMessage);
  static ListOperationsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get instanceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get pageSize => $_getIZ(1);
  @$pb.TagNumber(2)
  set pageSize($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPageSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get pageToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set pageToken($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPageToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearPageToken() => $_clearField(3);
}

class ListOperationsResponse extends $pb.GeneratedMessage {
  factory ListOperationsResponse({
    $core.Iterable<Operation>? operations,
    $core.String? nextPageToken,
  }) {
    final result = ListOperationsResponse._();
    if (operations != null) result.operations.addAll(operations);
    if (nextPageToken != null) result.nextPageToken = nextPageToken;
    return result;
  }

  ListOperationsResponse._();

  factory ListOperationsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListOperationsResponse()..mergeFromBuffer(data, registry);
  factory ListOperationsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListOperationsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListOperationsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListOperationsResponse.$_createMessage)
    ..pPM<Operation>(1, _omitFieldNames ? '' : 'operations',
        subBuilder: Operation.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'nextPageToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOperationsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOperationsResponse copyWith(
          void Function(ListOperationsResponse) updates) =>
      super.copyWith((message) => updates(message as ListOperationsResponse))
          as ListOperationsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListOperationsResponse() / ListOperationsResponse.new instead')
  static ListOperationsResponse create() => ListOperationsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListOperationsResponse._();
  @$core.override
  ListOperationsResponse createEmptyInstance() => ListOperationsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListOperationsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListOperationsResponse>(
          ListOperationsResponse.$_createMessage);
  static ListOperationsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Operation> get operations => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get nextPageToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set nextPageToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNextPageToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearNextPageToken() => $_clearField(2);
}

class WatchOperationRequest extends $pb.GeneratedMessage {
  factory WatchOperationRequest({
    $core.String? operationId,
    $fixnum.Int64? afterSequence,
  }) {
    final result = WatchOperationRequest._();
    if (operationId != null) result.operationId = operationId;
    if (afterSequence != null) result.afterSequence = afterSequence;
    return result;
  }

  WatchOperationRequest._();

  factory WatchOperationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchOperationRequest()..mergeFromBuffer(data, registry);
  factory WatchOperationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchOperationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchOperationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: WatchOperationRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'afterSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchOperationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchOperationRequest copyWith(
          void Function(WatchOperationRequest) updates) =>
      super.copyWith((message) => updates(message as WatchOperationRequest))
          as WatchOperationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchOperationRequest() / WatchOperationRequest.new instead')
  static WatchOperationRequest create() => WatchOperationRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchOperationRequest._();
  @$core.override
  WatchOperationRequest createEmptyInstance() => WatchOperationRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchOperationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchOperationRequest>(
          WatchOperationRequest.$_createMessage);
  static WatchOperationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get afterSequence => $_getI64(1);
  @$pb.TagNumber(2)
  set afterSequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAfterSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearAfterSequence() => $_clearField(2);
}

class CancelOperationRequest extends $pb.GeneratedMessage {
  factory CancelOperationRequest({
    $core.String? operationId,
  }) {
    final result = CancelOperationRequest._();
    if (operationId != null) result.operationId = operationId;
    return result;
  }

  CancelOperationRequest._();

  factory CancelOperationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelOperationRequest()..mergeFromBuffer(data, registry);
  factory CancelOperationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelOperationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelOperationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: CancelOperationRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelOperationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelOperationRequest copyWith(
          void Function(CancelOperationRequest) updates) =>
      super.copyWith((message) => updates(message as CancelOperationRequest))
          as CancelOperationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CancelOperationRequest() / CancelOperationRequest.new instead')
  static CancelOperationRequest create() => CancelOperationRequest._();
  static $pb.GeneratedMessage $_createMessage() => CancelOperationRequest._();
  @$core.override
  CancelOperationRequest createEmptyInstance() => CancelOperationRequest._();
  @$core.pragma('dart2js:noInline')
  static CancelOperationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CancelOperationRequest>(
          CancelOperationRequest.$_createMessage);
  static CancelOperationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);
}

class RespondToPromptRequest extends $pb.GeneratedMessage {
  factory RespondToPromptRequest({
    $core.String? operationId,
    $core.String? promptId,
    $core.String? value,
  }) {
    final result = RespondToPromptRequest._();
    if (operationId != null) result.operationId = operationId;
    if (promptId != null) result.promptId = promptId;
    if (value != null) result.value = value;
    return result;
  }

  RespondToPromptRequest._();

  factory RespondToPromptRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RespondToPromptRequest()..mergeFromBuffer(data, registry);
  factory RespondToPromptRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RespondToPromptRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RespondToPromptRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: RespondToPromptRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..aOS(2, _omitFieldNames ? '' : 'promptId')
    ..aOS(3, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RespondToPromptRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RespondToPromptRequest copyWith(
          void Function(RespondToPromptRequest) updates) =>
      super.copyWith((message) => updates(message as RespondToPromptRequest))
          as RespondToPromptRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RespondToPromptRequest() / RespondToPromptRequest.new instead')
  static RespondToPromptRequest create() => RespondToPromptRequest._();
  static $pb.GeneratedMessage $_createMessage() => RespondToPromptRequest._();
  @$core.override
  RespondToPromptRequest createEmptyInstance() => RespondToPromptRequest._();
  @$core.pragma('dart2js:noInline')
  static RespondToPromptRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RespondToPromptRequest>(
          RespondToPromptRequest.$_createMessage);
  static RespondToPromptRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get promptId => $_getSZ(1);
  @$pb.TagNumber(2)
  set promptId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPromptId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPromptId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get value => $_getSZ(2);
  @$pb.TagNumber(3)
  set value($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasValue() => $_has(2);
  @$pb.TagNumber(3)
  void clearValue() => $_clearField(3);
}

class WatchPromptsRequest extends $pb.GeneratedMessage {
  factory WatchPromptsRequest() => WatchPromptsRequest._();

  WatchPromptsRequest._();

  factory WatchPromptsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchPromptsRequest()..mergeFromBuffer(data, registry);
  factory WatchPromptsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchPromptsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchPromptsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: WatchPromptsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchPromptsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchPromptsRequest copyWith(void Function(WatchPromptsRequest) updates) =>
      super.copyWith((message) => updates(message as WatchPromptsRequest))
          as WatchPromptsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use WatchPromptsRequest() / WatchPromptsRequest.new instead')
  static WatchPromptsRequest create() => WatchPromptsRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchPromptsRequest._();
  @$core.override
  WatchPromptsRequest createEmptyInstance() => WatchPromptsRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchPromptsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchPromptsRequest>(
          WatchPromptsRequest.$_createMessage);
  static WatchPromptsRequest? _defaultInstance;
}

enum PromptEvent_Event { snapshot, raised, resolved, resyncRequired, notSet }

class PromptEvent extends $pb.GeneratedMessage {
  factory PromptEvent({
    PromptSnapshot? snapshot,
    PendingPrompt? raised,
    PromptResolved? resolved,
    PromptsResyncRequired? resyncRequired,
  }) {
    final result = PromptEvent._();
    if (snapshot != null) result.snapshot = snapshot;
    if (raised != null) result.raised = raised;
    if (resolved != null) result.resolved = resolved;
    if (resyncRequired != null) result.resyncRequired = resyncRequired;
    return result;
  }

  PromptEvent._();

  factory PromptEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptEvent()..mergeFromBuffer(data, registry);
  factory PromptEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptEvent()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, PromptEvent_Event> _PromptEvent_EventByTag =
      {
    1: PromptEvent_Event.snapshot,
    2: PromptEvent_Event.raised,
    3: PromptEvent_Event.resolved,
    4: PromptEvent_Event.resyncRequired,
    0: PromptEvent_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PromptEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PromptEvent.$_createMessage)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<PromptSnapshot>(1, _omitFieldNames ? '' : 'snapshot',
        subBuilder: PromptSnapshot.$_createMessage)
    ..aOM<PendingPrompt>(2, _omitFieldNames ? '' : 'raised',
        subBuilder: PendingPrompt.$_createMessage)
    ..aOM<PromptResolved>(3, _omitFieldNames ? '' : 'resolved',
        subBuilder: PromptResolved.$_createMessage)
    ..aOM<PromptsResyncRequired>(4, _omitFieldNames ? '' : 'resyncRequired',
        subBuilder: PromptsResyncRequired.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptEvent copyWith(void Function(PromptEvent) updates) =>
      super.copyWith((message) => updates(message as PromptEvent))
          as PromptEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PromptEvent() / PromptEvent.new instead')
  static PromptEvent create() => PromptEvent._();
  static $pb.GeneratedMessage $_createMessage() => PromptEvent._();
  @$core.override
  PromptEvent createEmptyInstance() => PromptEvent._();
  @$core.pragma('dart2js:noInline')
  static PromptEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PromptEvent>(
          PromptEvent.$_createMessage);
  static PromptEvent? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  PromptEvent_Event whichEvent() => _PromptEvent_EventByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearEvent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  PromptSnapshot get snapshot => $_getN(0);
  @$pb.TagNumber(1)
  set snapshot(PromptSnapshot value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshot() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshot() => $_clearField(1);
  @$pb.TagNumber(1)
  PromptSnapshot ensureSnapshot() => $_ensure(0);

  @$pb.TagNumber(2)
  PendingPrompt get raised => $_getN(1);
  @$pb.TagNumber(2)
  set raised(PendingPrompt value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRaised() => $_has(1);
  @$pb.TagNumber(2)
  void clearRaised() => $_clearField(2);
  @$pb.TagNumber(2)
  PendingPrompt ensureRaised() => $_ensure(1);

  @$pb.TagNumber(3)
  PromptResolved get resolved => $_getN(2);
  @$pb.TagNumber(3)
  set resolved(PromptResolved value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasResolved() => $_has(2);
  @$pb.TagNumber(3)
  void clearResolved() => $_clearField(3);
  @$pb.TagNumber(3)
  PromptResolved ensureResolved() => $_ensure(2);

  @$pb.TagNumber(4)
  PromptsResyncRequired get resyncRequired => $_getN(3);
  @$pb.TagNumber(4)
  set resyncRequired(PromptsResyncRequired value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasResyncRequired() => $_has(3);
  @$pb.TagNumber(4)
  void clearResyncRequired() => $_clearField(4);
  @$pb.TagNumber(4)
  PromptsResyncRequired ensureResyncRequired() => $_ensure(3);
}

class PromptSnapshot extends $pb.GeneratedMessage {
  factory PromptSnapshot({
    $core.Iterable<PendingPrompt>? prompts,
  }) {
    final result = PromptSnapshot._();
    if (prompts != null) result.prompts.addAll(prompts);
    return result;
  }

  PromptSnapshot._();

  factory PromptSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptSnapshot()..mergeFromBuffer(data, registry);
  factory PromptSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptSnapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PromptSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PromptSnapshot.$_createMessage)
    ..pPM<PendingPrompt>(1, _omitFieldNames ? '' : 'prompts',
        subBuilder: PendingPrompt.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptSnapshot copyWith(void Function(PromptSnapshot) updates) =>
      super.copyWith((message) => updates(message as PromptSnapshot))
          as PromptSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PromptSnapshot() / PromptSnapshot.new instead')
  static PromptSnapshot create() => PromptSnapshot._();
  static $pb.GeneratedMessage $_createMessage() => PromptSnapshot._();
  @$core.override
  PromptSnapshot createEmptyInstance() => PromptSnapshot._();
  @$core.pragma('dart2js:noInline')
  static PromptSnapshot getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PromptSnapshot>(
          PromptSnapshot.$_createMessage);
  static PromptSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PendingPrompt> get prompts => $_getList(0);
}

/// A prompt and the operations waiting on it. A prompt raised by a mod download
/// run that several operations wait on lists all of them.
class PendingPrompt extends $pb.GeneratedMessage {
  factory PendingPrompt({
    Prompt? prompt,
    $core.Iterable<PromptSubject>? operations,
  }) {
    final result = PendingPrompt._();
    if (prompt != null) result.prompt = prompt;
    if (operations != null) result.operations.addAll(operations);
    return result;
  }

  PendingPrompt._();

  factory PendingPrompt.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PendingPrompt()..mergeFromBuffer(data, registry);
  factory PendingPrompt.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PendingPrompt()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PendingPrompt',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PendingPrompt.$_createMessage)
    ..aOM<Prompt>(1, _omitFieldNames ? '' : 'prompt',
        subBuilder: Prompt.$_createMessage)
    ..pPM<PromptSubject>(2, _omitFieldNames ? '' : 'operations',
        subBuilder: PromptSubject.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PendingPrompt clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PendingPrompt copyWith(void Function(PendingPrompt) updates) =>
      super.copyWith((message) => updates(message as PendingPrompt))
          as PendingPrompt;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PendingPrompt() / PendingPrompt.new instead')
  static PendingPrompt create() => PendingPrompt._();
  static $pb.GeneratedMessage $_createMessage() => PendingPrompt._();
  @$core.override
  PendingPrompt createEmptyInstance() => PendingPrompt._();
  @$core.pragma('dart2js:noInline')
  static PendingPrompt getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PendingPrompt>(
          PendingPrompt.$_createMessage);
  static PendingPrompt? _defaultInstance;

  @$pb.TagNumber(1)
  Prompt get prompt => $_getN(0);
  @$pb.TagNumber(1)
  set prompt(Prompt value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => $_clearField(1);
  @$pb.TagNumber(1)
  Prompt ensurePrompt() => $_ensure(0);

  @$pb.TagNumber(2)
  $pb.PbList<PromptSubject> get operations => $_getList(1);
}

class PromptSubject extends $pb.GeneratedMessage {
  factory PromptSubject({
    $core.String? operationId,
    $core.String? instanceId,
    $core.String? accountId,
  }) {
    final result = PromptSubject._();
    if (operationId != null) result.operationId = operationId;
    if (instanceId != null) result.instanceId = instanceId;
    if (accountId != null) result.accountId = accountId;
    return result;
  }

  PromptSubject._();

  factory PromptSubject.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptSubject()..mergeFromBuffer(data, registry);
  factory PromptSubject.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptSubject()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PromptSubject',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PromptSubject.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..aOS(2, _omitFieldNames ? '' : 'instanceId')
    ..aOS(3, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptSubject clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptSubject copyWith(void Function(PromptSubject) updates) =>
      super.copyWith((message) => updates(message as PromptSubject))
          as PromptSubject;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PromptSubject() / PromptSubject.new instead')
  static PromptSubject create() => PromptSubject._();
  static $pb.GeneratedMessage $_createMessage() => PromptSubject._();
  @$core.override
  PromptSubject createEmptyInstance() => PromptSubject._();
  @$core.pragma('dart2js:noInline')
  static PromptSubject getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PromptSubject>(
          PromptSubject.$_createMessage);
  static PromptSubject? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get instanceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set instanceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstanceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstanceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get accountId => $_getSZ(2);
  @$pb.TagNumber(3)
  set accountId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccountId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccountId() => $_clearField(3);
}

class PromptsResyncRequired extends $pb.GeneratedMessage {
  factory PromptsResyncRequired() => PromptsResyncRequired._();

  PromptsResyncRequired._();

  factory PromptsResyncRequired.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptsResyncRequired()..mergeFromBuffer(data, registry);
  factory PromptsResyncRequired.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PromptsResyncRequired()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PromptsResyncRequired',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PromptsResyncRequired.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptsResyncRequired clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PromptsResyncRequired copyWith(
          void Function(PromptsResyncRequired) updates) =>
      super.copyWith((message) => updates(message as PromptsResyncRequired))
          as PromptsResyncRequired;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PromptsResyncRequired() / PromptsResyncRequired.new instead')
  static PromptsResyncRequired create() => PromptsResyncRequired._();
  static $pb.GeneratedMessage $_createMessage() => PromptsResyncRequired._();
  @$core.override
  PromptsResyncRequired createEmptyInstance() => PromptsResyncRequired._();
  @$core.pragma('dart2js:noInline')
  static PromptsResyncRequired getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PromptsResyncRequired>(
          PromptsResyncRequired.$_createMessage);
  static PromptsResyncRequired? _defaultInstance;
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
