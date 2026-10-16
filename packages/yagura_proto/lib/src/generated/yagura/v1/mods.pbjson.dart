// This is a generated file - do not edit.
//
// Generated from yagura/v1/mods.proto.

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

@$core.Deprecated('Use modDescriptor instead')
const Mod$json = {
  '1': 'Mod',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
    {'1': 'item_id', '3': 2, '4': 1, '5': 9, '10': 'itemId'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
    {'1': 'role', '3': 4, '4': 1, '5': 9, '10': 'role'},
    {'1': 'position', '3': 5, '4': 1, '5': 13, '10': 'position'},
    {'1': 'status', '3': 6, '4': 1, '5': 9, '10': 'status'},
    {'1': 'staged_name', '3': 7, '4': 1, '5': 9, '10': 'stagedName'},
    {'1': 'desired_version', '3': 13, '4': 1, '5': 9, '10': 'desiredVersion'},
    {'1': 'staged_version', '3': 14, '4': 1, '5': 9, '10': 'stagedVersion'},
    {'1': 'size_bytes', '3': 8, '4': 1, '5': 4, '10': 'sizeBytes'},
    {
      '1': 'local_updated',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'localUpdated'
    },
    {
      '1': 'remote_updated',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'remoteUpdated'
    },
    {'1': 'update_available', '3': 11, '4': 1, '5': 8, '10': 'updateAvailable'},
    {'1': 'last_error', '3': 12, '4': 1, '5': 9, '10': 'lastError'},
  ],
};

/// Descriptor for `Mod`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modDescriptor = $convert.base64Decode(
    'CgNNb2QSFgoGc291cmNlGAEgASgJUgZzb3VyY2USFwoHaXRlbV9pZBgCIAEoCVIGaXRlbUlkEh'
    'IKBG5hbWUYAyABKAlSBG5hbWUSEgoEcm9sZRgEIAEoCVIEcm9sZRIaCghwb3NpdGlvbhgFIAEo'
    'DVIIcG9zaXRpb24SFgoGc3RhdHVzGAYgASgJUgZzdGF0dXMSHwoLc3RhZ2VkX25hbWUYByABKA'
    'lSCnN0YWdlZE5hbWUSJwoPZGVzaXJlZF92ZXJzaW9uGA0gASgJUg5kZXNpcmVkVmVyc2lvbhIl'
    'Cg5zdGFnZWRfdmVyc2lvbhgOIAEoCVINc3RhZ2VkVmVyc2lvbhIdCgpzaXplX2J5dGVzGAggAS'
    'gEUglzaXplQnl0ZXMSPwoNbG9jYWxfdXBkYXRlZBgJIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5U'
    'aW1lc3RhbXBSDGxvY2FsVXBkYXRlZBJBCg5yZW1vdGVfdXBkYXRlZBgKIAEoCzIaLmdvb2dsZS'
    '5wcm90b2J1Zi5UaW1lc3RhbXBSDXJlbW90ZVVwZGF0ZWQSKQoQdXBkYXRlX2F2YWlsYWJsZRgL'
    'IAEoCFIPdXBkYXRlQXZhaWxhYmxlEh0KCmxhc3RfZXJyb3IYDCABKAlSCWxhc3RFcnJvcg==');

@$core.Deprecated('Use listModsRequestDescriptor instead')
const ListModsRequest$json = {
  '1': 'ListModsRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
  ],
};

/// Descriptor for `ListModsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listModsRequestDescriptor = $convert.base64Decode(
    'Cg9MaXN0TW9kc1JlcXVlc3QSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSWQ=');

@$core.Deprecated('Use listModsResponseDescriptor instead')
const ListModsResponse$json = {
  '1': 'ListModsResponse',
  '2': [
    {'1': 'mods', '3': 1, '4': 3, '5': 11, '6': '.yagura.v1.Mod', '10': 'mods'},
    {'1': 'update_check', '3': 2, '4': 1, '5': 9, '10': 'updateCheck'},
    {
      '1': 'checked_at',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'checkedAt'
    },
  ],
};

/// Descriptor for `ListModsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listModsResponseDescriptor = $convert.base64Decode(
    'ChBMaXN0TW9kc1Jlc3BvbnNlEiIKBG1vZHMYASADKAsyDi55YWd1cmEudjEuTW9kUgRtb2RzEi'
    'EKDHVwZGF0ZV9jaGVjaxgCIAEoCVILdXBkYXRlQ2hlY2sSOQoKY2hlY2tlZF9hdBgDIAEoCzIa'
    'Lmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCWNoZWNrZWRBdA==');

@$core.Deprecated('Use modRefDescriptor instead')
const ModRef$json = {
  '1': 'ModRef',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
    {'1': 'item_id', '3': 2, '4': 1, '5': 9, '10': 'itemId'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
  ],
};

/// Descriptor for `ModRef`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modRefDescriptor = $convert.base64Decode(
    'CgZNb2RSZWYSFgoGc291cmNlGAEgASgJUgZzb3VyY2USFwoHaXRlbV9pZBgCIAEoCVIGaXRlbU'
    'lkEhIKBHJvbGUYAyABKAlSBHJvbGU=');

@$core.Deprecated('Use setModsRequestDescriptor instead')
const SetModsRequest$json = {
  '1': 'SetModsRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {
      '1': 'expected_revision',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {
      '1': 'mods',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.ModRef',
      '10': 'mods'
    },
  ],
};

/// Descriptor for `SetModsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setModsRequestDescriptor = $convert.base64Decode(
    'Cg5TZXRNb2RzUmVxdWVzdBIfCgtpbnN0YW5jZV9pZBgBIAEoCVIKaW5zdGFuY2VJZBIrChFleH'
    'BlY3RlZF9yZXZpc2lvbhgDIAEoBFIQZXhwZWN0ZWRSZXZpc2lvbhIlCgRtb2RzGAIgAygLMhEu'
    'eWFndXJhLnYxLk1vZFJlZlIEbW9kcw==');

@$core.Deprecated('Use applyModsRequestDescriptor instead')
const ApplyModsRequest$json = {
  '1': 'ApplyModsRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
  ],
};

/// Descriptor for `ApplyModsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List applyModsRequestDescriptor = $convert.base64Decode(
    'ChBBcHBseU1vZHNSZXF1ZXN0Eh8KC2luc3RhbmNlX2lkGAEgASgJUgppbnN0YW5jZUlk');

@$core.Deprecated('Use checkModUpdatesRequestDescriptor instead')
const CheckModUpdatesRequest$json = {
  '1': 'CheckModUpdatesRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
  ],
};

/// Descriptor for `CheckModUpdatesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkModUpdatesRequestDescriptor =
    $convert.base64Decode(
        'ChZDaGVja01vZFVwZGF0ZXNSZXF1ZXN0Eh8KC2luc3RhbmNlX2lkGAEgASgJUgppbnN0YW5jZU'
        'lk');

@$core.Deprecated('Use updateModsRequestDescriptor instead')
const UpdateModsRequest$json = {
  '1': 'UpdateModsRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'item_ids', '3': 2, '4': 3, '5': 9, '10': 'itemIds'},
  ],
};

/// Descriptor for `UpdateModsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateModsRequestDescriptor = $convert.base64Decode(
    'ChFVcGRhdGVNb2RzUmVxdWVzdBIfCgtpbnN0YW5jZV9pZBgBIAEoCVIKaW5zdGFuY2VJZBIZCg'
    'hpdGVtX2lkcxgCIAMoCVIHaXRlbUlkcw==');
