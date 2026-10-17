// This is a generated file - do not edit.
//
// Generated from yagura/v1/rcon.proto.

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

@$core.Deprecated('Use executeRequestDescriptor instead')
const ExecuteRequest$json = {
  '1': 'ExecuteRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'command', '3': 2, '4': 1, '5': 9, '10': 'command'},
  ],
};

/// Descriptor for `ExecuteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List executeRequestDescriptor = $convert.base64Decode(
    'Cg5FeGVjdXRlUmVxdWVzdBIfCgtpbnN0YW5jZV9pZBgBIAEoCVIKaW5zdGFuY2VJZBIYCgdjb2'
    '1tYW5kGAIgASgJUgdjb21tYW5k');

@$core.Deprecated('Use executeResponseDescriptor instead')
const ExecuteResponse$json = {
  '1': 'ExecuteResponse',
  '2': [
    {'1': 'response', '3': 1, '4': 1, '5': 9, '10': 'response'},
  ],
};

/// Descriptor for `ExecuteResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List executeResponseDescriptor = $convert.base64Decode(
    'Cg9FeGVjdXRlUmVzcG9uc2USGgoIcmVzcG9uc2UYASABKAlSCHJlc3BvbnNl');

@$core.Deprecated('Use consoleInputDescriptor instead')
const ConsoleInput$json = {
  '1': 'ConsoleInput',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'command', '3': 2, '4': 1, '5': 9, '10': 'command'},
  ],
};

/// Descriptor for `ConsoleInput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List consoleInputDescriptor = $convert.base64Decode(
    'CgxDb25zb2xlSW5wdXQSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSWQSGAoHY29tbW'
    'FuZBgCIAEoCVIHY29tbWFuZA==');

@$core.Deprecated('Use consoleOutputDescriptor instead')
const ConsoleOutput$json = {
  '1': 'ConsoleOutput',
  '2': [
    {
      '1': 'at',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'at'
    },
    {
      '1': 'server_message',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'serverMessage'
    },
    {
      '1': 'command',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.CommandEcho',
      '9': 0,
      '10': 'command'
    },
    {'1': 'response', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'response'},
    {'1': 'connection', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'connection'},
  ],
  '8': [
    {'1': 'event'},
  ],
};

/// Descriptor for `ConsoleOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List consoleOutputDescriptor = $convert.base64Decode(
    'Cg1Db25zb2xlT3V0cHV0EioKAmF0GAEgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcF'
    'ICYXQSJwoOc2VydmVyX21lc3NhZ2UYAiABKAlIAFINc2VydmVyTWVzc2FnZRIyCgdjb21tYW5k'
    'GAMgASgLMhYueWFndXJhLnYxLkNvbW1hbmRFY2hvSABSB2NvbW1hbmQSHAoIcmVzcG9uc2UYBC'
    'ABKAlIAFIIcmVzcG9uc2USIAoKY29ubmVjdGlvbhgFIAEoCUgAUgpjb25uZWN0aW9uQgcKBWV2'
    'ZW50');

@$core.Deprecated('Use commandEchoDescriptor instead')
const CommandEcho$json = {
  '1': 'CommandEcho',
  '2': [
    {'1': 'device_name', '3': 1, '4': 1, '5': 9, '10': 'deviceName'},
    {'1': 'command', '3': 2, '4': 1, '5': 9, '10': 'command'},
  ],
};

/// Descriptor for `CommandEcho`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandEchoDescriptor = $convert.base64Decode(
    'CgtDb21tYW5kRWNobxIfCgtkZXZpY2VfbmFtZRgBIAEoCVIKZGV2aWNlTmFtZRIYCgdjb21tYW'
    '5kGAIgASgJUgdjb21tYW5k');
