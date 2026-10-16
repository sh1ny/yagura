// This is a generated file - do not edit.
//
// Generated from yagura/v1/steam.proto.

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

@$core.Deprecated('Use steamAccountDescriptor instead')
const SteamAccount$json = {
  '1': 'SteamAccount',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'status', '3': 3, '4': 1, '5': 9, '10': 'status'},
    {
      '1': 'password_remembered',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'passwordRemembered'
    },
    {
      '1': 'last_login_at',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastLoginAt'
    },
    {
      '1': 'used_by_instance_ids',
      '3': 6,
      '4': 3,
      '5': 9,
      '10': 'usedByInstanceIds'
    },
  ],
};

/// Descriptor for `SteamAccount`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List steamAccountDescriptor = $convert.base64Decode(
    'CgxTdGVhbUFjY291bnQSDgoCaWQYASABKAlSAmlkEhoKCHVzZXJuYW1lGAIgASgJUgh1c2Vybm'
    'FtZRIWCgZzdGF0dXMYAyABKAlSBnN0YXR1cxIvChNwYXNzd29yZF9yZW1lbWJlcmVkGAQgASgI'
    'UhJwYXNzd29yZFJlbWVtYmVyZWQSPgoNbGFzdF9sb2dpbl9hdBgFIAEoCzIaLmdvb2dsZS5wcm'
    '90b2J1Zi5UaW1lc3RhbXBSC2xhc3RMb2dpbkF0Ei8KFHVzZWRfYnlfaW5zdGFuY2VfaWRzGAYg'
    'AygJUhF1c2VkQnlJbnN0YW5jZUlkcw==');

@$core.Deprecated('Use listAccountsRequestDescriptor instead')
const ListAccountsRequest$json = {
  '1': 'ListAccountsRequest',
};

/// Descriptor for `ListAccountsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listAccountsRequestDescriptor =
    $convert.base64Decode('ChNMaXN0QWNjb3VudHNSZXF1ZXN0');

@$core.Deprecated('Use listAccountsResponseDescriptor instead')
const ListAccountsResponse$json = {
  '1': 'ListAccountsResponse',
  '2': [
    {
      '1': 'accounts',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.SteamAccount',
      '10': 'accounts'
    },
  ],
};

/// Descriptor for `ListAccountsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listAccountsResponseDescriptor = $convert.base64Decode(
    'ChRMaXN0QWNjb3VudHNSZXNwb25zZRIzCghhY2NvdW50cxgBIAMoCzIXLnlhZ3VyYS52MS5TdG'
    'VhbUFjY291bnRSCGFjY291bnRz');

@$core.Deprecated('Use addAccountRequestDescriptor instead')
const AddAccountRequest$json = {
  '1': 'AddAccountRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
    {
      '1': 'remember_password',
      '3': 3,
      '4': 1,
      '5': 8,
      '10': 'rememberPassword'
    },
  ],
};

/// Descriptor for `AddAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addAccountRequestDescriptor = $convert.base64Decode(
    'ChFBZGRBY2NvdW50UmVxdWVzdBIaCgh1c2VybmFtZRgBIAEoCVIIdXNlcm5hbWUSGgoIcGFzc3'
    'dvcmQYAiABKAlSCHBhc3N3b3JkEisKEXJlbWVtYmVyX3Bhc3N3b3JkGAMgASgIUhByZW1lbWJl'
    'clBhc3N3b3Jk');

@$core.Deprecated('Use reauthAccountRequestDescriptor instead')
const ReauthAccountRequest$json = {
  '1': 'ReauthAccountRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
    {
      '1': 'remember_password',
      '3': 3,
      '4': 1,
      '5': 8,
      '10': 'rememberPassword'
    },
  ],
};

/// Descriptor for `ReauthAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reauthAccountRequestDescriptor = $convert.base64Decode(
    'ChRSZWF1dGhBY2NvdW50UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SWQSGg'
    'oIcGFzc3dvcmQYAiABKAlSCHBhc3N3b3JkEisKEXJlbWVtYmVyX3Bhc3N3b3JkGAMgASgIUhBy'
    'ZW1lbWJlclBhc3N3b3Jk');

@$core.Deprecated('Use removeAccountRequestDescriptor instead')
const RemoveAccountRequest$json = {
  '1': 'RemoveAccountRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `RemoveAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List removeAccountRequestDescriptor = $convert.base64Decode(
    'ChRSZW1vdmVBY2NvdW50UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SWQ=');
