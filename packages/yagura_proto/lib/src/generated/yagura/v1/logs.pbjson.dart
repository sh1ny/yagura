// This is a generated file - do not edit.
//
// Generated from yagura/v1/logs.proto.

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

@$core.Deprecated('Use logSourceDescriptor instead')
const LogSource$json = {
  '1': 'LogSource',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'kind', '3': 2, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'status', '3': 3, '4': 1, '5': 9, '10': 'status'},
    {'1': 'current_file', '3': 4, '4': 1, '5': 9, '10': 'currentFile'},
    {'1': 'encoding', '3': 5, '4': 1, '5': 9, '10': 'encoding'},
    {'1': 'last_error', '3': 6, '4': 1, '5': 9, '10': 'lastError'},
  ],
};

/// Descriptor for `LogSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List logSourceDescriptor = $convert.base64Decode(
    'CglMb2dTb3VyY2USEgoEbmFtZRgBIAEoCVIEbmFtZRISCgRraW5kGAIgASgJUgRraW5kEhYKBn'
    'N0YXR1cxgDIAEoCVIGc3RhdHVzEiEKDGN1cnJlbnRfZmlsZRgEIAEoCVILY3VycmVudEZpbGUS'
    'GgoIZW5jb2RpbmcYBSABKAlSCGVuY29kaW5nEh0KCmxhc3RfZXJyb3IYBiABKAlSCWxhc3RFcn'
    'Jvcg==');

@$core.Deprecated('Use listSourcesRequestDescriptor instead')
const ListSourcesRequest$json = {
  '1': 'ListSourcesRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
  ],
};

/// Descriptor for `ListSourcesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSourcesRequestDescriptor = $convert.base64Decode(
    'ChJMaXN0U291cmNlc1JlcXVlc3QSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSWQ=');

@$core.Deprecated('Use listSourcesResponseDescriptor instead')
const ListSourcesResponse$json = {
  '1': 'ListSourcesResponse',
  '2': [
    {
      '1': 'sources',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.LogSource',
      '10': 'sources'
    },
  ],
};

/// Descriptor for `ListSourcesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSourcesResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0U291cmNlc1Jlc3BvbnNlEi4KB3NvdXJjZXMYASADKAsyFC55YWd1cmEudjEuTG9nU2'
    '91cmNlUgdzb3VyY2Vz');

@$core.Deprecated('Use backlogRequestDescriptor instead')
const BacklogRequest$json = {
  '1': 'BacklogRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'sources', '3': 2, '4': 3, '5': 9, '10': 'sources'},
    {'1': 'lines', '3': 3, '4': 1, '5': 13, '10': 'lines'},
  ],
};

/// Descriptor for `BacklogRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List backlogRequestDescriptor = $convert.base64Decode(
    'Cg5CYWNrbG9nUmVxdWVzdBIfCgtpbnN0YW5jZV9pZBgBIAEoCVIKaW5zdGFuY2VJZBIYCgdzb3'
    'VyY2VzGAIgAygJUgdzb3VyY2VzEhQKBWxpbmVzGAMgASgNUgVsaW5lcw==');

@$core.Deprecated('Use followRequestDescriptor instead')
const FollowRequest$json = {
  '1': 'FollowRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'sources', '3': 2, '4': 3, '5': 9, '10': 'sources'},
  ],
};

/// Descriptor for `FollowRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List followRequestDescriptor = $convert.base64Decode(
    'Cg1Gb2xsb3dSZXF1ZXN0Eh8KC2luc3RhbmNlX2lkGAEgASgJUgppbnN0YW5jZUlkEhgKB3NvdX'
    'JjZXMYAiADKAlSB3NvdXJjZXM=');

@$core.Deprecated('Use logEntryDescriptor instead')
const LogEntry$json = {
  '1': 'LogEntry',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
    {'1': 'sequence', '3': 2, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'received_at',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'receivedAt'
    },
    {'1': 'text', '3': 4, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `LogEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List logEntryDescriptor = $convert.base64Decode(
    'CghMb2dFbnRyeRIWCgZzb3VyY2UYASABKAlSBnNvdXJjZRIaCghzZXF1ZW5jZRgCIAEoBFIIc2'
    'VxdWVuY2USOwoLcmVjZWl2ZWRfYXQYAyABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1w'
    'UgpyZWNlaXZlZEF0EhIKBHRleHQYBCABKAlSBHRleHQ=');

@$core.Deprecated('Use logBatchDescriptor instead')
const LogBatch$json = {
  '1': 'LogBatch',
  '2': [
    {
      '1': 'entries',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.LogEntry',
      '10': 'entries'
    },
    {'1': 'dropped', '3': 2, '4': 1, '5': 4, '10': 'dropped'},
    {'1': 'truncated', '3': 3, '4': 1, '5': 8, '10': 'truncated'},
    {'1': 'source_event', '3': 4, '4': 1, '5': 9, '10': 'sourceEvent'},
  ],
};

/// Descriptor for `LogBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List logBatchDescriptor = $convert.base64Decode(
    'CghMb2dCYXRjaBItCgdlbnRyaWVzGAEgAygLMhMueWFndXJhLnYxLkxvZ0VudHJ5UgdlbnRyaW'
    'VzEhgKB2Ryb3BwZWQYAiABKARSB2Ryb3BwZWQSHAoJdHJ1bmNhdGVkGAMgASgIUgl0cnVuY2F0'
    'ZWQSIQoMc291cmNlX2V2ZW50GAQgASgJUgtzb3VyY2VFdmVudA==');
