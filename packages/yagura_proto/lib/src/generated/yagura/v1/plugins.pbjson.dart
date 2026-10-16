// This is a generated file - do not edit.
//
// Generated from yagura/v1/plugins.proto.

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

@$core.Deprecated('Use pluginStatusDescriptor instead')
const PluginStatus$json = {
  '1': 'PluginStatus',
  '2': [
    {'1': 'PLUGIN_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'PLUGIN_STATUS_LOADED', '2': 1},
    {'1': 'PLUGIN_STATUS_REJECTED', '2': 2},
  ],
};

/// Descriptor for `PluginStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pluginStatusDescriptor = $convert.base64Decode(
    'CgxQbHVnaW5TdGF0dXMSHQoZUExVR0lOX1NUQVRVU19VTlNQRUNJRklFRBAAEhgKFFBMVUdJTl'
    '9TVEFUVVNfTE9BREVEEAESGgoWUExVR0lOX1NUQVRVU19SRUpFQ1RFRBAC');

@$core.Deprecated('Use pluginProblemDescriptor instead')
const PluginProblem$json = {
  '1': 'PluginProblem',
  '2': [
    {'1': 'reason', '3': 1, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'path', '3': 2, '4': 1, '5': 9, '10': 'path'},
    {'1': 'file', '3': 3, '4': 1, '5': 9, '10': 'file'},
    {'1': 'line', '3': 4, '4': 1, '5': 13, '10': 'line'},
    {'1': 'message', '3': 5, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `PluginProblem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pluginProblemDescriptor = $convert.base64Decode(
    'Cg1QbHVnaW5Qcm9ibGVtEhYKBnJlYXNvbhgBIAEoCVIGcmVhc29uEhIKBHBhdGgYAiABKAlSBH'
    'BhdGgSEgoEZmlsZRgDIAEoCVIEZmlsZRISCgRsaW5lGAQgASgNUgRsaW5lEhgKB21lc3NhZ2UY'
    'BSABKAlSB21lc3NhZ2U=');

@$core.Deprecated('Use pluginSummaryDescriptor instead')
const PluginSummary$json = {
  '1': 'PluginSummary',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'version', '3': 3, '4': 1, '5': 9, '10': 'version'},
    {'1': 'manifest_version', '3': 4, '4': 1, '5': 13, '10': 'manifestVersion'},
    {
      '1': 'status',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.yagura.v1.PluginStatus',
      '10': 'status'
    },
    {'1': 'platforms', '3': 6, '4': 3, '5': 9, '10': 'platforms'},
    {
      '1': 'problems',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.PluginProblem',
      '10': 'problems'
    },
    {'1': 'has_hooks', '3': 8, '4': 1, '5': 8, '10': 'hasHooks'},
    {'1': 'supports_mods', '3': 9, '4': 1, '5': 8, '10': 'supportsMods'},
    {'1': 'rcon_protocol', '3': 10, '4': 1, '5': 9, '10': 'rconProtocol'},
    {'1': 'steam_login', '3': 11, '4': 1, '5': 9, '10': 'steamLogin'},
  ],
};

/// Descriptor for `PluginSummary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pluginSummaryDescriptor = $convert.base64Decode(
    'Cg1QbHVnaW5TdW1tYXJ5Eg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEhgKB3'
    'ZlcnNpb24YAyABKAlSB3ZlcnNpb24SKQoQbWFuaWZlc3RfdmVyc2lvbhgEIAEoDVIPbWFuaWZl'
    'c3RWZXJzaW9uEi8KBnN0YXR1cxgFIAEoDjIXLnlhZ3VyYS52MS5QbHVnaW5TdGF0dXNSBnN0YX'
    'R1cxIcCglwbGF0Zm9ybXMYBiADKAlSCXBsYXRmb3JtcxI0Cghwcm9ibGVtcxgHIAMoCzIYLnlh'
    'Z3VyYS52MS5QbHVnaW5Qcm9ibGVtUghwcm9ibGVtcxIbCgloYXNfaG9va3MYCCABKAhSCGhhc0'
    'hvb2tzEiMKDXN1cHBvcnRzX21vZHMYCSABKAhSDHN1cHBvcnRzTW9kcxIjCg1yY29uX3Byb3Rv'
    'Y29sGAogASgJUgxyY29uUHJvdG9jb2wSHwoLc3RlYW1fbG9naW4YCyABKAlSCnN0ZWFtTG9naW'
    '4=');

@$core.Deprecated('Use listPluginsRequestDescriptor instead')
const ListPluginsRequest$json = {
  '1': 'ListPluginsRequest',
};

/// Descriptor for `ListPluginsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPluginsRequestDescriptor =
    $convert.base64Decode('ChJMaXN0UGx1Z2luc1JlcXVlc3Q=');

@$core.Deprecated('Use listPluginsResponseDescriptor instead')
const ListPluginsResponse$json = {
  '1': 'ListPluginsResponse',
  '2': [
    {
      '1': 'plugins',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.PluginSummary',
      '10': 'plugins'
    },
  ],
};

/// Descriptor for `ListPluginsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPluginsResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0UGx1Z2luc1Jlc3BvbnNlEjIKB3BsdWdpbnMYASADKAsyGC55YWd1cmEudjEuUGx1Z2'
    'luU3VtbWFyeVIHcGx1Z2lucw==');

@$core.Deprecated('Use getPluginRequestDescriptor instead')
const GetPluginRequest$json = {
  '1': 'GetPluginRequest',
  '2': [
    {'1': 'plugin_id', '3': 1, '4': 1, '5': 9, '10': 'pluginId'},
  ],
};

/// Descriptor for `GetPluginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPluginRequestDescriptor = $convert.base64Decode(
    'ChBHZXRQbHVnaW5SZXF1ZXN0EhsKCXBsdWdpbl9pZBgBIAEoCVIIcGx1Z2luSWQ=');

@$core.Deprecated('Use pluginDetailDescriptor instead')
const PluginDetail$json = {
  '1': 'PluginDetail',
  '2': [
    {
      '1': 'summary',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.PluginSummary',
      '10': 'summary'
    },
    {
      '1': 'settings_schema',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.JsonDocument',
      '10': 'settingsSchema'
    },
    {
      '1': 'default_ports',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Port',
      '10': 'defaultPorts'
    },
    {'1': 'mod_roles', '3': 4, '4': 3, '5': 9, '10': 'modRoles'},
    {'1': 'log_sources', '3': 5, '4': 3, '5': 9, '10': 'logSources'},
  ],
};

/// Descriptor for `PluginDetail`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pluginDetailDescriptor = $convert.base64Decode(
    'CgxQbHVnaW5EZXRhaWwSMgoHc3VtbWFyeRgBIAEoCzIYLnlhZ3VyYS52MS5QbHVnaW5TdW1tYX'
    'J5UgdzdW1tYXJ5EkAKD3NldHRpbmdzX3NjaGVtYRgCIAEoCzIXLnlhZ3VyYS52MS5Kc29uRG9j'
    'dW1lbnRSDnNldHRpbmdzU2NoZW1hEjQKDWRlZmF1bHRfcG9ydHMYAyADKAsyDy55YWd1cmEudj'
    'EuUG9ydFIMZGVmYXVsdFBvcnRzEhsKCW1vZF9yb2xlcxgEIAMoCVIIbW9kUm9sZXMSHwoLbG9n'
    'X3NvdXJjZXMYBSADKAlSCmxvZ1NvdXJjZXM=');

@$core.Deprecated('Use reloadPluginsRequestDescriptor instead')
const ReloadPluginsRequest$json = {
  '1': 'ReloadPluginsRequest',
  '2': [
    {'1': 'plugin_ids', '3': 1, '4': 3, '5': 9, '10': 'pluginIds'},
  ],
};

/// Descriptor for `ReloadPluginsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reloadPluginsRequestDescriptor = $convert.base64Decode(
    'ChRSZWxvYWRQbHVnaW5zUmVxdWVzdBIdCgpwbHVnaW5faWRzGAEgAygJUglwbHVnaW5JZHM=');

@$core.Deprecated('Use pluginReloadResultDescriptor instead')
const PluginReloadResult$json = {
  '1': 'PluginReloadResult',
  '2': [
    {'1': 'plugin_id', '3': 1, '4': 1, '5': 9, '10': 'pluginId'},
    {'1': 'outcome', '3': 2, '4': 1, '5': 9, '10': 'outcome'},
    {
      '1': 'problems',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.PluginProblem',
      '10': 'problems'
    },
  ],
};

/// Descriptor for `PluginReloadResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pluginReloadResultDescriptor = $convert.base64Decode(
    'ChJQbHVnaW5SZWxvYWRSZXN1bHQSGwoJcGx1Z2luX2lkGAEgASgJUghwbHVnaW5JZBIYCgdvdX'
    'Rjb21lGAIgASgJUgdvdXRjb21lEjQKCHByb2JsZW1zGAMgAygLMhgueWFndXJhLnYxLlBsdWdp'
    'blByb2JsZW1SCHByb2JsZW1z');

@$core.Deprecated('Use reloadPluginsResponseDescriptor instead')
const ReloadPluginsResponse$json = {
  '1': 'ReloadPluginsResponse',
  '2': [
    {
      '1': 'results',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.PluginReloadResult',
      '10': 'results'
    },
  ],
};

/// Descriptor for `ReloadPluginsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reloadPluginsResponseDescriptor = $convert.base64Decode(
    'ChVSZWxvYWRQbHVnaW5zUmVzcG9uc2USNwoHcmVzdWx0cxgBIAMoCzIdLnlhZ3VyYS52MS5QbH'
    'VnaW5SZWxvYWRSZXN1bHRSB3Jlc3VsdHM=');
