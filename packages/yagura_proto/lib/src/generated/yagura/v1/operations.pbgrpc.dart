// This is a generated file - do not edit.
//
// Generated from yagura/v1/operations.proto.

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

import 'operations.pb.dart' as $0;

export 'operations.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Operations')
class OperationsClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  OperationsClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.Operation> getOperation(
    $0.GetOperationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getOperation, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListOperationsResponse> listOperations(
    $0.ListOperationsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listOperations, request, options: options);
  }

  /// Ordered events; pass after_sequence to resume without gaps.
  $grpc.ResponseStream<$0.OperationEvent> watchOperation(
    $0.WatchOperationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchOperation, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.Operation> cancelOperation(
    $0.CancelOperationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$cancelOperation, request, options: options);
  }

  /// Answers a prompt raised by the operation (Steam Guard code...).
  $grpc.ResponseFuture<$0.Operation> respondToPrompt(
    $0.RespondToPromptRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$respondToPrompt, request, options: options);
  }

  // method descriptors

  static final _$getOperation =
      $grpc.ClientMethod<$0.GetOperationRequest, $0.Operation>(
          '/yagura.v1.Operations/GetOperation',
          ($0.GetOperationRequest value) => value.writeToBuffer(),
          $0.Operation.fromBuffer);
  static final _$listOperations =
      $grpc.ClientMethod<$0.ListOperationsRequest, $0.ListOperationsResponse>(
          '/yagura.v1.Operations/ListOperations',
          ($0.ListOperationsRequest value) => value.writeToBuffer(),
          $0.ListOperationsResponse.fromBuffer);
  static final _$watchOperation =
      $grpc.ClientMethod<$0.WatchOperationRequest, $0.OperationEvent>(
          '/yagura.v1.Operations/WatchOperation',
          ($0.WatchOperationRequest value) => value.writeToBuffer(),
          $0.OperationEvent.fromBuffer);
  static final _$cancelOperation =
      $grpc.ClientMethod<$0.CancelOperationRequest, $0.Operation>(
          '/yagura.v1.Operations/CancelOperation',
          ($0.CancelOperationRequest value) => value.writeToBuffer(),
          $0.Operation.fromBuffer);
  static final _$respondToPrompt =
      $grpc.ClientMethod<$0.RespondToPromptRequest, $0.Operation>(
          '/yagura.v1.Operations/RespondToPrompt',
          ($0.RespondToPromptRequest value) => value.writeToBuffer(),
          $0.Operation.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Operations')
abstract class OperationsServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Operations';

  OperationsServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.GetOperationRequest, $0.Operation>(
        'GetOperation',
        getOperation_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetOperationRequest.fromBuffer(value),
        ($0.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListOperationsRequest,
            $0.ListOperationsResponse>(
        'ListOperations',
        listOperations_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListOperationsRequest.fromBuffer(value),
        ($0.ListOperationsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.WatchOperationRequest, $0.OperationEvent>(
        'WatchOperation',
        watchOperation_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.WatchOperationRequest.fromBuffer(value),
        ($0.OperationEvent value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CancelOperationRequest, $0.Operation>(
        'CancelOperation',
        cancelOperation_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CancelOperationRequest.fromBuffer(value),
        ($0.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RespondToPromptRequest, $0.Operation>(
        'RespondToPrompt',
        respondToPrompt_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RespondToPromptRequest.fromBuffer(value),
        ($0.Operation value) => value.writeToBuffer()));
  }

  $async.Future<$0.Operation> getOperation_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetOperationRequest> $request) async {
    return getOperation($call, await $request);
  }

  $async.Future<$0.Operation> getOperation(
      $grpc.ServiceCall call, $0.GetOperationRequest request);

  $async.Future<$0.ListOperationsResponse> listOperations_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListOperationsRequest> $request) async {
    return listOperations($call, await $request);
  }

  $async.Future<$0.ListOperationsResponse> listOperations(
      $grpc.ServiceCall call, $0.ListOperationsRequest request);

  $async.Stream<$0.OperationEvent> watchOperation_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchOperationRequest> $request) async* {
    yield* watchOperation($call, await $request);
  }

  $async.Stream<$0.OperationEvent> watchOperation(
      $grpc.ServiceCall call, $0.WatchOperationRequest request);

  $async.Future<$0.Operation> cancelOperation_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CancelOperationRequest> $request) async {
    return cancelOperation($call, await $request);
  }

  $async.Future<$0.Operation> cancelOperation(
      $grpc.ServiceCall call, $0.CancelOperationRequest request);

  $async.Future<$0.Operation> respondToPrompt_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RespondToPromptRequest> $request) async {
    return respondToPrompt($call, await $request);
  }

  $async.Future<$0.Operation> respondToPrompt(
      $grpc.ServiceCall call, $0.RespondToPromptRequest request);
}
