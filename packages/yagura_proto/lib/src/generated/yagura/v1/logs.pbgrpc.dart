// This is a generated file - do not edit.
//
// Generated from yagura/v1/logs.proto.

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

import 'logs.pb.dart' as $0;

export 'logs.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Logs')
class LogsClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  LogsClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListSourcesResponse> listSources(
    $0.ListSourcesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listSources, request, options: options);
  }

  /// Up to 5000 lines, oldest first, paged across messages.
  $grpc.ResponseStream<$0.LogBatch> backlog(
    $0.BacklogRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$backlog, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Live lines; DROPPED markers when the subscriber lags > 1000 lines.
  $grpc.ResponseStream<$0.LogBatch> follow(
    $0.FollowRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$follow, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$listSources =
      $grpc.ClientMethod<$0.ListSourcesRequest, $0.ListSourcesResponse>(
          '/yagura.v1.Logs/ListSources',
          ($0.ListSourcesRequest value) => value.writeToBuffer(),
          $0.ListSourcesResponse.fromBuffer);
  static final _$backlog = $grpc.ClientMethod<$0.BacklogRequest, $0.LogBatch>(
      '/yagura.v1.Logs/Backlog',
      ($0.BacklogRequest value) => value.writeToBuffer(),
      $0.LogBatch.fromBuffer);
  static final _$follow = $grpc.ClientMethod<$0.FollowRequest, $0.LogBatch>(
      '/yagura.v1.Logs/Follow',
      ($0.FollowRequest value) => value.writeToBuffer(),
      $0.LogBatch.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Logs')
abstract class LogsServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Logs';

  LogsServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.ListSourcesRequest, $0.ListSourcesResponse>(
            'ListSources',
            listSources_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListSourcesRequest.fromBuffer(value),
            ($0.ListSourcesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.BacklogRequest, $0.LogBatch>(
        'Backlog',
        backlog_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.BacklogRequest.fromBuffer(value),
        ($0.LogBatch value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.FollowRequest, $0.LogBatch>(
        'Follow',
        follow_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.FollowRequest.fromBuffer(value),
        ($0.LogBatch value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListSourcesResponse> listSources_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListSourcesRequest> $request) async {
    return listSources($call, await $request);
  }

  $async.Future<$0.ListSourcesResponse> listSources(
      $grpc.ServiceCall call, $0.ListSourcesRequest request);

  $async.Stream<$0.LogBatch> backlog_Pre($grpc.ServiceCall $call,
      $async.Future<$0.BacklogRequest> $request) async* {
    yield* backlog($call, await $request);
  }

  $async.Stream<$0.LogBatch> backlog(
      $grpc.ServiceCall call, $0.BacklogRequest request);

  $async.Stream<$0.LogBatch> follow_Pre($grpc.ServiceCall $call,
      $async.Future<$0.FollowRequest> $request) async* {
    yield* follow($call, await $request);
  }

  $async.Stream<$0.LogBatch> follow(
      $grpc.ServiceCall call, $0.FollowRequest request);
}
