// This is a generated file - do not edit.
//
// Generated from yagura/v1/common.proto.

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

@$core.Deprecated('Use protocolDescriptor instead')
const Protocol$json = {
  '1': 'Protocol',
  '2': [
    {'1': 'PROTOCOL_UNSPECIFIED', '2': 0},
    {'1': 'PROTOCOL_UDP', '2': 1},
    {'1': 'PROTOCOL_TCP', '2': 2},
    {'1': 'PROTOCOL_BOTH', '2': 3},
  ],
};

/// Descriptor for `Protocol`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List protocolDescriptor = $convert.base64Decode(
    'CghQcm90b2NvbBIYChRQUk9UT0NPTF9VTlNQRUNJRklFRBAAEhAKDFBST1RPQ09MX1VEUBABEh'
    'AKDFBST1RPQ09MX1RDUBACEhEKDVBST1RPQ09MX0JPVEgQAw==');

@$core.Deprecated('Use errorDetailDescriptor instead')
const ErrorDetail$json = {
  '1': 'ErrorDetail',
  '2': [
    {'1': 'reason', '3': 1, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {
      '1': 'field_violations',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.FieldViolation',
      '10': 'fieldViolations'
    },
    {'1': 'incident_id', '3': 4, '4': 1, '5': 9, '10': 'incidentId'},
    {
      '1': 'metadata',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.ErrorDetail.MetadataEntry',
      '10': 'metadata'
    },
  ],
  '3': [ErrorDetail_MetadataEntry$json],
};

@$core.Deprecated('Use errorDetailDescriptor instead')
const ErrorDetail_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ErrorDetail`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorDetailDescriptor = $convert.base64Decode(
    'CgtFcnJvckRldGFpbBIWCgZyZWFzb24YASABKAlSBnJlYXNvbhIYCgdtZXNzYWdlGAIgASgJUg'
    'dtZXNzYWdlEkQKEGZpZWxkX3Zpb2xhdGlvbnMYAyADKAsyGS55YWd1cmEudjEuRmllbGRWaW9s'
    'YXRpb25SD2ZpZWxkVmlvbGF0aW9ucxIfCgtpbmNpZGVudF9pZBgEIAEoCVIKaW5jaWRlbnRJZB'
    'JACghtZXRhZGF0YRgFIAMoCzIkLnlhZ3VyYS52MS5FcnJvckRldGFpbC5NZXRhZGF0YUVudHJ5'
    'UghtZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGA'
    'IgASgJUgV2YWx1ZToCOAE=');

@$core.Deprecated('Use fieldViolationDescriptor instead')
const FieldViolation$json = {
  '1': 'FieldViolation',
  '2': [
    {'1': 'field', '3': 1, '4': 1, '5': 9, '10': 'field'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `FieldViolation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fieldViolationDescriptor = $convert.base64Decode(
    'Cg5GaWVsZFZpb2xhdGlvbhIUCgVmaWVsZBgBIAEoCVIFZmllbGQSIAoLZGVzY3JpcHRpb24YAi'
    'ABKAlSC2Rlc2NyaXB0aW9u');

@$core.Deprecated('Use jsonDocumentDescriptor instead')
const JsonDocument$json = {
  '1': 'JsonDocument',
  '2': [
    {'1': 'json', '3': 1, '4': 1, '5': 9, '10': 'json'},
    {'1': 'schema_version', '3': 2, '4': 1, '5': 13, '10': 'schemaVersion'},
  ],
};

/// Descriptor for `JsonDocument`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jsonDocumentDescriptor = $convert.base64Decode(
    'CgxKc29uRG9jdW1lbnQSEgoEanNvbhgBIAEoCVIEanNvbhIlCg5zY2hlbWFfdmVyc2lvbhgCIA'
    'EoDVINc2NoZW1hVmVyc2lvbg==');

@$core.Deprecated('Use portDescriptor instead')
const Port$json = {
  '1': 'Port',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'number', '3': 2, '4': 1, '5': 13, '10': 'number'},
    {
      '1': 'protocol',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.yagura.v1.Protocol',
      '10': 'protocol'
    },
    {'1': 'purpose', '3': 4, '4': 1, '5': 9, '10': 'purpose'},
    {'1': 'exposed', '3': 5, '4': 1, '5': 8, '10': 'exposed'},
  ],
};

/// Descriptor for `Port`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List portDescriptor = $convert.base64Decode(
    'CgRQb3J0EhIKBG5hbWUYASABKAlSBG5hbWUSFgoGbnVtYmVyGAIgASgNUgZudW1iZXISLwoIcH'
    'JvdG9jb2wYAyABKA4yEy55YWd1cmEudjEuUHJvdG9jb2xSCHByb3RvY29sEhgKB3B1cnBvc2UY'
    'BCABKAlSB3B1cnBvc2USGAoHZXhwb3NlZBgFIAEoCFIHZXhwb3NlZA==');

@$core.Deprecated('Use emptyDescriptor instead')
const Empty$json = {
  '1': 'Empty',
};

/// Descriptor for `Empty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emptyDescriptor =
    $convert.base64Decode('CgVFbXB0eQ==');
