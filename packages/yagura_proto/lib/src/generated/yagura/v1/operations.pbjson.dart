// This is a generated file - do not edit.
//
// Generated from yagura/v1/operations.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use operationStatusDescriptor instead')
const OperationStatus$json = {
  '1': 'OperationStatus',
  '2': [
    {'1': 'OPERATION_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'OPERATION_STATUS_QUEUED', '2': 1},
    {'1': 'OPERATION_STATUS_RUNNING', '2': 2},
    {'1': 'OPERATION_STATUS_WAITING_FOR_INPUT', '2': 3},
    {'1': 'OPERATION_STATUS_SUCCEEDED', '2': 4},
    {'1': 'OPERATION_STATUS_FAILED', '2': 5},
    {'1': 'OPERATION_STATUS_CANCELLED', '2': 6},
    {'1': 'OPERATION_STATUS_INTERRUPTED', '2': 7},
  ],
};

/// Descriptor for `OperationStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List operationStatusDescriptor = $convert.base64Decode(
    'Cg9PcGVyYXRpb25TdGF0dXMSIAocT1BFUkFUSU9OX1NUQVRVU19VTlNQRUNJRklFRBAAEhsKF0'
    '9QRVJBVElPTl9TVEFUVVNfUVVFVUVEEAESHAoYT1BFUkFUSU9OX1NUQVRVU19SVU5OSU5HEAIS'
    'JgoiT1BFUkFUSU9OX1NUQVRVU19XQUlUSU5HX0ZPUl9JTlBVVBADEh4KGk9QRVJBVElPTl9TVE'
    'FUVVNfU1VDQ0VFREVEEAQSGwoXT1BFUkFUSU9OX1NUQVRVU19GQUlMRUQQBRIeChpPUEVSQVRJ'
    'T05fU1RBVFVTX0NBTkNFTExFRBAGEiAKHE9QRVJBVElPTl9TVEFUVVNfSU5URVJSVVBURUQQBw'
    '==');

@$core.Deprecated('Use operationDescriptor instead')
const Operation$json = {
  '1': 'Operation',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'instance_id', '3': 2, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'kind', '3': 3, '4': 1, '5': 9, '10': 'kind'},
    {
      '1': 'status',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.yagura.v1.OperationStatus',
      '10': 'status'
    },
    {'1': 'queue_position', '3': 5, '4': 1, '5': 13, '10': 'queuePosition'},
    {'1': 'current_step', '3': 6, '4': 1, '5': 9, '10': 'currentStep'},
    {
      '1': 'created_at',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {
      '1': 'started_at',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'startedAt'
    },
    {
      '1': 'ended_at',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'endedAt'
    },
    {
      '1': 'requested_by_device_id',
      '3': 10,
      '4': 1,
      '5': 9,
      '10': 'requestedByDeviceId'
    },
    {'1': 'result_reason', '3': 11, '4': 1, '5': 9, '10': 'resultReason'},
    {'1': 'result_message', '3': 12, '4': 1, '5': 9, '10': 'resultMessage'},
    {'1': 'warnings', '3': 13, '4': 3, '5': 9, '10': 'warnings'},
    {
      '1': 'pending_prompt',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Prompt',
      '10': 'pendingPrompt'
    },
    {'1': 'last_sequence', '3': 15, '4': 1, '5': 4, '10': 'lastSequence'},
  ],
};

/// Descriptor for `Operation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List operationDescriptor = $convert.base64Decode(
    'CglPcGVyYXRpb24SDgoCaWQYASABKAlSAmlkEh8KC2luc3RhbmNlX2lkGAIgASgJUgppbnN0YW'
    '5jZUlkEhIKBGtpbmQYAyABKAlSBGtpbmQSMgoGc3RhdHVzGAQgASgOMhoueWFndXJhLnYxLk9w'
    'ZXJhdGlvblN0YXR1c1IGc3RhdHVzEiUKDnF1ZXVlX3Bvc2l0aW9uGAUgASgNUg1xdWV1ZVBvc2'
    'l0aW9uEiEKDGN1cnJlbnRfc3RlcBgGIAEoCVILY3VycmVudFN0ZXASOQoKY3JlYXRlZF9hdBgH'
    'IAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCWNyZWF0ZWRBdBI5CgpzdGFydGVkX2'
    'F0GAggASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJc3RhcnRlZEF0EjUKCGVuZGVk'
    'X2F0GAkgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIHZW5kZWRBdBIzChZyZXF1ZX'
    'N0ZWRfYnlfZGV2aWNlX2lkGAogASgJUhNyZXF1ZXN0ZWRCeURldmljZUlkEiMKDXJlc3VsdF9y'
    'ZWFzb24YCyABKAlSDHJlc3VsdFJlYXNvbhIlCg5yZXN1bHRfbWVzc2FnZRgMIAEoCVINcmVzdW'
    'x0TWVzc2FnZRIaCgh3YXJuaW5ncxgNIAMoCVIId2FybmluZ3MSOAoOcGVuZGluZ19wcm9tcHQY'
    'DiABKAsyES55YWd1cmEudjEuUHJvbXB0Ug1wZW5kaW5nUHJvbXB0EiMKDWxhc3Rfc2VxdWVuY2'
    'UYDyABKARSDGxhc3RTZXF1ZW5jZQ==');

@$core.Deprecated('Use promptDescriptor instead')
const Prompt$json = {
  '1': 'Prompt',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'kind', '3': 2, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'message', '3': 3, '4': 1, '5': 9, '10': 'message'},
    {'1': 'steam_account', '3': 4, '4': 1, '5': 9, '10': 'steamAccount'},
    {
      '1': 'expires_at',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'expiresAt'
    },
  ],
};

/// Descriptor for `Prompt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List promptDescriptor = $convert.base64Decode(
    'CgZQcm9tcHQSDgoCaWQYASABKAlSAmlkEhIKBGtpbmQYAiABKAlSBGtpbmQSGAoHbWVzc2FnZR'
    'gDIAEoCVIHbWVzc2FnZRIjCg1zdGVhbV9hY2NvdW50GAQgASgJUgxzdGVhbUFjY291bnQSOQoK'
    'ZXhwaXJlc19hdBgFIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCWV4cGlyZXNBdA'
    '==');

@$core.Deprecated('Use operationEventDescriptor instead')
const OperationEvent$json = {
  '1': 'OperationEvent',
  '2': [
    {'1': 'sequence', '3': 1, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'at',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'at'
    },
    {
      '1': 'step_started',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.StepStarted',
      '9': 0,
      '10': 'stepStarted'
    },
    {
      '1': 'progress',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Progress',
      '9': 0,
      '10': 'progress'
    },
    {
      '1': 'log',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.LogLine',
      '9': 0,
      '10': 'log'
    },
    {
      '1': 'prompt',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Prompt',
      '9': 0,
      '10': 'prompt'
    },
    {
      '1': 'prompt_resolved',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.PromptResolved',
      '9': 0,
      '10': 'promptResolved'
    },
    {
      '1': 'finished',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Operation',
      '9': 0,
      '10': 'finished'
    },
    {
      '1': 'events_dropped',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.EventsDropped',
      '9': 0,
      '10': 'eventsDropped'
    },
    {
      '1': 'snapshot',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Operation',
      '9': 0,
      '10': 'snapshot'
    },
  ],
  '8': [
    {'1': 'event'},
  ],
};

/// Descriptor for `OperationEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List operationEventDescriptor = $convert.base64Decode(
    'Cg5PcGVyYXRpb25FdmVudBIaCghzZXF1ZW5jZRgBIAEoBFIIc2VxdWVuY2USKgoCYXQYAiABKA'
    'syGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgJhdBI7CgxzdGVwX3N0YXJ0ZWQYAyABKAsy'
    'Fi55YWd1cmEudjEuU3RlcFN0YXJ0ZWRIAFILc3RlcFN0YXJ0ZWQSMQoIcHJvZ3Jlc3MYBCABKA'
    'syEy55YWd1cmEudjEuUHJvZ3Jlc3NIAFIIcHJvZ3Jlc3MSJgoDbG9nGAUgASgLMhIueWFndXJh'
    'LnYxLkxvZ0xpbmVIAFIDbG9nEisKBnByb21wdBgGIAEoCzIRLnlhZ3VyYS52MS5Qcm9tcHRIAF'
    'IGcHJvbXB0EkQKD3Byb21wdF9yZXNvbHZlZBgHIAEoCzIZLnlhZ3VyYS52MS5Qcm9tcHRSZXNv'
    'bHZlZEgAUg5wcm9tcHRSZXNvbHZlZBIyCghmaW5pc2hlZBgIIAEoCzIULnlhZ3VyYS52MS5PcG'
    'VyYXRpb25IAFIIZmluaXNoZWQSQQoOZXZlbnRzX2Ryb3BwZWQYCSABKAsyGC55YWd1cmEudjEu'
    'RXZlbnRzRHJvcHBlZEgAUg1ldmVudHNEcm9wcGVkEjIKCHNuYXBzaG90GAogASgLMhQueWFndX'
    'JhLnYxLk9wZXJhdGlvbkgAUghzbmFwc2hvdEIHCgVldmVudA==');

@$core.Deprecated('Use eventsDroppedDescriptor instead')
const EventsDropped$json = {
  '1': 'EventsDropped',
  '2': [
    {'1': 'from_sequence', '3': 1, '4': 1, '5': 4, '10': 'fromSequence'},
    {'1': 'to_sequence', '3': 2, '4': 1, '5': 4, '10': 'toSequence'},
  ],
};

/// Descriptor for `EventsDropped`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eventsDroppedDescriptor = $convert.base64Decode(
    'Cg1FdmVudHNEcm9wcGVkEiMKDWZyb21fc2VxdWVuY2UYASABKARSDGZyb21TZXF1ZW5jZRIfCg'
    't0b19zZXF1ZW5jZRgCIAEoBFIKdG9TZXF1ZW5jZQ==');

@$core.Deprecated('Use stepStartedDescriptor instead')
const StepStarted$json = {
  '1': 'StepStarted',
  '2': [
    {'1': 'step', '3': 1, '4': 1, '5': 9, '10': 'step'},
  ],
};

/// Descriptor for `StepStarted`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stepStartedDescriptor =
    $convert.base64Decode('CgtTdGVwU3RhcnRlZBISCgRzdGVwGAEgASgJUgRzdGVw');

@$core.Deprecated('Use progressDescriptor instead')
const Progress$json = {
  '1': 'Progress',
  '2': [
    {'1': 'step', '3': 1, '4': 1, '5': 9, '10': 'step'},
    {'1': 'percent', '3': 2, '4': 1, '5': 1, '10': 'percent'},
    {'1': 'bytes_done', '3': 3, '4': 1, '5': 4, '10': 'bytesDone'},
    {'1': 'bytes_total', '3': 4, '4': 1, '5': 4, '10': 'bytesTotal'},
  ],
};

/// Descriptor for `Progress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List progressDescriptor = $convert.base64Decode(
    'CghQcm9ncmVzcxISCgRzdGVwGAEgASgJUgRzdGVwEhgKB3BlcmNlbnQYAiABKAFSB3BlcmNlbn'
    'QSHQoKYnl0ZXNfZG9uZRgDIAEoBFIJYnl0ZXNEb25lEh8KC2J5dGVzX3RvdGFsGAQgASgEUgpi'
    'eXRlc1RvdGFs');

@$core.Deprecated('Use logLineDescriptor instead')
const LogLine$json = {
  '1': 'LogLine',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `LogLine`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List logLineDescriptor =
    $convert.base64Decode('CgdMb2dMaW5lEhIKBHRleHQYASABKAlSBHRleHQ=');

@$core.Deprecated('Use promptResolvedDescriptor instead')
const PromptResolved$json = {
  '1': 'PromptResolved',
  '2': [
    {'1': 'prompt_id', '3': 1, '4': 1, '5': 9, '10': 'promptId'},
    {'1': 'by_device_id', '3': 2, '4': 1, '5': 9, '10': 'byDeviceId'},
    {'1': 'outcome', '3': 3, '4': 1, '5': 9, '10': 'outcome'},
  ],
};

/// Descriptor for `PromptResolved`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List promptResolvedDescriptor = $convert.base64Decode(
    'Cg5Qcm9tcHRSZXNvbHZlZBIbCglwcm9tcHRfaWQYASABKAlSCHByb21wdElkEiAKDGJ5X2Rldm'
    'ljZV9pZBgCIAEoCVIKYnlEZXZpY2VJZBIYCgdvdXRjb21lGAMgASgJUgdvdXRjb21l');

@$core.Deprecated('Use getOperationRequestDescriptor instead')
const GetOperationRequest$json = {
  '1': 'GetOperationRequest',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
  ],
};

/// Descriptor for `GetOperationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getOperationRequestDescriptor = $convert.base64Decode(
    'ChNHZXRPcGVyYXRpb25SZXF1ZXN0EiEKDG9wZXJhdGlvbl9pZBgBIAEoCVILb3BlcmF0aW9uSW'
    'Q=');

@$core.Deprecated('Use listOperationsRequestDescriptor instead')
const ListOperationsRequest$json = {
  '1': 'ListOperationsRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'page_size', '3': 2, '4': 1, '5': 13, '10': 'pageSize'},
    {'1': 'page_token', '3': 3, '4': 1, '5': 9, '10': 'pageToken'},
  ],
};

/// Descriptor for `ListOperationsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listOperationsRequestDescriptor = $convert.base64Decode(
    'ChVMaXN0T3BlcmF0aW9uc1JlcXVlc3QSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSW'
    'QSGwoJcGFnZV9zaXplGAIgASgNUghwYWdlU2l6ZRIdCgpwYWdlX3Rva2VuGAMgASgJUglwYWdl'
    'VG9rZW4=');

@$core.Deprecated('Use listOperationsResponseDescriptor instead')
const ListOperationsResponse$json = {
  '1': 'ListOperationsResponse',
  '2': [
    {
      '1': 'operations',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Operation',
      '10': 'operations'
    },
    {'1': 'next_page_token', '3': 2, '4': 1, '5': 9, '10': 'nextPageToken'},
  ],
};

/// Descriptor for `ListOperationsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listOperationsResponseDescriptor = $convert.base64Decode(
    'ChZMaXN0T3BlcmF0aW9uc1Jlc3BvbnNlEjQKCm9wZXJhdGlvbnMYASADKAsyFC55YWd1cmEudj'
    'EuT3BlcmF0aW9uUgpvcGVyYXRpb25zEiYKD25leHRfcGFnZV90b2tlbhgCIAEoCVINbmV4dFBh'
    'Z2VUb2tlbg==');

@$core.Deprecated('Use watchOperationRequestDescriptor instead')
const WatchOperationRequest$json = {
  '1': 'WatchOperationRequest',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
    {'1': 'after_sequence', '3': 2, '4': 1, '5': 4, '10': 'afterSequence'},
  ],
};

/// Descriptor for `WatchOperationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchOperationRequestDescriptor = $convert.base64Decode(
    'ChVXYXRjaE9wZXJhdGlvblJlcXVlc3QSIQoMb3BlcmF0aW9uX2lkGAEgASgJUgtvcGVyYXRpb2'
    '5JZBIlCg5hZnRlcl9zZXF1ZW5jZRgCIAEoBFINYWZ0ZXJTZXF1ZW5jZQ==');

@$core.Deprecated('Use cancelOperationRequestDescriptor instead')
const CancelOperationRequest$json = {
  '1': 'CancelOperationRequest',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
  ],
};

/// Descriptor for `CancelOperationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cancelOperationRequestDescriptor =
    $convert.base64Decode(
        'ChZDYW5jZWxPcGVyYXRpb25SZXF1ZXN0EiEKDG9wZXJhdGlvbl9pZBgBIAEoCVILb3BlcmF0aW'
        '9uSWQ=');

@$core.Deprecated('Use respondToPromptRequestDescriptor instead')
const RespondToPromptRequest$json = {
  '1': 'RespondToPromptRequest',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
    {'1': 'prompt_id', '3': 2, '4': 1, '5': 9, '10': 'promptId'},
    {'1': 'value', '3': 3, '4': 1, '5': 9, '10': 'value'},
  ],
};

/// Descriptor for `RespondToPromptRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List respondToPromptRequestDescriptor = $convert.base64Decode(
    'ChZSZXNwb25kVG9Qcm9tcHRSZXF1ZXN0EiEKDG9wZXJhdGlvbl9pZBgBIAEoCVILb3BlcmF0aW'
    '9uSWQSGwoJcHJvbXB0X2lkGAIgASgJUghwcm9tcHRJZBIUCgV2YWx1ZRgDIAEoCVIFdmFsdWU=');

@$core.Deprecated('Use watchPromptsRequestDescriptor instead')
const WatchPromptsRequest$json = {
  '1': 'WatchPromptsRequest',
};

/// Descriptor for `WatchPromptsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchPromptsRequestDescriptor =
    $convert.base64Decode('ChNXYXRjaFByb21wdHNSZXF1ZXN0');

@$core.Deprecated('Use promptEventDescriptor instead')
const PromptEvent$json = {
  '1': 'PromptEvent',
  '2': [
    {
      '1': 'snapshot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.PromptSnapshot',
      '9': 0,
      '10': 'snapshot'
    },
    {
      '1': 'raised',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.PendingPrompt',
      '9': 0,
      '10': 'raised'
    },
    {
      '1': 'resolved',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.PromptResolved',
      '9': 0,
      '10': 'resolved'
    },
    {
      '1': 'resync_required',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.PromptsResyncRequired',
      '9': 0,
      '10': 'resyncRequired'
    },
  ],
  '8': [
    {'1': 'event'},
  ],
};

/// Descriptor for `PromptEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List promptEventDescriptor = $convert.base64Decode(
    'CgtQcm9tcHRFdmVudBI3CghzbmFwc2hvdBgBIAEoCzIZLnlhZ3VyYS52MS5Qcm9tcHRTbmFwc2'
    'hvdEgAUghzbmFwc2hvdBIyCgZyYWlzZWQYAiABKAsyGC55YWd1cmEudjEuUGVuZGluZ1Byb21w'
    'dEgAUgZyYWlzZWQSNwoIcmVzb2x2ZWQYAyABKAsyGS55YWd1cmEudjEuUHJvbXB0UmVzb2x2ZW'
    'RIAFIIcmVzb2x2ZWQSSwoPcmVzeW5jX3JlcXVpcmVkGAQgASgLMiAueWFndXJhLnYxLlByb21w'
    'dHNSZXN5bmNSZXF1aXJlZEgAUg5yZXN5bmNSZXF1aXJlZEIHCgVldmVudA==');

@$core.Deprecated('Use promptSnapshotDescriptor instead')
const PromptSnapshot$json = {
  '1': 'PromptSnapshot',
  '2': [
    {
      '1': 'prompts',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.PendingPrompt',
      '10': 'prompts'
    },
  ],
};

/// Descriptor for `PromptSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List promptSnapshotDescriptor = $convert.base64Decode(
    'Cg5Qcm9tcHRTbmFwc2hvdBIyCgdwcm9tcHRzGAEgAygLMhgueWFndXJhLnYxLlBlbmRpbmdQcm'
    '9tcHRSB3Byb21wdHM=');

@$core.Deprecated('Use pendingPromptDescriptor instead')
const PendingPrompt$json = {
  '1': 'PendingPrompt',
  '2': [
    {
      '1': 'prompt',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Prompt',
      '10': 'prompt'
    },
    {
      '1': 'operations',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.PromptSubject',
      '10': 'operations'
    },
  ],
};

/// Descriptor for `PendingPrompt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pendingPromptDescriptor = $convert.base64Decode(
    'Cg1QZW5kaW5nUHJvbXB0EikKBnByb21wdBgBIAEoCzIRLnlhZ3VyYS52MS5Qcm9tcHRSBnByb2'
    '1wdBI4CgpvcGVyYXRpb25zGAIgAygLMhgueWFndXJhLnYxLlByb21wdFN1YmplY3RSCm9wZXJh'
    'dGlvbnM=');

@$core.Deprecated('Use promptSubjectDescriptor instead')
const PromptSubject$json = {
  '1': 'PromptSubject',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
    {'1': 'instance_id', '3': 2, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'account_id', '3': 3, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `PromptSubject`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List promptSubjectDescriptor = $convert.base64Decode(
    'Cg1Qcm9tcHRTdWJqZWN0EiEKDG9wZXJhdGlvbl9pZBgBIAEoCVILb3BlcmF0aW9uSWQSHwoLaW'
    '5zdGFuY2VfaWQYAiABKAlSCmluc3RhbmNlSWQSHQoKYWNjb3VudF9pZBgDIAEoCVIJYWNjb3Vu'
    'dElk');

@$core.Deprecated('Use promptsResyncRequiredDescriptor instead')
const PromptsResyncRequired$json = {
  '1': 'PromptsResyncRequired',
};

/// Descriptor for `PromptsResyncRequired`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List promptsResyncRequiredDescriptor =
    $convert.base64Decode('ChVQcm9tcHRzUmVzeW5jUmVxdWlyZWQ=');
