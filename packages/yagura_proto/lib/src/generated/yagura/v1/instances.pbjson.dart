// This is a generated file - do not edit.
//
// Generated from yagura/v1/instances.proto.

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

@$core.Deprecated('Use instanceStateDescriptor instead')
const InstanceState$json = {
  '1': 'InstanceState',
  '2': [
    {'1': 'INSTANCE_STATE_UNSPECIFIED', '2': 0},
    {'1': 'INSTANCE_STATE_NOT_INSTALLED', '2': 1},
    {'1': 'INSTANCE_STATE_INSTALLING', '2': 2},
    {'1': 'INSTANCE_STATE_STOPPED', '2': 3},
    {'1': 'INSTANCE_STATE_STARTING', '2': 4},
    {'1': 'INSTANCE_STATE_RUNNING', '2': 5},
    {'1': 'INSTANCE_STATE_STOPPING', '2': 6},
    {'1': 'INSTANCE_STATE_UPDATING', '2': 7},
    {'1': 'INSTANCE_STATE_ERROR', '2': 8},
  ],
};

/// Descriptor for `InstanceState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List instanceStateDescriptor = $convert.base64Decode(
    'Cg1JbnN0YW5jZVN0YXRlEh4KGklOU1RBTkNFX1NUQVRFX1VOU1BFQ0lGSUVEEAASIAocSU5TVE'
    'FOQ0VfU1RBVEVfTk9UX0lOU1RBTExFRBABEh0KGUlOU1RBTkNFX1NUQVRFX0lOU1RBTExJTkcQ'
    'AhIaChZJTlNUQU5DRV9TVEFURV9TVE9QUEVEEAMSGwoXSU5TVEFOQ0VfU1RBVEVfU1RBUlRJTk'
    'cQBBIaChZJTlNUQU5DRV9TVEFURV9SVU5OSU5HEAUSGwoXSU5TVEFOQ0VfU1RBVEVfU1RPUFBJ'
    'TkcQBhIbChdJTlNUQU5DRV9TVEFURV9VUERBVElORxAHEhgKFElOU1RBTkNFX1NUQVRFX0VSUk'
    '9SEAg=');

@$core.Deprecated('Use healthDescriptor instead')
const Health$json = {
  '1': 'Health',
  '2': [
    {'1': 'HEALTH_UNSPECIFIED', '2': 0},
    {'1': 'HEALTH_OK', '2': 1},
    {'1': 'HEALTH_UNKNOWN', '2': 2},
    {'1': 'HEALTH_FAILING', '2': 3},
  ],
};

/// Descriptor for `Health`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List healthDescriptor = $convert.base64Decode(
    'CgZIZWFsdGgSFgoSSEVBTFRIX1VOU1BFQ0lGSUVEEAASDQoJSEVBTFRIX09LEAESEgoOSEVBTF'
    'RIX1VOS05PV04QAhISCg5IRUFMVEhfRkFJTElORxAD');

@$core.Deprecated('Use instanceDescriptor instead')
const Instance$json = {
  '1': 'Instance',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'plugin_id', '3': 3, '4': 1, '5': 9, '10': 'pluginId'},
    {'1': 'plugin_version', '3': 4, '4': 1, '5': 9, '10': 'pluginVersion'},
    {'1': 'directory', '3': 5, '4': 1, '5': 9, '10': 'directory'},
    {
      '1': 'state',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.yagura.v1.InstanceState',
      '10': 'state'
    },
    {'1': 'state_reason', '3': 7, '4': 1, '5': 9, '10': 'stateReason'},
    {
      '1': 'health',
      '3': 8,
      '4': 1,
      '5': 14,
      '6': '.yagura.v1.Health',
      '10': 'health'
    },
    {
      '1': 'ports',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Port',
      '10': 'ports'
    },
    {
      '1': 'settings',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.JsonDocument',
      '10': 'settings'
    },
    {'1': 'steam_account_id', '3': 11, '4': 1, '5': 9, '10': 'steamAccountId'},
    {'1': 'restart_policy', '3': 12, '4': 1, '5': 9, '10': 'restartPolicy'},
    {'1': 'firewall_status', '3': 13, '4': 1, '5': 9, '10': 'firewallStatus'},
    {
      '1': 'active_operation_id',
      '3': 14,
      '4': 1,
      '5': 9,
      '10': 'activeOperationId'
    },
    {
      '1': 'queued_operations',
      '3': 15,
      '4': 1,
      '5': 13,
      '10': 'queuedOperations'
    },
    {
      '1': 'created_at',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {
      '1': 'state_changed_at',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'stateChangedAt'
    },
    {'1': 'pid', '3': 18, '4': 1, '5': 13, '10': 'pid'},
    {'1': 'revision', '3': 19, '4': 1, '5': 4, '10': 'revision'},
    {'1': 'restart_required', '3': 20, '4': 1, '5': 8, '10': 'restartRequired'},
    {'1': 'autostart', '3': 21, '4': 1, '5': 8, '10': 'autostart'},
    {'1': 'settings_invalid', '3': 22, '4': 1, '5': 8, '10': 'settingsInvalid'},
    {
      '1': 'mods_update_available',
      '3': 23,
      '4': 1,
      '5': 13,
      '10': 'modsUpdateAvailable'
    },
    {'1': 'settings_omitted', '3': 24, '4': 1, '5': 8, '10': 'settingsOmitted'},
  ],
};

/// Descriptor for `Instance`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List instanceDescriptor = $convert.base64Decode(
    'CghJbnN0YW5jZRIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIbCglwbHVnaW'
    '5faWQYAyABKAlSCHBsdWdpbklkEiUKDnBsdWdpbl92ZXJzaW9uGAQgASgJUg1wbHVnaW5WZXJz'
    'aW9uEhwKCWRpcmVjdG9yeRgFIAEoCVIJZGlyZWN0b3J5Ei4KBXN0YXRlGAYgASgOMhgueWFndX'
    'JhLnYxLkluc3RhbmNlU3RhdGVSBXN0YXRlEiEKDHN0YXRlX3JlYXNvbhgHIAEoCVILc3RhdGVS'
    'ZWFzb24SKQoGaGVhbHRoGAggASgOMhEueWFndXJhLnYxLkhlYWx0aFIGaGVhbHRoEiUKBXBvcn'
    'RzGAkgAygLMg8ueWFndXJhLnYxLlBvcnRSBXBvcnRzEjMKCHNldHRpbmdzGAogASgLMhcueWFn'
    'dXJhLnYxLkpzb25Eb2N1bWVudFIIc2V0dGluZ3MSKAoQc3RlYW1fYWNjb3VudF9pZBgLIAEoCV'
    'IOc3RlYW1BY2NvdW50SWQSJQoOcmVzdGFydF9wb2xpY3kYDCABKAlSDXJlc3RhcnRQb2xpY3kS'
    'JwoPZmlyZXdhbGxfc3RhdHVzGA0gASgJUg5maXJld2FsbFN0YXR1cxIuChNhY3RpdmVfb3Blcm'
    'F0aW9uX2lkGA4gASgJUhFhY3RpdmVPcGVyYXRpb25JZBIrChFxdWV1ZWRfb3BlcmF0aW9ucxgP'
    'IAEoDVIQcXVldWVkT3BlcmF0aW9ucxI5CgpjcmVhdGVkX2F0GBAgASgLMhouZ29vZ2xlLnByb3'
    'RvYnVmLlRpbWVzdGFtcFIJY3JlYXRlZEF0EkQKEHN0YXRlX2NoYW5nZWRfYXQYESABKAsyGi5n'
    'b29nbGUucHJvdG9idWYuVGltZXN0YW1wUg5zdGF0ZUNoYW5nZWRBdBIQCgNwaWQYEiABKA1SA3'
    'BpZBIaCghyZXZpc2lvbhgTIAEoBFIIcmV2aXNpb24SKQoQcmVzdGFydF9yZXF1aXJlZBgUIAEo'
    'CFIPcmVzdGFydFJlcXVpcmVkEhwKCWF1dG9zdGFydBgVIAEoCFIJYXV0b3N0YXJ0EikKEHNldH'
    'RpbmdzX2ludmFsaWQYFiABKAhSD3NldHRpbmdzSW52YWxpZBIyChVtb2RzX3VwZGF0ZV9hdmFp'
    'bGFibGUYFyABKA1SE21vZHNVcGRhdGVBdmFpbGFibGUSKQoQc2V0dGluZ3Nfb21pdHRlZBgYIA'
    'EoCFIPc2V0dGluZ3NPbWl0dGVk');

@$core.Deprecated('Use listInstancesRequestDescriptor instead')
const ListInstancesRequest$json = {
  '1': 'ListInstancesRequest',
};

/// Descriptor for `ListInstancesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listInstancesRequestDescriptor =
    $convert.base64Decode('ChRMaXN0SW5zdGFuY2VzUmVxdWVzdA==');

@$core.Deprecated('Use listInstancesResponseDescriptor instead')
const ListInstancesResponse$json = {
  '1': 'ListInstancesResponse',
  '2': [
    {
      '1': 'instances',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Instance',
      '10': 'instances'
    },
  ],
};

/// Descriptor for `ListInstancesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listInstancesResponseDescriptor = $convert.base64Decode(
    'ChVMaXN0SW5zdGFuY2VzUmVzcG9uc2USMQoJaW5zdGFuY2VzGAEgAygLMhMueWFndXJhLnYxLk'
    'luc3RhbmNlUglpbnN0YW5jZXM=');

@$core.Deprecated('Use getInstanceRequestDescriptor instead')
const GetInstanceRequest$json = {
  '1': 'GetInstanceRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
  ],
};

/// Descriptor for `GetInstanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getInstanceRequestDescriptor = $convert.base64Decode(
    'ChJHZXRJbnN0YW5jZVJlcXVlc3QSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSWQ=');

@$core.Deprecated('Use watchInstancesRequestDescriptor instead')
const WatchInstancesRequest$json = {
  '1': 'WatchInstancesRequest',
};

/// Descriptor for `WatchInstancesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchInstancesRequestDescriptor =
    $convert.base64Decode('ChVXYXRjaEluc3RhbmNlc1JlcXVlc3Q=');

@$core.Deprecated('Use instanceEventDescriptor instead')
const InstanceEvent$json = {
  '1': 'InstanceEvent',
  '2': [
    {
      '1': 'snapshot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.InstanceSnapshot',
      '9': 0,
      '10': 'snapshot'
    },
    {
      '1': 'changed',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Instance',
      '9': 0,
      '10': 'changed'
    },
    {
      '1': 'removed_instance_id',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'removedInstanceId'
    },
    {
      '1': 'resync_required',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.ResyncRequired',
      '9': 0,
      '10': 'resyncRequired'
    },
    {
      '1': 'notice',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.InstanceNotice',
      '9': 0,
      '10': 'notice'
    },
  ],
  '8': [
    {'1': 'event'},
  ],
};

/// Descriptor for `InstanceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List instanceEventDescriptor = $convert.base64Decode(
    'Cg1JbnN0YW5jZUV2ZW50EjkKCHNuYXBzaG90GAEgASgLMhsueWFndXJhLnYxLkluc3RhbmNlU2'
    '5hcHNob3RIAFIIc25hcHNob3QSLwoHY2hhbmdlZBgCIAEoCzITLnlhZ3VyYS52MS5JbnN0YW5j'
    'ZUgAUgdjaGFuZ2VkEjAKE3JlbW92ZWRfaW5zdGFuY2VfaWQYAyABKAlIAFIRcmVtb3ZlZEluc3'
    'RhbmNlSWQSRAoPcmVzeW5jX3JlcXVpcmVkGAQgASgLMhkueWFndXJhLnYxLlJlc3luY1JlcXVp'
    'cmVkSABSDnJlc3luY1JlcXVpcmVkEjMKBm5vdGljZRgFIAEoCzIZLnlhZ3VyYS52MS5JbnN0YW'
    '5jZU5vdGljZUgAUgZub3RpY2VCBwoFZXZlbnQ=');

@$core.Deprecated('Use instanceSnapshotDescriptor instead')
const InstanceSnapshot$json = {
  '1': 'InstanceSnapshot',
  '2': [
    {
      '1': 'instances',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Instance',
      '10': 'instances'
    },
  ],
};

/// Descriptor for `InstanceSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List instanceSnapshotDescriptor = $convert.base64Decode(
    'ChBJbnN0YW5jZVNuYXBzaG90EjEKCWluc3RhbmNlcxgBIAMoCzITLnlhZ3VyYS52MS5JbnN0YW'
    '5jZVIJaW5zdGFuY2Vz');

@$core.Deprecated('Use resyncRequiredDescriptor instead')
const ResyncRequired$json = {
  '1': 'ResyncRequired',
};

/// Descriptor for `ResyncRequired`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resyncRequiredDescriptor =
    $convert.base64Decode('Cg5SZXN5bmNSZXF1aXJlZA==');

@$core.Deprecated('Use instanceNoticeDescriptor instead')
const InstanceNotice$json = {
  '1': 'InstanceNotice',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'kind', '3': 2, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'message', '3': 3, '4': 1, '5': 9, '10': 'message'},
    {'1': 'exit_code', '3': 4, '4': 1, '5': 5, '10': 'exitCode'},
    {'1': 'last_log_lines', '3': 5, '4': 3, '5': 9, '10': 'lastLogLines'},
    {
      '1': 'at',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'at'
    },
  ],
};

/// Descriptor for `InstanceNotice`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List instanceNoticeDescriptor = $convert.base64Decode(
    'Cg5JbnN0YW5jZU5vdGljZRIfCgtpbnN0YW5jZV9pZBgBIAEoCVIKaW5zdGFuY2VJZBISCgRraW'
    '5kGAIgASgJUgRraW5kEhgKB21lc3NhZ2UYAyABKAlSB21lc3NhZ2USGwoJZXhpdF9jb2RlGAQg'
    'ASgFUghleGl0Q29kZRIkCg5sYXN0X2xvZ19saW5lcxgFIAMoCVIMbGFzdExvZ0xpbmVzEioKAm'
    'F0GAYgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFICYXQ=');

@$core.Deprecated('Use createInstanceRequestDescriptor instead')
const CreateInstanceRequest$json = {
  '1': 'CreateInstanceRequest',
  '2': [
    {'1': 'plugin_id', '3': 1, '4': 1, '5': 9, '10': 'pluginId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'directory', '3': 3, '4': 1, '5': 9, '10': 'directory'},
    {
      '1': 'settings',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.JsonDocument',
      '10': 'settings'
    },
    {
      '1': 'ports',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Port',
      '10': 'ports'
    },
    {'1': 'steam_account_id', '3': 6, '4': 1, '5': 9, '10': 'steamAccountId'},
  ],
};

/// Descriptor for `CreateInstanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createInstanceRequestDescriptor = $convert.base64Decode(
    'ChVDcmVhdGVJbnN0YW5jZVJlcXVlc3QSGwoJcGx1Z2luX2lkGAEgASgJUghwbHVnaW5JZBISCg'
    'RuYW1lGAIgASgJUgRuYW1lEhwKCWRpcmVjdG9yeRgDIAEoCVIJZGlyZWN0b3J5EjMKCHNldHRp'
    'bmdzGAQgASgLMhcueWFndXJhLnYxLkpzb25Eb2N1bWVudFIIc2V0dGluZ3MSJQoFcG9ydHMYBS'
    'ADKAsyDy55YWd1cmEudjEuUG9ydFIFcG9ydHMSKAoQc3RlYW1fYWNjb3VudF9pZBgGIAEoCVIO'
    'c3RlYW1BY2NvdW50SWQ=');

@$core.Deprecated('Use updateSettingsRequestDescriptor instead')
const UpdateSettingsRequest$json = {
  '1': 'UpdateSettingsRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {
      '1': 'expected_revision',
      '3': 6,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {
      '1': 'settings',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.JsonDocument',
      '10': 'settings'
    },
    {
      '1': 'ports',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Port',
      '10': 'ports'
    },
    {
      '1': 'restart_policy',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'restartPolicy',
      '17': true
    },
    {
      '1': 'steam_account_id',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'steamAccountId',
      '17': true
    },
    {
      '1': 'autostart',
      '3': 7,
      '4': 1,
      '5': 8,
      '9': 2,
      '10': 'autostart',
      '17': true
    },
  ],
  '8': [
    {'1': '_restart_policy'},
    {'1': '_steam_account_id'},
    {'1': '_autostart'},
  ],
};

/// Descriptor for `UpdateSettingsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateSettingsRequestDescriptor = $convert.base64Decode(
    'ChVVcGRhdGVTZXR0aW5nc1JlcXVlc3QSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSW'
    'QSKwoRZXhwZWN0ZWRfcmV2aXNpb24YBiABKARSEGV4cGVjdGVkUmV2aXNpb24SMwoIc2V0dGlu'
    'Z3MYAiABKAsyFy55YWd1cmEudjEuSnNvbkRvY3VtZW50UghzZXR0aW5ncxIlCgVwb3J0cxgDIA'
    'MoCzIPLnlhZ3VyYS52MS5Qb3J0UgVwb3J0cxIqCg5yZXN0YXJ0X3BvbGljeRgEIAEoCUgAUg1y'
    'ZXN0YXJ0UG9saWN5iAEBEi0KEHN0ZWFtX2FjY291bnRfaWQYBSABKAlIAVIOc3RlYW1BY2NvdW'
    '50SWSIAQESIQoJYXV0b3N0YXJ0GAcgASgISAJSCWF1dG9zdGFydIgBAUIRCg9fcmVzdGFydF9w'
    'b2xpY3lCEwoRX3N0ZWFtX2FjY291bnRfaWRCDAoKX2F1dG9zdGFydA==');

@$core.Deprecated('Use setSecretRequestDescriptor instead')
const SetSecretRequest$json = {
  '1': 'SetSecretRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {
      '1': 'expected_revision',
      '3': 4,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {'1': 'key', '3': 2, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 3, '4': 1, '5': 9, '10': 'value'},
  ],
};

/// Descriptor for `SetSecretRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setSecretRequestDescriptor = $convert.base64Decode(
    'ChBTZXRTZWNyZXRSZXF1ZXN0Eh8KC2luc3RhbmNlX2lkGAEgASgJUgppbnN0YW5jZUlkEisKEW'
    'V4cGVjdGVkX3JldmlzaW9uGAQgASgEUhBleHBlY3RlZFJldmlzaW9uEhAKA2tleRgCIAEoCVID'
    'a2V5EhQKBXZhbHVlGAMgASgJUgV2YWx1ZQ==');

@$core.Deprecated('Use deleteSecretRequestDescriptor instead')
const DeleteSecretRequest$json = {
  '1': 'DeleteSecretRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {
      '1': 'expected_revision',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {'1': 'key', '3': 2, '4': 1, '5': 9, '10': 'key'},
  ],
};

/// Descriptor for `DeleteSecretRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteSecretRequestDescriptor = $convert.base64Decode(
    'ChNEZWxldGVTZWNyZXRSZXF1ZXN0Eh8KC2luc3RhbmNlX2lkGAEgASgJUgppbnN0YW5jZUlkEi'
    'sKEWV4cGVjdGVkX3JldmlzaW9uGAMgASgEUhBleHBlY3RlZFJldmlzaW9uEhAKA2tleRgCIAEo'
    'CVIDa2V5');

@$core.Deprecated('Use deleteInstanceRequestDescriptor instead')
const DeleteInstanceRequest$json = {
  '1': 'DeleteInstanceRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {
      '1': 'expected_revision',
      '3': 4,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {'1': 'delete_files', '3': 2, '4': 1, '5': 8, '10': 'deleteFiles'},
    {'1': 'confirm_name', '3': 3, '4': 1, '5': 9, '10': 'confirmName'},
  ],
};

/// Descriptor for `DeleteInstanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteInstanceRequestDescriptor = $convert.base64Decode(
    'ChVEZWxldGVJbnN0YW5jZVJlcXVlc3QSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSW'
    'QSKwoRZXhwZWN0ZWRfcmV2aXNpb24YBCABKARSEGV4cGVjdGVkUmV2aXNpb24SIQoMZGVsZXRl'
    'X2ZpbGVzGAIgASgIUgtkZWxldGVGaWxlcxIhCgxjb25maXJtX25hbWUYAyABKAlSC2NvbmZpcm'
    '1OYW1l');

@$core.Deprecated('Use importInstanceRequestDescriptor instead')
const ImportInstanceRequest$json = {
  '1': 'ImportInstanceRequest',
  '2': [
    {'1': 'directory', '3': 1, '4': 1, '5': 9, '10': 'directory'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `ImportInstanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List importInstanceRequestDescriptor = $convert.base64Decode(
    'ChVJbXBvcnRJbnN0YW5jZVJlcXVlc3QSHAoJZGlyZWN0b3J5GAEgASgJUglkaXJlY3RvcnkSEg'
    'oEbmFtZRgCIAEoCVIEbmFtZQ==');

@$core.Deprecated('Use importInstanceResponseDescriptor instead')
const ImportInstanceResponse$json = {
  '1': 'ImportInstanceResponse',
  '2': [
    {
      '1': 'instance',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.yagura.v1.Instance',
      '10': 'instance'
    },
    {'1': 'secrets_to_set', '3': 2, '4': 3, '5': 9, '10': 'secretsToSet'},
  ],
};

/// Descriptor for `ImportInstanceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List importInstanceResponseDescriptor = $convert.base64Decode(
    'ChZJbXBvcnRJbnN0YW5jZVJlc3BvbnNlEi8KCGluc3RhbmNlGAEgASgLMhMueWFndXJhLnYxLk'
    'luc3RhbmNlUghpbnN0YW5jZRIkCg5zZWNyZXRzX3RvX3NldBgCIAMoCVIMc2VjcmV0c1RvU2V0');

@$core.Deprecated('Use exportInstanceRequestDescriptor instead')
const ExportInstanceRequest$json = {
  '1': 'ExportInstanceRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
  ],
};

/// Descriptor for `ExportInstanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List exportInstanceRequestDescriptor = $convert.base64Decode(
    'ChVFeHBvcnRJbnN0YW5jZVJlcXVlc3QSHwoLaW5zdGFuY2VfaWQYASABKAlSCmluc3RhbmNlSW'
    'Q=');

@$core.Deprecated('Use exportInstanceResponseDescriptor instead')
const ExportInstanceResponse$json = {
  '1': 'ExportInstanceResponse',
  '2': [
    {'1': 'instance_json', '3': 1, '4': 1, '5': 9, '10': 'instanceJson'},
  ],
};

/// Descriptor for `ExportInstanceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List exportInstanceResponseDescriptor =
    $convert.base64Decode(
        'ChZFeHBvcnRJbnN0YW5jZVJlc3BvbnNlEiMKDWluc3RhbmNlX2pzb24YASABKAlSDGluc3Rhbm'
        'NlSnNvbg==');

@$core.Deprecated('Use lifecycleRequestDescriptor instead')
const LifecycleRequest$json = {
  '1': 'LifecycleRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'validate_files', '3': 2, '4': 1, '5': 8, '10': 'validateFiles'},
    {'1': 'force', '3': 3, '4': 1, '5': 8, '10': 'force'},
    {'1': 'skip_snapshot', '3': 4, '4': 1, '5': 8, '10': 'skipSnapshot'},
  ],
};

/// Descriptor for `LifecycleRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lifecycleRequestDescriptor = $convert.base64Decode(
    'ChBMaWZlY3ljbGVSZXF1ZXN0Eh8KC2luc3RhbmNlX2lkGAEgASgJUgppbnN0YW5jZUlkEiUKDn'
    'ZhbGlkYXRlX2ZpbGVzGAIgASgIUg12YWxpZGF0ZUZpbGVzEhQKBWZvcmNlGAMgASgIUgVmb3Jj'
    'ZRIjCg1za2lwX3NuYXBzaG90GAQgASgIUgxza2lwU25hcHNob3Q=');

@$core.Deprecated('Use snapshotDescriptor instead')
const Snapshot$json = {
  '1': 'Snapshot',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'instance_id', '3': 5, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'instance_name', '3': 6, '4': 1, '5': 9, '10': 'instanceName'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
    {
      '1': 'created_at',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {'1': 'size_bytes', '3': 4, '4': 1, '5': 4, '10': 'sizeBytes'},
  ],
};

/// Descriptor for `Snapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List snapshotDescriptor = $convert.base64Decode(
    'CghTbmFwc2hvdBIOCgJpZBgBIAEoCVICaWQSHwoLaW5zdGFuY2VfaWQYBSABKAlSCmluc3Rhbm'
    'NlSWQSIwoNaW5zdGFuY2VfbmFtZRgGIAEoCVIMaW5zdGFuY2VOYW1lEhYKBnJlYXNvbhgCIAEo'
    'CVIGcmVhc29uEjkKCmNyZWF0ZWRfYXQYAyABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW'
    '1wUgljcmVhdGVkQXQSHQoKc2l6ZV9ieXRlcxgEIAEoBFIJc2l6ZUJ5dGVz');

@$core.Deprecated('Use listSnapshotsResponseDescriptor instead')
const ListSnapshotsResponse$json = {
  '1': 'ListSnapshotsResponse',
  '2': [
    {
      '1': 'snapshots',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Snapshot',
      '10': 'snapshots'
    },
  ],
};

/// Descriptor for `ListSnapshotsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSnapshotsResponseDescriptor = $convert.base64Decode(
    'ChVMaXN0U25hcHNob3RzUmVzcG9uc2USMQoJc25hcHNob3RzGAEgAygLMhMueWFndXJhLnYxLl'
    'NuYXBzaG90UglzbmFwc2hvdHM=');

@$core.Deprecated('Use restoreSnapshotRequestDescriptor instead')
const RestoreSnapshotRequest$json = {
  '1': 'RestoreSnapshotRequest',
  '2': [
    {'1': 'instance_id', '3': 1, '4': 1, '5': 9, '10': 'instanceId'},
    {'1': 'snapshot_id', '3': 2, '4': 1, '5': 9, '10': 'snapshotId'},
    {
      '1': 'expected_revision',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
  ],
};

/// Descriptor for `RestoreSnapshotRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreSnapshotRequestDescriptor = $convert.base64Decode(
    'ChZSZXN0b3JlU25hcHNob3RSZXF1ZXN0Eh8KC2luc3RhbmNlX2lkGAEgASgJUgppbnN0YW5jZU'
    'lkEh8KC3NuYXBzaG90X2lkGAIgASgJUgpzbmFwc2hvdElkEisKEWV4cGVjdGVkX3JldmlzaW9u'
    'GAMgASgEUhBleHBlY3RlZFJldmlzaW9u');

@$core.Deprecated('Use listOrphanSnapshotsRequestDescriptor instead')
const ListOrphanSnapshotsRequest$json = {
  '1': 'ListOrphanSnapshotsRequest',
};

/// Descriptor for `ListOrphanSnapshotsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listOrphanSnapshotsRequestDescriptor =
    $convert.base64Decode('ChpMaXN0T3JwaGFuU25hcHNob3RzUmVxdWVzdA==');
