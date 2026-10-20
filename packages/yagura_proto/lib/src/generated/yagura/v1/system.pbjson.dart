// This is a generated file - do not edit.
//
// Generated from yagura/v1/system.proto.

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

@$core.Deprecated('Use getInfoRequestDescriptor instead')
const GetInfoRequest$json = {
  '1': 'GetInfoRequest',
};

/// Descriptor for `GetInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getInfoRequestDescriptor =
    $convert.base64Decode('Cg5HZXRJbmZvUmVxdWVzdA==');

@$core.Deprecated('Use daemonInfoDescriptor instead')
const DaemonInfo$json = {
  '1': 'DaemonInfo',
  '2': [
    {'1': 'daemon_version', '3': 1, '4': 1, '5': 9, '10': 'daemonVersion'},
    {'1': 'api_version', '3': 2, '4': 1, '5': 9, '10': 'apiVersion'},
    {'1': 'api_versions', '3': 9, '4': 3, '5': 9, '10': 'apiVersions'},
    {'1': 'host_name', '3': 3, '4': 1, '5': 9, '10': 'hostName'},
    {'1': 'os', '3': 4, '4': 1, '5': 9, '10': 'os'},
    {'1': 'os_version', '3': 5, '4': 1, '5': 9, '10': 'osVersion'},
    {'1': 'data_dir', '3': 6, '4': 1, '5': 9, '10': 'dataDir'},
    {
      '1': 'started_at',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'startedAt'
    },
    {'1': 'dev_mode', '3': 8, '4': 1, '5': 8, '10': 'devMode'},
  ],
};

/// Descriptor for `DaemonInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List daemonInfoDescriptor = $convert.base64Decode(
    'CgpEYWVtb25JbmZvEiUKDmRhZW1vbl92ZXJzaW9uGAEgASgJUg1kYWVtb25WZXJzaW9uEh8KC2'
    'FwaV92ZXJzaW9uGAIgASgJUgphcGlWZXJzaW9uEiEKDGFwaV92ZXJzaW9ucxgJIAMoCVILYXBp'
    'VmVyc2lvbnMSGwoJaG9zdF9uYW1lGAMgASgJUghob3N0TmFtZRIOCgJvcxgEIAEoCVICb3MSHQ'
    'oKb3NfdmVyc2lvbhgFIAEoCVIJb3NWZXJzaW9uEhkKCGRhdGFfZGlyGAYgASgJUgdkYXRhRGly'
    'EjkKCnN0YXJ0ZWRfYXQYByABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUglzdGFydG'
    'VkQXQSGQoIZGV2X21vZGUYCCABKAhSB2Rldk1vZGU=');

@$core.Deprecated('Use getHealthRequestDescriptor instead')
const GetHealthRequest$json = {
  '1': 'GetHealthRequest',
};

/// Descriptor for `GetHealthRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getHealthRequestDescriptor =
    $convert.base64Decode('ChBHZXRIZWFsdGhSZXF1ZXN0');

@$core.Deprecated('Use daemonHealthDescriptor instead')
const DaemonHealth$json = {
  '1': 'DaemonHealth',
  '2': [
    {'1': 'database_ok', '3': 1, '4': 1, '5': 8, '10': 'databaseOk'},
    {'1': 'secret_store_ok', '3': 2, '4': 1, '5': 8, '10': 'secretStoreOk'},
    {'1': 'firewall_ok', '3': 3, '4': 1, '5': 8, '10': 'firewallOk'},
    {
      '1': 'data_volume_free_bytes',
      '3': 4,
      '4': 1,
      '5': 4,
      '10': 'dataVolumeFreeBytes'
    },
    {
      '1': 'running_instances',
      '3': 5,
      '4': 1,
      '5': 13,
      '10': 'runningInstances'
    },
    {
      '1': 'queued_operations',
      '3': 6,
      '4': 1,
      '5': 13,
      '10': 'queuedOperations'
    },
    {
      '1': 'leaked_hook_workers',
      '3': 7,
      '4': 1,
      '5': 13,
      '10': 'leakedHookWorkers'
    },
    {'1': 'hooks_degraded', '3': 8, '4': 1, '5': 8, '10': 'hooksDegraded'},
    {'1': 'plugins_ok', '3': 9, '4': 1, '5': 8, '10': 'pluginsOk'},
    {'1': 'not_built', '3': 10, '4': 3, '5': 9, '10': 'notBuilt'},
    {'1': 'admin_channel_ok', '3': 11, '4': 1, '5': 8, '10': 'adminChannelOk'},
    {
      '1': 'service_accounts_ok',
      '3': 12,
      '4': 1,
      '5': 8,
      '10': 'serviceAccountsOk'
    },
    {
      '1': 'server_cert_not_after',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'serverCertNotAfter'
    },
  ],
};

/// Descriptor for `DaemonHealth`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List daemonHealthDescriptor = $convert.base64Decode(
    'CgxEYWVtb25IZWFsdGgSHwoLZGF0YWJhc2Vfb2sYASABKAhSCmRhdGFiYXNlT2sSJgoPc2Vjcm'
    'V0X3N0b3JlX29rGAIgASgIUg1zZWNyZXRTdG9yZU9rEh8KC2ZpcmV3YWxsX29rGAMgASgIUgpm'
    'aXJld2FsbE9rEjMKFmRhdGFfdm9sdW1lX2ZyZWVfYnl0ZXMYBCABKARSE2RhdGFWb2x1bWVGcm'
    'VlQnl0ZXMSKwoRcnVubmluZ19pbnN0YW5jZXMYBSABKA1SEHJ1bm5pbmdJbnN0YW5jZXMSKwoR'
    'cXVldWVkX29wZXJhdGlvbnMYBiABKA1SEHF1ZXVlZE9wZXJhdGlvbnMSLgoTbGVha2VkX2hvb2'
    'tfd29ya2VycxgHIAEoDVIRbGVha2VkSG9va1dvcmtlcnMSJQoOaG9va3NfZGVncmFkZWQYCCAB'
    'KAhSDWhvb2tzRGVncmFkZWQSHQoKcGx1Z2luc19vaxgJIAEoCFIJcGx1Z2luc09rEhsKCW5vdF'
    '9idWlsdBgKIAMoCVIIbm90QnVpbHQSKAoQYWRtaW5fY2hhbm5lbF9vaxgLIAEoCFIOYWRtaW5D'
    'aGFubmVsT2sSLgoTc2VydmljZV9hY2NvdW50c19vaxgMIAEoCFIRc2VydmljZUFjY291bnRzT2'
    'sSTQoVc2VydmVyX2NlcnRfbm90X2FmdGVyGA0gASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVz'
    'dGFtcFISc2VydmVyQ2VydE5vdEFmdGVy');

@$core.Deprecated('Use listAuditRequestDescriptor instead')
const ListAuditRequest$json = {
  '1': 'ListAuditRequest',
  '2': [
    {'1': 'page_size', '3': 1, '4': 1, '5': 13, '10': 'pageSize'},
    {'1': 'page_token', '3': 2, '4': 1, '5': 9, '10': 'pageToken'},
  ],
};

/// Descriptor for `ListAuditRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listAuditRequestDescriptor = $convert.base64Decode(
    'ChBMaXN0QXVkaXRSZXF1ZXN0EhsKCXBhZ2Vfc2l6ZRgBIAEoDVIIcGFnZVNpemUSHQoKcGFnZV'
    '90b2tlbhgCIAEoCVIJcGFnZVRva2Vu');

@$core.Deprecated('Use auditEntryDescriptor instead')
const AuditEntry$json = {
  '1': 'AuditEntry',
  '2': [
    {
      '1': 'at',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'at'
    },
    {'1': 'device_id', '3': 2, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'remote_address', '3': 3, '4': 1, '5': 9, '10': 'remoteAddress'},
    {'1': 'method', '3': 4, '4': 1, '5': 9, '10': 'method'},
    {'1': 'target', '3': 5, '4': 1, '5': 9, '10': 'target'},
    {'1': 'result', '3': 6, '4': 1, '5': 9, '10': 'result'},
  ],
};

/// Descriptor for `AuditEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List auditEntryDescriptor = $convert.base64Decode(
    'CgpBdWRpdEVudHJ5EioKAmF0GAEgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFICYX'
    'QSGwoJZGV2aWNlX2lkGAIgASgJUghkZXZpY2VJZBIlCg5yZW1vdGVfYWRkcmVzcxgDIAEoCVIN'
    'cmVtb3RlQWRkcmVzcxIWCgZtZXRob2QYBCABKAlSBm1ldGhvZBIWCgZ0YXJnZXQYBSABKAlSBn'
    'RhcmdldBIWCgZyZXN1bHQYBiABKAlSBnJlc3VsdA==');

@$core.Deprecated('Use listAuditResponseDescriptor instead')
const ListAuditResponse$json = {
  '1': 'ListAuditResponse',
  '2': [
    {
      '1': 'entries',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.AuditEntry',
      '10': 'entries'
    },
    {'1': 'next_page_token', '3': 2, '4': 1, '5': 9, '10': 'nextPageToken'},
  ],
};

/// Descriptor for `ListAuditResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listAuditResponseDescriptor = $convert.base64Decode(
    'ChFMaXN0QXVkaXRSZXNwb25zZRIvCgdlbnRyaWVzGAEgAygLMhUueWFndXJhLnYxLkF1ZGl0RW'
    '50cnlSB2VudHJpZXMSJgoPbmV4dF9wYWdlX3Rva2VuGAIgASgJUg1uZXh0UGFnZVRva2Vu');
