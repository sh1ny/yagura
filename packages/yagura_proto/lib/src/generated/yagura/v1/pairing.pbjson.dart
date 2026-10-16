// This is a generated file - do not edit.
//
// Generated from yagura/v1/pairing.proto.

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

@$core.Deprecated('Use pairingInfoRequestDescriptor instead')
const PairingInfoRequest$json = {
  '1': 'PairingInfoRequest',
};

/// Descriptor for `PairingInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairingInfoRequestDescriptor =
    $convert.base64Decode('ChJQYWlyaW5nSW5mb1JlcXVlc3Q=');

@$core.Deprecated('Use pairingInfoDescriptor instead')
const PairingInfo$json = {
  '1': 'PairingInfo',
  '2': [
    {'1': 'daemon_name', '3': 1, '4': 1, '5': 9, '10': 'daemonName'},
    {
      '1': 'ca_fingerprint_sha256',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'caFingerprintSha256'
    },
    {'1': 'api_version', '3': 3, '4': 1, '5': 9, '10': 'apiVersion'},
    {
      '1': 'ca_certificate_der',
      '3': 4,
      '4': 1,
      '5': 12,
      '10': 'caCertificateDer'
    },
    {'1': 'tls_authority', '3': 5, '4': 1, '5': 9, '10': 'tlsAuthority'},
  ],
};

/// Descriptor for `PairingInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairingInfoDescriptor = $convert.base64Decode(
    'CgtQYWlyaW5nSW5mbxIfCgtkYWVtb25fbmFtZRgBIAEoCVIKZGFlbW9uTmFtZRIyChVjYV9maW'
    '5nZXJwcmludF9zaGEyNTYYAiABKAlSE2NhRmluZ2VycHJpbnRTaGEyNTYSHwoLYXBpX3ZlcnNp'
    'b24YAyABKAlSCmFwaVZlcnNpb24SLAoSY2FfY2VydGlmaWNhdGVfZGVyGAQgASgMUhBjYUNlcn'
    'RpZmljYXRlRGVyEiMKDXRsc19hdXRob3JpdHkYBSABKAlSDHRsc0F1dGhvcml0eQ==');

@$core.Deprecated('Use enrollRequestDescriptor instead')
const EnrollRequest$json = {
  '1': 'EnrollRequest',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 9, '10': 'code'},
    {'1': 'device_name', '3': 2, '4': 1, '5': 9, '10': 'deviceName'},
    {'1': 'csr_der', '3': 3, '4': 1, '5': 12, '10': 'csrDer'},
  ],
};

/// Descriptor for `EnrollRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List enrollRequestDescriptor = $convert.base64Decode(
    'Cg1FbnJvbGxSZXF1ZXN0EhIKBGNvZGUYASABKAlSBGNvZGUSHwoLZGV2aWNlX25hbWUYAiABKA'
    'lSCmRldmljZU5hbWUSFwoHY3NyX2RlchgDIAEoDFIGY3NyRGVy');

@$core.Deprecated('Use enrollResponseDescriptor instead')
const EnrollResponse$json = {
  '1': 'EnrollResponse',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {
      '1': 'client_certificate_der',
      '3': 2,
      '4': 1,
      '5': 12,
      '10': 'clientCertificateDer'
    },
    {
      '1': 'ca_certificate_der',
      '3': 3,
      '4': 1,
      '5': 12,
      '10': 'caCertificateDer'
    },
  ],
};

/// Descriptor for `EnrollResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List enrollResponseDescriptor = $convert.base64Decode(
    'Cg5FbnJvbGxSZXNwb25zZRIbCglkZXZpY2VfaWQYASABKAlSCGRldmljZUlkEjQKFmNsaWVudF'
    '9jZXJ0aWZpY2F0ZV9kZXIYAiABKAxSFGNsaWVudENlcnRpZmljYXRlRGVyEiwKEmNhX2NlcnRp'
    'ZmljYXRlX2RlchgDIAEoDFIQY2FDZXJ0aWZpY2F0ZURlcg==');

@$core.Deprecated('Use deviceDescriptor instead')
const Device$json = {
  '1': 'Device',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'certificates',
      '3': 12,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.DeviceCertificate',
      '10': 'certificates'
    },
    {
      '1': 'enrolled_at',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'enrolledAt'
    },
    {
      '1': 'last_seen_at',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastSeenAt'
    },
    {'1': 'last_address', '3': 6, '4': 1, '5': 9, '10': 'lastAddress'},
    {
      '1': 'certificate_expires_at',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'certificateExpiresAt'
    },
    {'1': 'revoked', '3': 8, '4': 1, '5': 8, '10': 'revoked'},
    {
      '1': 'revoked_at',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'revokedAt'
    },
    {
      '1': 'revoked_by_device_id',
      '3': 10,
      '4': 1,
      '5': 9,
      '10': 'revokedByDeviceId'
    },
    {'1': 'is_caller', '3': 11, '4': 1, '5': 8, '10': 'isCaller'},
  ],
  '9': [
    {'1': 3, '2': 4},
  ],
};

/// Descriptor for `Device`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceDescriptor = $convert.base64Decode(
    'CgZEZXZpY2USDgoCaWQYASABKAlSAmlkEhIKBG5hbWUYAiABKAlSBG5hbWUSQAoMY2VydGlmaW'
    'NhdGVzGAwgAygLMhwueWFndXJhLnYxLkRldmljZUNlcnRpZmljYXRlUgxjZXJ0aWZpY2F0ZXMS'
    'OwoLZW5yb2xsZWRfYXQYBCABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgplbnJvbG'
    'xlZEF0EjwKDGxhc3Rfc2Vlbl9hdBgFIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBS'
    'Cmxhc3RTZWVuQXQSIQoMbGFzdF9hZGRyZXNzGAYgASgJUgtsYXN0QWRkcmVzcxJQChZjZXJ0aW'
    'ZpY2F0ZV9leHBpcmVzX2F0GAcgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIUY2Vy'
    'dGlmaWNhdGVFeHBpcmVzQXQSGAoHcmV2b2tlZBgIIAEoCFIHcmV2b2tlZBI5CgpyZXZva2VkX2'
    'F0GAkgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJcmV2b2tlZEF0Ei8KFHJldm9r'
    'ZWRfYnlfZGV2aWNlX2lkGAogASgJUhFyZXZva2VkQnlEZXZpY2VJZBIbCglpc19jYWxsZXIYCy'
    'ABKAhSCGlzQ2FsbGVySgQIAxAE');

@$core.Deprecated('Use listDevicesRequestDescriptor instead')
const ListDevicesRequest$json = {
  '1': 'ListDevicesRequest',
};

/// Descriptor for `ListDevicesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesRequestDescriptor =
    $convert.base64Decode('ChJMaXN0RGV2aWNlc1JlcXVlc3Q=');

@$core.Deprecated('Use listDevicesResponseDescriptor instead')
const ListDevicesResponse$json = {
  '1': 'ListDevicesResponse',
  '2': [
    {
      '1': 'devices',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.yagura.v1.Device',
      '10': 'devices'
    },
  ],
};

/// Descriptor for `ListDevicesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0RGV2aWNlc1Jlc3BvbnNlEisKB2RldmljZXMYASADKAsyES55YWd1cmEudjEuRGV2aW'
    'NlUgdkZXZpY2Vz');

@$core.Deprecated('Use revokeDeviceRequestDescriptor instead')
const RevokeDeviceRequest$json = {
  '1': 'RevokeDeviceRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `RevokeDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeDeviceRequestDescriptor =
    $convert.base64Decode(
        'ChNSZXZva2VEZXZpY2VSZXF1ZXN0EhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQ=');

@$core.Deprecated('Use renameDeviceRequestDescriptor instead')
const RenameDeviceRequest$json = {
  '1': 'RenameDeviceRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `RenameDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renameDeviceRequestDescriptor = $convert.base64Decode(
    'ChNSZW5hbWVEZXZpY2VSZXF1ZXN0EhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQSEgoEbm'
    'FtZRgCIAEoCVIEbmFtZQ==');

@$core.Deprecated('Use renewCertificateRequestDescriptor instead')
const RenewCertificateRequest$json = {
  '1': 'RenewCertificateRequest',
  '2': [
    {'1': 'csr_der', '3': 1, '4': 1, '5': 12, '10': 'csrDer'},
  ],
};

/// Descriptor for `RenewCertificateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renewCertificateRequestDescriptor =
    $convert.base64Decode(
        'ChdSZW5ld0NlcnRpZmljYXRlUmVxdWVzdBIXCgdjc3JfZGVyGAEgASgMUgZjc3JEZXI=');

@$core.Deprecated('Use deviceCertificateDescriptor instead')
const DeviceCertificate$json = {
  '1': 'DeviceCertificate',
  '2': [
    {'1': 'sha256', '3': 1, '4': 1, '5': 9, '10': 'sha256'},
    {
      '1': 'not_after',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'notAfter'
    },
  ],
};

/// Descriptor for `DeviceCertificate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceCertificateDescriptor = $convert.base64Decode(
    'ChFEZXZpY2VDZXJ0aWZpY2F0ZRIWCgZzaGEyNTYYASABKAlSBnNoYTI1NhI3Cglub3RfYWZ0ZX'
    'IYAiABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUghub3RBZnRlcg==');
