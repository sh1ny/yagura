// This is a generated file - do not edit.
//
// Generated from yagura/v1/pairing.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'pairing.pb.dart' as $0;

export 'pairing.pb.dart';

/// Enroll and Info are the only methods that accept a connection without a
/// client certificate (TLS server auth only; the client pins the CA
/// fingerprint from the pairing string). Everything else requires mTLS with
/// an enrolled, non-revoked device certificate (ADR 0007).
@$pb.GrpcServiceName('yagura.v1.Pairing')
class PairingClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  PairingClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.PairingInfo> info(
    $0.PairingInfoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$info, request, options: options);
  }

  $grpc.ResponseFuture<$0.EnrollResponse> enroll(
    $0.EnrollRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$enroll, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListDevicesResponse> listDevices(
    $0.ListDevicesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listDevices, request, options: options);
  }

  $grpc.ResponseFuture<$0.Device> revokeDevice(
    $0.RevokeDeviceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$revokeDevice, request, options: options);
  }

  $grpc.ResponseFuture<$0.Device> renameDevice(
    $0.RenameDeviceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$renameDevice, request, options: options);
  }

  /// Over the caller's existing mTLS connection: signs a CSR for a new key,
  /// adds a certificate row to the same device; the old one works until it expires.
  $grpc.ResponseFuture<$0.EnrollResponse> renewCertificate(
    $0.RenewCertificateRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$renewCertificate, request, options: options);
  }

  // method descriptors

  static final _$info =
      $grpc.ClientMethod<$0.PairingInfoRequest, $0.PairingInfo>(
          '/yagura.v1.Pairing/Info',
          ($0.PairingInfoRequest value) => value.writeToBuffer(),
          $0.PairingInfo.fromBuffer);
  static final _$enroll =
      $grpc.ClientMethod<$0.EnrollRequest, $0.EnrollResponse>(
          '/yagura.v1.Pairing/Enroll',
          ($0.EnrollRequest value) => value.writeToBuffer(),
          $0.EnrollResponse.fromBuffer);
  static final _$listDevices =
      $grpc.ClientMethod<$0.ListDevicesRequest, $0.ListDevicesResponse>(
          '/yagura.v1.Pairing/ListDevices',
          ($0.ListDevicesRequest value) => value.writeToBuffer(),
          $0.ListDevicesResponse.fromBuffer);
  static final _$revokeDevice =
      $grpc.ClientMethod<$0.RevokeDeviceRequest, $0.Device>(
          '/yagura.v1.Pairing/RevokeDevice',
          ($0.RevokeDeviceRequest value) => value.writeToBuffer(),
          $0.Device.fromBuffer);
  static final _$renameDevice =
      $grpc.ClientMethod<$0.RenameDeviceRequest, $0.Device>(
          '/yagura.v1.Pairing/RenameDevice',
          ($0.RenameDeviceRequest value) => value.writeToBuffer(),
          $0.Device.fromBuffer);
  static final _$renewCertificate =
      $grpc.ClientMethod<$0.RenewCertificateRequest, $0.EnrollResponse>(
          '/yagura.v1.Pairing/RenewCertificate',
          ($0.RenewCertificateRequest value) => value.writeToBuffer(),
          $0.EnrollResponse.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Pairing')
abstract class PairingServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Pairing';

  PairingServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.PairingInfoRequest, $0.PairingInfo>(
        'Info',
        info_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.PairingInfoRequest.fromBuffer(value),
        ($0.PairingInfo value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.EnrollRequest, $0.EnrollResponse>(
        'Enroll',
        enroll_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.EnrollRequest.fromBuffer(value),
        ($0.EnrollResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListDevicesRequest, $0.ListDevicesResponse>(
            'ListDevices',
            listDevices_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListDevicesRequest.fromBuffer(value),
            ($0.ListDevicesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RevokeDeviceRequest, $0.Device>(
        'RevokeDevice',
        revokeDevice_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RevokeDeviceRequest.fromBuffer(value),
        ($0.Device value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RenameDeviceRequest, $0.Device>(
        'RenameDevice',
        renameDevice_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RenameDeviceRequest.fromBuffer(value),
        ($0.Device value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.RenewCertificateRequest, $0.EnrollResponse>(
            'RenewCertificate',
            renewCertificate_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.RenewCertificateRequest.fromBuffer(value),
            ($0.EnrollResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.PairingInfo> info_Pre($grpc.ServiceCall $call,
      $async.Future<$0.PairingInfoRequest> $request) async {
    return info($call, await $request);
  }

  $async.Future<$0.PairingInfo> info(
      $grpc.ServiceCall call, $0.PairingInfoRequest request);

  $async.Future<$0.EnrollResponse> enroll_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.EnrollRequest> $request) async {
    return enroll($call, await $request);
  }

  $async.Future<$0.EnrollResponse> enroll(
      $grpc.ServiceCall call, $0.EnrollRequest request);

  $async.Future<$0.ListDevicesResponse> listDevices_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListDevicesRequest> $request) async {
    return listDevices($call, await $request);
  }

  $async.Future<$0.ListDevicesResponse> listDevices(
      $grpc.ServiceCall call, $0.ListDevicesRequest request);

  $async.Future<$0.Device> revokeDevice_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RevokeDeviceRequest> $request) async {
    return revokeDevice($call, await $request);
  }

  $async.Future<$0.Device> revokeDevice(
      $grpc.ServiceCall call, $0.RevokeDeviceRequest request);

  $async.Future<$0.Device> renameDevice_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RenameDeviceRequest> $request) async {
    return renameDevice($call, await $request);
  }

  $async.Future<$0.Device> renameDevice(
      $grpc.ServiceCall call, $0.RenameDeviceRequest request);

  $async.Future<$0.EnrollResponse> renewCertificate_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RenewCertificateRequest> $request) async {
    return renewCertificate($call, await $request);
  }

  $async.Future<$0.EnrollResponse> renewCertificate(
      $grpc.ServiceCall call, $0.RenewCertificateRequest request);
}
