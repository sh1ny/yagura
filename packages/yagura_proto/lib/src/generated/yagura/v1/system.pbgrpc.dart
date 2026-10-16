// This is a generated file - do not edit.
//
// Generated from yagura/v1/system.proto.

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

import 'system.pb.dart' as $0;

export 'system.pb.dart';

@$pb.GrpcServiceName('yagura.v1.System')
class SystemClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  SystemClient(super.channel, {super.options, super.interceptors});

  /// Allowed for any authenticated device. Clients compare api_version major.
  $grpc.ResponseFuture<$0.DaemonInfo> getInfo(
    $0.GetInfoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getInfo, request, options: options);
  }

  $grpc.ResponseFuture<$0.DaemonHealth> getHealth(
    $0.GetHealthRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getHealth, request, options: options);
  }

  /// Audit log, newest first.
  $grpc.ResponseFuture<$0.ListAuditResponse> listAudit(
    $0.ListAuditRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listAudit, request, options: options);
  }

  // method descriptors

  static final _$getInfo = $grpc.ClientMethod<$0.GetInfoRequest, $0.DaemonInfo>(
      '/yagura.v1.System/GetInfo',
      ($0.GetInfoRequest value) => value.writeToBuffer(),
      $0.DaemonInfo.fromBuffer);
  static final _$getHealth =
      $grpc.ClientMethod<$0.GetHealthRequest, $0.DaemonHealth>(
          '/yagura.v1.System/GetHealth',
          ($0.GetHealthRequest value) => value.writeToBuffer(),
          $0.DaemonHealth.fromBuffer);
  static final _$listAudit =
      $grpc.ClientMethod<$0.ListAuditRequest, $0.ListAuditResponse>(
          '/yagura.v1.System/ListAudit',
          ($0.ListAuditRequest value) => value.writeToBuffer(),
          $0.ListAuditResponse.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.System')
abstract class SystemServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.System';

  SystemServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.GetInfoRequest, $0.DaemonInfo>(
        'GetInfo',
        getInfo_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetInfoRequest.fromBuffer(value),
        ($0.DaemonInfo value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetHealthRequest, $0.DaemonHealth>(
        'GetHealth',
        getHealth_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetHealthRequest.fromBuffer(value),
        ($0.DaemonHealth value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListAuditRequest, $0.ListAuditResponse>(
        'ListAudit',
        listAudit_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListAuditRequest.fromBuffer(value),
        ($0.ListAuditResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.DaemonInfo> getInfo_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetInfoRequest> $request) async {
    return getInfo($call, await $request);
  }

  $async.Future<$0.DaemonInfo> getInfo(
      $grpc.ServiceCall call, $0.GetInfoRequest request);

  $async.Future<$0.DaemonHealth> getHealth_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetHealthRequest> $request) async {
    return getHealth($call, await $request);
  }

  $async.Future<$0.DaemonHealth> getHealth(
      $grpc.ServiceCall call, $0.GetHealthRequest request);

  $async.Future<$0.ListAuditResponse> listAudit_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListAuditRequest> $request) async {
    return listAudit($call, await $request);
  }

  $async.Future<$0.ListAuditResponse> listAudit(
      $grpc.ServiceCall call, $0.ListAuditRequest request);
}
