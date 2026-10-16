// This is a generated file - do not edit.
//
// Generated from yagura/v1/pairing.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class PairingInfoRequest extends $pb.GeneratedMessage {
  factory PairingInfoRequest() => PairingInfoRequest._();

  PairingInfoRequest._();

  factory PairingInfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairingInfoRequest()..mergeFromBuffer(data, registry);
  factory PairingInfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairingInfoRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairingInfoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PairingInfoRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairingInfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairingInfoRequest copyWith(void Function(PairingInfoRequest) updates) =>
      super.copyWith((message) => updates(message as PairingInfoRequest))
          as PairingInfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PairingInfoRequest() / PairingInfoRequest.new instead')
  static PairingInfoRequest create() => PairingInfoRequest._();
  static $pb.GeneratedMessage $_createMessage() => PairingInfoRequest._();
  @$core.override
  PairingInfoRequest createEmptyInstance() => PairingInfoRequest._();
  @$core.pragma('dart2js:noInline')
  static PairingInfoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PairingInfoRequest>(
          PairingInfoRequest.$_createMessage);
  static PairingInfoRequest? _defaultInstance;
}

class PairingInfo extends $pb.GeneratedMessage {
  factory PairingInfo({
    $core.String? daemonName,
    $core.String? caFingerprintSha256,
    $core.String? apiVersion,
    $core.List<$core.int>? caCertificateDer,
    $core.String? tlsAuthority,
  }) {
    final result = PairingInfo._();
    if (daemonName != null) result.daemonName = daemonName;
    if (caFingerprintSha256 != null)
      result.caFingerprintSha256 = caFingerprintSha256;
    if (apiVersion != null) result.apiVersion = apiVersion;
    if (caCertificateDer != null) result.caCertificateDer = caCertificateDer;
    if (tlsAuthority != null) result.tlsAuthority = tlsAuthority;
    return result;
  }

  PairingInfo._();

  factory PairingInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairingInfo()..mergeFromBuffer(data, registry);
  factory PairingInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairingInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairingInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: PairingInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'daemonName')
    ..aOS(2, _omitFieldNames ? '' : 'caFingerprintSha256')
    ..aOS(3, _omitFieldNames ? '' : 'apiVersion')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'caCertificateDer', $pb.PbFieldType.OY)
    ..aOS(5, _omitFieldNames ? '' : 'tlsAuthority')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairingInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairingInfo copyWith(void Function(PairingInfo) updates) =>
      super.copyWith((message) => updates(message as PairingInfo))
          as PairingInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PairingInfo() / PairingInfo.new instead')
  static PairingInfo create() => PairingInfo._();
  static $pb.GeneratedMessage $_createMessage() => PairingInfo._();
  @$core.override
  PairingInfo createEmptyInstance() => PairingInfo._();
  @$core.pragma('dart2js:noInline')
  static PairingInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PairingInfo>(
          PairingInfo.$_createMessage);
  static PairingInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get daemonName => $_getSZ(0);
  @$pb.TagNumber(1)
  set daemonName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDaemonName() => $_has(0);
  @$pb.TagNumber(1)
  void clearDaemonName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get caFingerprintSha256 => $_getSZ(1);
  @$pb.TagNumber(2)
  set caFingerprintSha256($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCaFingerprintSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearCaFingerprintSha256() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get apiVersion => $_getSZ(2);
  @$pb.TagNumber(3)
  set apiVersion($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasApiVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearApiVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get caCertificateDer => $_getN(3);
  @$pb.TagNumber(4)
  set caCertificateDer($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCaCertificateDer() => $_has(3);
  @$pb.TagNumber(4)
  void clearCaCertificateDer() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get tlsAuthority => $_getSZ(4);
  @$pb.TagNumber(5)
  set tlsAuthority($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTlsAuthority() => $_has(4);
  @$pb.TagNumber(5)
  void clearTlsAuthority() => $_clearField(5);
}

class EnrollRequest extends $pb.GeneratedMessage {
  factory EnrollRequest({
    $core.String? code,
    $core.String? deviceName,
    $core.List<$core.int>? csrDer,
  }) {
    final result = EnrollRequest._();
    if (code != null) result.code = code;
    if (deviceName != null) result.deviceName = deviceName;
    if (csrDer != null) result.csrDer = csrDer;
    return result;
  }

  EnrollRequest._();

  factory EnrollRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EnrollRequest()..mergeFromBuffer(data, registry);
  factory EnrollRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EnrollRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnrollRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: EnrollRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..aOS(2, _omitFieldNames ? '' : 'deviceName')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'csrDer', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnrollRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnrollRequest copyWith(void Function(EnrollRequest) updates) =>
      super.copyWith((message) => updates(message as EnrollRequest))
          as EnrollRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EnrollRequest() / EnrollRequest.new instead')
  static EnrollRequest create() => EnrollRequest._();
  static $pb.GeneratedMessage $_createMessage() => EnrollRequest._();
  @$core.override
  EnrollRequest createEmptyInstance() => EnrollRequest._();
  @$core.pragma('dart2js:noInline')
  static EnrollRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EnrollRequest>(
          EnrollRequest.$_createMessage);
  static EnrollRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get csrDer => $_getN(2);
  @$pb.TagNumber(3)
  set csrDer($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCsrDer() => $_has(2);
  @$pb.TagNumber(3)
  void clearCsrDer() => $_clearField(3);
}

class EnrollResponse extends $pb.GeneratedMessage {
  factory EnrollResponse({
    $core.String? deviceId,
    $core.List<$core.int>? clientCertificateDer,
    $core.List<$core.int>? caCertificateDer,
  }) {
    final result = EnrollResponse._();
    if (deviceId != null) result.deviceId = deviceId;
    if (clientCertificateDer != null)
      result.clientCertificateDer = clientCertificateDer;
    if (caCertificateDer != null) result.caCertificateDer = caCertificateDer;
    return result;
  }

  EnrollResponse._();

  factory EnrollResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EnrollResponse()..mergeFromBuffer(data, registry);
  factory EnrollResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EnrollResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnrollResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: EnrollResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'clientCertificateDer', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'caCertificateDer', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnrollResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnrollResponse copyWith(void Function(EnrollResponse) updates) =>
      super.copyWith((message) => updates(message as EnrollResponse))
          as EnrollResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EnrollResponse() / EnrollResponse.new instead')
  static EnrollResponse create() => EnrollResponse._();
  static $pb.GeneratedMessage $_createMessage() => EnrollResponse._();
  @$core.override
  EnrollResponse createEmptyInstance() => EnrollResponse._();
  @$core.pragma('dart2js:noInline')
  static EnrollResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EnrollResponse>(
          EnrollResponse.$_createMessage);
  static EnrollResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get clientCertificateDer => $_getN(1);
  @$pb.TagNumber(2)
  set clientCertificateDer($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClientCertificateDer() => $_has(1);
  @$pb.TagNumber(2)
  void clearClientCertificateDer() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get caCertificateDer => $_getN(2);
  @$pb.TagNumber(3)
  set caCertificateDer($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCaCertificateDer() => $_has(2);
  @$pb.TagNumber(3)
  void clearCaCertificateDer() => $_clearField(3);
}

class Device extends $pb.GeneratedMessage {
  factory Device({
    $core.String? id,
    $core.String? name,
    $1.Timestamp? enrolledAt,
    $1.Timestamp? lastSeenAt,
    $core.String? lastAddress,
    $1.Timestamp? certificateExpiresAt,
    $core.bool? revoked,
    $1.Timestamp? revokedAt,
    $core.String? revokedByDeviceId,
    $core.bool? isCaller,
    $core.Iterable<DeviceCertificate>? certificates,
  }) {
    final result = Device._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (enrolledAt != null) result.enrolledAt = enrolledAt;
    if (lastSeenAt != null) result.lastSeenAt = lastSeenAt;
    if (lastAddress != null) result.lastAddress = lastAddress;
    if (certificateExpiresAt != null)
      result.certificateExpiresAt = certificateExpiresAt;
    if (revoked != null) result.revoked = revoked;
    if (revokedAt != null) result.revokedAt = revokedAt;
    if (revokedByDeviceId != null) result.revokedByDeviceId = revokedByDeviceId;
    if (isCaller != null) result.isCaller = isCaller;
    if (certificates != null) result.certificates.addAll(certificates);
    return result;
  }

  Device._();

  factory Device.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Device()..mergeFromBuffer(data, registry);
  factory Device.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Device()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Device',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: Device.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOM<$1.Timestamp>(4, _omitFieldNames ? '' : 'enrolledAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOM<$1.Timestamp>(5, _omitFieldNames ? '' : 'lastSeenAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOS(6, _omitFieldNames ? '' : 'lastAddress')
    ..aOM<$1.Timestamp>(7, _omitFieldNames ? '' : 'certificateExpiresAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOB(8, _omitFieldNames ? '' : 'revoked')
    ..aOM<$1.Timestamp>(9, _omitFieldNames ? '' : 'revokedAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOS(10, _omitFieldNames ? '' : 'revokedByDeviceId')
    ..aOB(11, _omitFieldNames ? '' : 'isCaller')
    ..pPM<DeviceCertificate>(12, _omitFieldNames ? '' : 'certificates',
        subBuilder: DeviceCertificate.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Device clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Device copyWith(void Function(Device) updates) =>
      super.copyWith((message) => updates(message as Device)) as Device;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Device() / Device.new instead')
  static Device create() => Device._();
  static $pb.GeneratedMessage $_createMessage() => Device._();
  @$core.override
  Device createEmptyInstance() => Device._();
  @$core.pragma('dart2js:noInline')
  static Device getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Device>(Device.$_createMessage);
  static Device? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(4)
  $1.Timestamp get enrolledAt => $_getN(2);
  @$pb.TagNumber(4)
  set enrolledAt($1.Timestamp value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEnrolledAt() => $_has(2);
  @$pb.TagNumber(4)
  void clearEnrolledAt() => $_clearField(4);
  @$pb.TagNumber(4)
  $1.Timestamp ensureEnrolledAt() => $_ensure(2);

  @$pb.TagNumber(5)
  $1.Timestamp get lastSeenAt => $_getN(3);
  @$pb.TagNumber(5)
  set lastSeenAt($1.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasLastSeenAt() => $_has(3);
  @$pb.TagNumber(5)
  void clearLastSeenAt() => $_clearField(5);
  @$pb.TagNumber(5)
  $1.Timestamp ensureLastSeenAt() => $_ensure(3);

  @$pb.TagNumber(6)
  $core.String get lastAddress => $_getSZ(4);
  @$pb.TagNumber(6)
  set lastAddress($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasLastAddress() => $_has(4);
  @$pb.TagNumber(6)
  void clearLastAddress() => $_clearField(6);

  @$pb.TagNumber(7)
  $1.Timestamp get certificateExpiresAt => $_getN(5);
  @$pb.TagNumber(7)
  set certificateExpiresAt($1.Timestamp value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasCertificateExpiresAt() => $_has(5);
  @$pb.TagNumber(7)
  void clearCertificateExpiresAt() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.Timestamp ensureCertificateExpiresAt() => $_ensure(5);

  @$pb.TagNumber(8)
  $core.bool get revoked => $_getBF(6);
  @$pb.TagNumber(8)
  set revoked($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(8)
  $core.bool hasRevoked() => $_has(6);
  @$pb.TagNumber(8)
  void clearRevoked() => $_clearField(8);

  @$pb.TagNumber(9)
  $1.Timestamp get revokedAt => $_getN(7);
  @$pb.TagNumber(9)
  set revokedAt($1.Timestamp value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasRevokedAt() => $_has(7);
  @$pb.TagNumber(9)
  void clearRevokedAt() => $_clearField(9);
  @$pb.TagNumber(9)
  $1.Timestamp ensureRevokedAt() => $_ensure(7);

  @$pb.TagNumber(10)
  $core.String get revokedByDeviceId => $_getSZ(8);
  @$pb.TagNumber(10)
  set revokedByDeviceId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(10)
  $core.bool hasRevokedByDeviceId() => $_has(8);
  @$pb.TagNumber(10)
  void clearRevokedByDeviceId() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get isCaller => $_getBF(9);
  @$pb.TagNumber(11)
  set isCaller($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(11)
  $core.bool hasIsCaller() => $_has(9);
  @$pb.TagNumber(11)
  void clearIsCaller() => $_clearField(11);

  @$pb.TagNumber(12)
  $pb.PbList<DeviceCertificate> get certificates => $_getList(10);
}

class ListDevicesRequest extends $pb.GeneratedMessage {
  factory ListDevicesRequest() => ListDevicesRequest._();

  ListDevicesRequest._();

  factory ListDevicesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesRequest()..mergeFromBuffer(data, registry);
  factory ListDevicesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListDevicesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListDevicesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesRequest copyWith(void Function(ListDevicesRequest) updates) =>
      super.copyWith((message) => updates(message as ListDevicesRequest))
          as ListDevicesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListDevicesRequest() / ListDevicesRequest.new instead')
  static ListDevicesRequest create() => ListDevicesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListDevicesRequest._();
  @$core.override
  ListDevicesRequest createEmptyInstance() => ListDevicesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListDevicesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListDevicesRequest>(
          ListDevicesRequest.$_createMessage);
  static ListDevicesRequest? _defaultInstance;
}

class ListDevicesResponse extends $pb.GeneratedMessage {
  factory ListDevicesResponse({
    $core.Iterable<Device>? devices,
  }) {
    final result = ListDevicesResponse._();
    if (devices != null) result.devices.addAll(devices);
    return result;
  }

  ListDevicesResponse._();

  factory ListDevicesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesResponse()..mergeFromBuffer(data, registry);
  factory ListDevicesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListDevicesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListDevicesResponse.$_createMessage)
    ..pPM<Device>(1, _omitFieldNames ? '' : 'devices',
        subBuilder: Device.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesResponse copyWith(void Function(ListDevicesResponse) updates) =>
      super.copyWith((message) => updates(message as ListDevicesResponse))
          as ListDevicesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListDevicesResponse() / ListDevicesResponse.new instead')
  static ListDevicesResponse create() => ListDevicesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListDevicesResponse._();
  @$core.override
  ListDevicesResponse createEmptyInstance() => ListDevicesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListDevicesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListDevicesResponse>(
          ListDevicesResponse.$_createMessage);
  static ListDevicesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Device> get devices => $_getList(0);
}

class RevokeDeviceRequest extends $pb.GeneratedMessage {
  factory RevokeDeviceRequest({
    $core.String? deviceId,
  }) {
    final result = RevokeDeviceRequest._();
    if (deviceId != null) result.deviceId = deviceId;
    return result;
  }

  RevokeDeviceRequest._();

  factory RevokeDeviceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceRequest()..mergeFromBuffer(data, registry);
  factory RevokeDeviceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeDeviceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: RevokeDeviceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceRequest copyWith(void Function(RevokeDeviceRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeDeviceRequest))
          as RevokeDeviceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RevokeDeviceRequest() / RevokeDeviceRequest.new instead')
  static RevokeDeviceRequest create() => RevokeDeviceRequest._();
  static $pb.GeneratedMessage $_createMessage() => RevokeDeviceRequest._();
  @$core.override
  RevokeDeviceRequest createEmptyInstance() => RevokeDeviceRequest._();
  @$core.pragma('dart2js:noInline')
  static RevokeDeviceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeDeviceRequest>(
          RevokeDeviceRequest.$_createMessage);
  static RevokeDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);
}

class RenameDeviceRequest extends $pb.GeneratedMessage {
  factory RenameDeviceRequest({
    $core.String? deviceId,
    $core.String? name,
  }) {
    final result = RenameDeviceRequest._();
    if (deviceId != null) result.deviceId = deviceId;
    if (name != null) result.name = name;
    return result;
  }

  RenameDeviceRequest._();

  factory RenameDeviceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenameDeviceRequest()..mergeFromBuffer(data, registry);
  factory RenameDeviceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenameDeviceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenameDeviceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: RenameDeviceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenameDeviceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenameDeviceRequest copyWith(void Function(RenameDeviceRequest) updates) =>
      super.copyWith((message) => updates(message as RenameDeviceRequest))
          as RenameDeviceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RenameDeviceRequest() / RenameDeviceRequest.new instead')
  static RenameDeviceRequest create() => RenameDeviceRequest._();
  static $pb.GeneratedMessage $_createMessage() => RenameDeviceRequest._();
  @$core.override
  RenameDeviceRequest createEmptyInstance() => RenameDeviceRequest._();
  @$core.pragma('dart2js:noInline')
  static RenameDeviceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RenameDeviceRequest>(
          RenameDeviceRequest.$_createMessage);
  static RenameDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);
}

class RenewCertificateRequest extends $pb.GeneratedMessage {
  factory RenewCertificateRequest({
    $core.List<$core.int>? csrDer,
  }) {
    final result = RenewCertificateRequest._();
    if (csrDer != null) result.csrDer = csrDer;
    return result;
  }

  RenewCertificateRequest._();

  factory RenewCertificateRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenewCertificateRequest()..mergeFromBuffer(data, registry);
  factory RenewCertificateRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenewCertificateRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenewCertificateRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: RenewCertificateRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'csrDer', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenewCertificateRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenewCertificateRequest copyWith(
          void Function(RenewCertificateRequest) updates) =>
      super.copyWith((message) => updates(message as RenewCertificateRequest))
          as RenewCertificateRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RenewCertificateRequest() / RenewCertificateRequest.new instead')
  static RenewCertificateRequest create() => RenewCertificateRequest._();
  static $pb.GeneratedMessage $_createMessage() => RenewCertificateRequest._();
  @$core.override
  RenewCertificateRequest createEmptyInstance() => RenewCertificateRequest._();
  @$core.pragma('dart2js:noInline')
  static RenewCertificateRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RenewCertificateRequest>(
          RenewCertificateRequest.$_createMessage);
  static RenewCertificateRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get csrDer => $_getN(0);
  @$pb.TagNumber(1)
  set csrDer($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCsrDer() => $_has(0);
  @$pb.TagNumber(1)
  void clearCsrDer() => $_clearField(1);
}

class DeviceCertificate extends $pb.GeneratedMessage {
  factory DeviceCertificate({
    $core.String? sha256,
    $1.Timestamp? notAfter,
  }) {
    final result = DeviceCertificate._();
    if (sha256 != null) result.sha256 = sha256;
    if (notAfter != null) result.notAfter = notAfter;
    return result;
  }

  DeviceCertificate._();

  factory DeviceCertificate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceCertificate()..mergeFromBuffer(data, registry);
  factory DeviceCertificate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceCertificate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceCertificate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: DeviceCertificate.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sha256')
    ..aOM<$1.Timestamp>(2, _omitFieldNames ? '' : 'notAfter',
        subBuilder: $1.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceCertificate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceCertificate copyWith(void Function(DeviceCertificate) updates) =>
      super.copyWith((message) => updates(message as DeviceCertificate))
          as DeviceCertificate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeviceCertificate() / DeviceCertificate.new instead')
  static DeviceCertificate create() => DeviceCertificate._();
  static $pb.GeneratedMessage $_createMessage() => DeviceCertificate._();
  @$core.override
  DeviceCertificate createEmptyInstance() => DeviceCertificate._();
  @$core.pragma('dart2js:noInline')
  static DeviceCertificate getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceCertificate>(
          DeviceCertificate.$_createMessage);
  static DeviceCertificate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sha256 => $_getSZ(0);
  @$pb.TagNumber(1)
  set sha256($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSha256() => $_has(0);
  @$pb.TagNumber(1)
  void clearSha256() => $_clearField(1);

  @$pb.TagNumber(2)
  $1.Timestamp get notAfter => $_getN(1);
  @$pb.TagNumber(2)
  set notAfter($1.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasNotAfter() => $_has(1);
  @$pb.TagNumber(2)
  void clearNotAfter() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Timestamp ensureNotAfter() => $_ensure(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
