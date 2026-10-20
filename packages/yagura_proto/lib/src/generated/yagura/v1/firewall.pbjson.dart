// This is a generated file - do not edit.
//
// Generated from yagura/v1/firewall.proto.

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

@$core.Deprecated('Use firewallRuleDescriptor instead')
const FirewallRule$json = {
  '1': 'FirewallRule',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'instance_id', '3': 2, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'port_name', '3': 3, '4': 1, '5': 9, '10': 'portName'},
    {'1': 'port', '3': 4, '4': 1, '5': 13, '10': 'port'},
    {'1': 'protocol', '3': 5, '4': 1, '5': 9, '10': 'protocol'},
    {'1': 'managed', '3': 6, '4': 1, '5': 8, '10': 'managed'},
    {'1': 'present', '3': 7, '4': 1, '5': 8, '10': 'present'},
    {'1': 'in_step', '3': 8, '4': 1, '5': 8, '10': 'inStep'},
  ],
};

/// Descriptor for `FirewallRule`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List firewallRuleDescriptor = $convert.base64Decode(
    'CgxGaXJld2FsbFJ1bGUSEgoEbmFtZRgBIAEoCVIEbmFtZRIfCgtpbnN0YW5jZV9pZBgCIAEoCV'
    'IKaW5zdGFuY2VJZBIbCglwb3J0X25hbWUYAyABKAlSCHBvcnROYW1lEhIKBHBvcnQYBCABKA1S'
    'BHBvcnQSGgoIcHJvdG9jb2wYBSABKAlSCHByb3RvY29sEhgKB21hbmFnZWQYBiABKAhSB21hbm'
    'FnZWQSGAoHcHJlc2VudBgHIAEoCFIHcHJlc2VudBIXCgdpbl9zdGVwGAggASgIUgZpblN0ZXA=');

@$core.Deprecated('Use listRulesRequestDescriptor instead')
const ListRulesRequest$json = {
  '1': 'ListRulesRequest',
};

/// Descriptor for `ListRulesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRulesRequestDescriptor =
    $convert.base64Decode('ChBMaXN0UnVsZXNSZXF1ZXN0');

@$core.Deprecated('Use listRulesResponseDescriptor instead')
const ListRulesResponse$json = {
  '1': 'ListRulesResponse',
  '2': [
    {
      '1': 'rules',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.FirewallRule',
      '10': 'rules'
    },
    {'1': 'status', '3': 2, '4': 1, '5': 9, '10': 'status'},
  ],
};

/// Descriptor for `ListRulesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRulesResponseDescriptor = $convert.base64Decode(
    'ChFMaXN0UnVsZXNSZXNwb25zZRItCgVydWxlcxgBIAMoCzIXLnlhZ3VyYS52MS5GaXJld2FsbF'
    'J1bGVSBXJ1bGVzEhYKBnN0YXR1cxgCIAEoCVIGc3RhdHVz');

@$core.Deprecated('Use reconcileRequestDescriptor instead')
const ReconcileRequest$json = {
  '1': 'ReconcileRequest',
};

/// Descriptor for `ReconcileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reconcileRequestDescriptor =
    $convert.base64Decode('ChBSZWNvbmNpbGVSZXF1ZXN0');

@$core.Deprecated('Use ruleChangeDescriptor instead')
const RuleChange$json = {
  '1': 'RuleChange',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'action', '3': 2, '4': 1, '5': 9, '10': 'action'},
    {'1': 'error', '3': 3, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `RuleChange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ruleChangeDescriptor = $convert.base64Decode(
    'CgpSdWxlQ2hhbmdlEhIKBG5hbWUYASABKAlSBG5hbWUSFgoGYWN0aW9uGAIgASgJUgZhY3Rpb2'
    '4SFAoFZXJyb3IYAyABKAlSBWVycm9y');

@$core.Deprecated('Use reconcileResponseDescriptor instead')
const ReconcileResponse$json = {
  '1': 'ReconcileResponse',
  '2': [
    {
      '1': 'changes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.RuleChange',
      '10': 'changes'
    },
  ],
};

/// Descriptor for `ReconcileResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reconcileResponseDescriptor = $convert.base64Decode(
    'ChFSZWNvbmNpbGVSZXNwb25zZRIvCgdjaGFuZ2VzGAEgAygLMhUueWFndXJhLnYxLlJ1bGVDaG'
    'FuZ2VSB2NoYW5nZXM=');
