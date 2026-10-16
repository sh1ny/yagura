// This is a generated file - do not edit.
//
// Generated from yagura/v1/firewall.proto.

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

import 'firewall.pb.dart' as $0;

export 'firewall.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Firewall')
class FirewallClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  FirewallClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListRulesResponse> listRules(
    $0.ListRulesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listRules, request, options: options);
  }

  $grpc.ResponseFuture<$0.ReconcileResponse> reconcile(
    $0.ReconcileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reconcile, request, options: options);
  }

  // method descriptors

  static final _$listRules =
      $grpc.ClientMethod<$0.ListRulesRequest, $0.ListRulesResponse>(
          '/yagura.v1.Firewall/ListRules',
          ($0.ListRulesRequest value) => value.writeToBuffer(),
          $0.ListRulesResponse.fromBuffer);
  static final _$reconcile =
      $grpc.ClientMethod<$0.ReconcileRequest, $0.ReconcileResponse>(
          '/yagura.v1.Firewall/Reconcile',
          ($0.ReconcileRequest value) => value.writeToBuffer(),
          $0.ReconcileResponse.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Firewall')
abstract class FirewallServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Firewall';

  FirewallServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ListRulesRequest, $0.ListRulesResponse>(
        'ListRules',
        listRules_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListRulesRequest.fromBuffer(value),
        ($0.ListRulesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ReconcileRequest, $0.ReconcileResponse>(
        'Reconcile',
        reconcile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ReconcileRequest.fromBuffer(value),
        ($0.ReconcileResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListRulesResponse> listRules_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListRulesRequest> $request) async {
    return listRules($call, await $request);
  }

  $async.Future<$0.ListRulesResponse> listRules(
      $grpc.ServiceCall call, $0.ListRulesRequest request);

  $async.Future<$0.ReconcileResponse> reconcile_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ReconcileRequest> $request) async {
    return reconcile($call, await $request);
  }

  $async.Future<$0.ReconcileResponse> reconcile(
      $grpc.ServiceCall call, $0.ReconcileRequest request);
}
