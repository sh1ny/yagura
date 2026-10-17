// This is a generated file - do not edit.
//
// Generated from yagura/v1/plugins.proto.

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

import 'plugins.pb.dart' as $0;

export 'plugins.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Plugins')
class PluginsClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  PluginsClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListPluginsResponse> listPlugins(
    $0.ListPluginsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPlugins, request, options: options);
  }

  /// Settings schema and manifest summary for rendering forms.
  $grpc.ResponseFuture<$0.PluginDetail> getPlugin(
    $0.GetPluginRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getPlugin, request, options: options);
  }

  $grpc.ResponseFuture<$0.ReloadPluginsResponse> reloadPlugins(
    $0.ReloadPluginsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reloadPlugins, request, options: options);
  }

  // method descriptors

  static final _$listPlugins =
      $grpc.ClientMethod<$0.ListPluginsRequest, $0.ListPluginsResponse>(
          '/yagura.v1.Plugins/ListPlugins',
          ($0.ListPluginsRequest value) => value.writeToBuffer(),
          $0.ListPluginsResponse.fromBuffer);
  static final _$getPlugin =
      $grpc.ClientMethod<$0.GetPluginRequest, $0.PluginDetail>(
          '/yagura.v1.Plugins/GetPlugin',
          ($0.GetPluginRequest value) => value.writeToBuffer(),
          $0.PluginDetail.fromBuffer);
  static final _$reloadPlugins =
      $grpc.ClientMethod<$0.ReloadPluginsRequest, $0.ReloadPluginsResponse>(
          '/yagura.v1.Plugins/ReloadPlugins',
          ($0.ReloadPluginsRequest value) => value.writeToBuffer(),
          $0.ReloadPluginsResponse.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Plugins')
abstract class PluginsServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Plugins';

  PluginsServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.ListPluginsRequest, $0.ListPluginsResponse>(
            'ListPlugins',
            listPlugins_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListPluginsRequest.fromBuffer(value),
            ($0.ListPluginsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetPluginRequest, $0.PluginDetail>(
        'GetPlugin',
        getPlugin_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetPluginRequest.fromBuffer(value),
        ($0.PluginDetail value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ReloadPluginsRequest, $0.ReloadPluginsResponse>(
            'ReloadPlugins',
            reloadPlugins_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ReloadPluginsRequest.fromBuffer(value),
            ($0.ReloadPluginsResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListPluginsResponse> listPlugins_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListPluginsRequest> $request) async {
    return listPlugins($call, await $request);
  }

  $async.Future<$0.ListPluginsResponse> listPlugins(
      $grpc.ServiceCall call, $0.ListPluginsRequest request);

  $async.Future<$0.PluginDetail> getPlugin_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetPluginRequest> $request) async {
    return getPlugin($call, await $request);
  }

  $async.Future<$0.PluginDetail> getPlugin(
      $grpc.ServiceCall call, $0.GetPluginRequest request);

  $async.Future<$0.ReloadPluginsResponse> reloadPlugins_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ReloadPluginsRequest> $request) async {
    return reloadPlugins($call, await $request);
  }

  $async.Future<$0.ReloadPluginsResponse> reloadPlugins(
      $grpc.ServiceCall call, $0.ReloadPluginsRequest request);
}
