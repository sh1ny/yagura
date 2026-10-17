// This is a generated file - do not edit.
//
// Generated from yagura/v1/mods.proto.

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

import 'mods.pb.dart' as $0;
import 'operations.pb.dart' as $1;

export 'mods.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Mods')
class ModsClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  ModsClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListModsResponse> listMods(
    $0.ListModsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMods, request, options: options);
  }

  /// Records changes; staging happens on next start or ApplyMods.
  $grpc.ResponseFuture<$0.ListModsResponse> setMods(
    $0.SetModsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setMods, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> applyMods(
    $0.ApplyModsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$applyMods, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> checkModUpdates(
    $0.CheckModUpdatesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$checkModUpdates, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> updateMods(
    $0.UpdateModsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMods, request, options: options);
  }

  // method descriptors

  static final _$listMods =
      $grpc.ClientMethod<$0.ListModsRequest, $0.ListModsResponse>(
          '/yagura.v1.Mods/ListMods',
          ($0.ListModsRequest value) => value.writeToBuffer(),
          $0.ListModsResponse.fromBuffer);
  static final _$setMods =
      $grpc.ClientMethod<$0.SetModsRequest, $0.ListModsResponse>(
          '/yagura.v1.Mods/SetMods',
          ($0.SetModsRequest value) => value.writeToBuffer(),
          $0.ListModsResponse.fromBuffer);
  static final _$applyMods =
      $grpc.ClientMethod<$0.ApplyModsRequest, $1.Operation>(
          '/yagura.v1.Mods/ApplyMods',
          ($0.ApplyModsRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$checkModUpdates =
      $grpc.ClientMethod<$0.CheckModUpdatesRequest, $1.Operation>(
          '/yagura.v1.Mods/CheckModUpdates',
          ($0.CheckModUpdatesRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$updateMods =
      $grpc.ClientMethod<$0.UpdateModsRequest, $1.Operation>(
          '/yagura.v1.Mods/UpdateMods',
          ($0.UpdateModsRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Mods')
abstract class ModsServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Mods';

  ModsServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ListModsRequest, $0.ListModsResponse>(
        'ListMods',
        listMods_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListModsRequest.fromBuffer(value),
        ($0.ListModsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetModsRequest, $0.ListModsResponse>(
        'SetMods',
        setMods_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetModsRequest.fromBuffer(value),
        ($0.ListModsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ApplyModsRequest, $1.Operation>(
        'ApplyMods',
        applyMods_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ApplyModsRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CheckModUpdatesRequest, $1.Operation>(
        'CheckModUpdates',
        checkModUpdates_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CheckModUpdatesRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateModsRequest, $1.Operation>(
        'UpdateMods',
        updateMods_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.UpdateModsRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListModsResponse> listMods_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListModsRequest> $request) async {
    return listMods($call, await $request);
  }

  $async.Future<$0.ListModsResponse> listMods(
      $grpc.ServiceCall call, $0.ListModsRequest request);

  $async.Future<$0.ListModsResponse> setMods_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetModsRequest> $request) async {
    return setMods($call, await $request);
  }

  $async.Future<$0.ListModsResponse> setMods(
      $grpc.ServiceCall call, $0.SetModsRequest request);

  $async.Future<$1.Operation> applyMods_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ApplyModsRequest> $request) async {
    return applyMods($call, await $request);
  }

  $async.Future<$1.Operation> applyMods(
      $grpc.ServiceCall call, $0.ApplyModsRequest request);

  $async.Future<$1.Operation> checkModUpdates_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CheckModUpdatesRequest> $request) async {
    return checkModUpdates($call, await $request);
  }

  $async.Future<$1.Operation> checkModUpdates(
      $grpc.ServiceCall call, $0.CheckModUpdatesRequest request);

  $async.Future<$1.Operation> updateMods_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdateModsRequest> $request) async {
    return updateMods($call, await $request);
  }

  $async.Future<$1.Operation> updateMods(
      $grpc.ServiceCall call, $0.UpdateModsRequest request);
}
