// This is a generated file - do not edit.
//
// Generated from yagura/v1/steam.proto.

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

import 'operations.pb.dart' as $1;
import 'steam.pb.dart' as $0;

export 'steam.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Steam')
class SteamClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  SteamClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListAccountsResponse> listAccounts(
    $0.ListAccountsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listAccounts, request, options: options);
  }

  /// Starts an add_steam_account operation; Steam Guard arrives as a Prompt
  /// on that operation and is answered with Operations.RespondToPrompt.
  $grpc.ResponseFuture<$1.Operation> addAccount(
    $0.AddAccountRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$addAccount, request, options: options);
  }

  /// Re-login for an account whose cached login expired.
  $grpc.ResponseFuture<$1.Operation> reauthAccount(
    $0.ReauthAccountRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reauthAccount, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListAccountsResponse> removeAccount(
    $0.RemoveAccountRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removeAccount, request, options: options);
  }

  // method descriptors

  static final _$listAccounts =
      $grpc.ClientMethod<$0.ListAccountsRequest, $0.ListAccountsResponse>(
          '/yagura.v1.Steam/ListAccounts',
          ($0.ListAccountsRequest value) => value.writeToBuffer(),
          $0.ListAccountsResponse.fromBuffer);
  static final _$addAccount =
      $grpc.ClientMethod<$0.AddAccountRequest, $1.Operation>(
          '/yagura.v1.Steam/AddAccount',
          ($0.AddAccountRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$reauthAccount =
      $grpc.ClientMethod<$0.ReauthAccountRequest, $1.Operation>(
          '/yagura.v1.Steam/ReauthAccount',
          ($0.ReauthAccountRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$removeAccount =
      $grpc.ClientMethod<$0.RemoveAccountRequest, $0.ListAccountsResponse>(
          '/yagura.v1.Steam/RemoveAccount',
          ($0.RemoveAccountRequest value) => value.writeToBuffer(),
          $0.ListAccountsResponse.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Steam')
abstract class SteamServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Steam';

  SteamServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.ListAccountsRequest, $0.ListAccountsResponse>(
            'ListAccounts',
            listAccounts_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListAccountsRequest.fromBuffer(value),
            ($0.ListAccountsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AddAccountRequest, $1.Operation>(
        'AddAccount',
        addAccount_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.AddAccountRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ReauthAccountRequest, $1.Operation>(
        'ReauthAccount',
        reauthAccount_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ReauthAccountRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.RemoveAccountRequest, $0.ListAccountsResponse>(
            'RemoveAccount',
            removeAccount_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.RemoveAccountRequest.fromBuffer(value),
            ($0.ListAccountsResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListAccountsResponse> listAccounts_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListAccountsRequest> $request) async {
    return listAccounts($call, await $request);
  }

  $async.Future<$0.ListAccountsResponse> listAccounts(
      $grpc.ServiceCall call, $0.ListAccountsRequest request);

  $async.Future<$1.Operation> addAccount_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AddAccountRequest> $request) async {
    return addAccount($call, await $request);
  }

  $async.Future<$1.Operation> addAccount(
      $grpc.ServiceCall call, $0.AddAccountRequest request);

  $async.Future<$1.Operation> reauthAccount_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ReauthAccountRequest> $request) async {
    return reauthAccount($call, await $request);
  }

  $async.Future<$1.Operation> reauthAccount(
      $grpc.ServiceCall call, $0.ReauthAccountRequest request);

  $async.Future<$0.ListAccountsResponse> removeAccount_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RemoveAccountRequest> $request) async {
    return removeAccount($call, await $request);
  }

  $async.Future<$0.ListAccountsResponse> removeAccount(
      $grpc.ServiceCall call, $0.RemoveAccountRequest request);
}
