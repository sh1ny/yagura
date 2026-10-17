// This is a generated file - do not edit.
//
// Generated from yagura/v1/rcon.proto.

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

import 'rcon.pb.dart' as $0;

export 'rcon.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Rcon')
class RconClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  RconClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ExecuteResponse> execute(
    $0.ExecuteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$execute, request, options: options);
  }

  /// Bidirectional console. First client message must carry instance_id.
  $grpc.ResponseStream<$0.ConsoleOutput> console(
    $async.Stream<$0.ConsoleInput> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$console, request, options: options);
  }

  // method descriptors

  static final _$execute =
      $grpc.ClientMethod<$0.ExecuteRequest, $0.ExecuteResponse>(
          '/yagura.v1.Rcon/Execute',
          ($0.ExecuteRequest value) => value.writeToBuffer(),
          $0.ExecuteResponse.fromBuffer);
  static final _$console =
      $grpc.ClientMethod<$0.ConsoleInput, $0.ConsoleOutput>(
          '/yagura.v1.Rcon/Console',
          ($0.ConsoleInput value) => value.writeToBuffer(),
          $0.ConsoleOutput.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Rcon')
abstract class RconServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Rcon';

  RconServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ExecuteRequest, $0.ExecuteResponse>(
        'Execute',
        execute_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ExecuteRequest.fromBuffer(value),
        ($0.ExecuteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ConsoleInput, $0.ConsoleOutput>(
        'Console',
        console,
        true,
        true,
        ($core.List<$core.int> value) => $0.ConsoleInput.fromBuffer(value),
        ($0.ConsoleOutput value) => value.writeToBuffer()));
  }

  $async.Future<$0.ExecuteResponse> execute_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ExecuteRequest> $request) async {
    return execute($call, await $request);
  }

  $async.Future<$0.ExecuteResponse> execute(
      $grpc.ServiceCall call, $0.ExecuteRequest request);

  $async.Stream<$0.ConsoleOutput> console(
      $grpc.ServiceCall call, $async.Stream<$0.ConsoleInput> request);
}
