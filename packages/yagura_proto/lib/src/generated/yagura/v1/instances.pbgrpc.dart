// This is a generated file - do not edit.
//
// Generated from yagura/v1/instances.proto.

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

import 'instances.pb.dart' as $0;
import 'operations.pb.dart' as $1;

export 'instances.pb.dart';

@$pb.GrpcServiceName('yagura.v1.Instances')
class InstancesClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  InstancesClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListInstancesResponse> listInstances(
    $0.ListInstancesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listInstances, request, options: options);
  }

  $grpc.ResponseFuture<$0.Instance> getInstance(
    $0.GetInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getInstance, request, options: options);
  }

  /// Snapshot of all instances, then deltas. Sends RESYNC_REQUIRED and a new
  /// snapshot when the subscriber fell more than 1000 events behind.
  $grpc.ResponseStream<$0.InstanceEvent> watchInstances(
    $0.WatchInstancesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchInstances, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.Instance> createInstance(
    $0.CreateInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createInstance, request, options: options);
  }

  $grpc.ResponseFuture<$0.Instance> updateSettings(
    $0.UpdateSettingsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateSettings, request, options: options);
  }

  $grpc.ResponseFuture<$0.Instance> setSecret(
    $0.SetSecretRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setSecret, request, options: options);
  }

  $grpc.ResponseFuture<$0.Instance> deleteSecret(
    $0.DeleteSecretRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deleteSecret, request, options: options);
  }

  /// Runs on the instance's queue; with delete_files: snapshot, marker, rows, directory.
  $grpc.ResponseFuture<$1.Operation> deleteInstance(
    $0.DeleteInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deleteInstance, request, options: options);
  }

  $grpc.ResponseFuture<$0.ImportInstanceResponse> importInstance(
    $0.ImportInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$importInstance, request, options: options);
  }

  $grpc.ResponseFuture<$0.ExportInstanceResponse> exportInstance(
    $0.ExportInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$exportInstance, request, options: options);
  }

  /// Lifecycle: each returns immediately with an operation; follow it with
  /// Operations.WatchOperation.
  $grpc.ResponseFuture<$1.Operation> install(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$install, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> update(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$update, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> validate(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$validate, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> start(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$start, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> stop(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$stop, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> restart(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$restart, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> applyConfig(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$applyConfig, request, options: options);
  }

  /// Clears error after settings were fixed or the crash cause addressed.
  $grpc.ResponseFuture<$0.Instance> acknowledge(
    $0.LifecycleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$acknowledge, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListSnapshotsResponse> listSnapshots(
    $0.GetInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listSnapshots, request, options: options);
  }

  $grpc.ResponseFuture<$1.Operation> restoreSnapshot(
    $0.RestoreSnapshotRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$restoreSnapshot, request, options: options);
  }

  /// pre_delete snapshots of deleted instances, kept 30 days.
  $grpc.ResponseFuture<$0.ListSnapshotsResponse> listOrphanSnapshots(
    $0.ListOrphanSnapshotsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listOrphanSnapshots, request, options: options);
  }

  // method descriptors

  static final _$listInstances =
      $grpc.ClientMethod<$0.ListInstancesRequest, $0.ListInstancesResponse>(
          '/yagura.v1.Instances/ListInstances',
          ($0.ListInstancesRequest value) => value.writeToBuffer(),
          $0.ListInstancesResponse.fromBuffer);
  static final _$getInstance =
      $grpc.ClientMethod<$0.GetInstanceRequest, $0.Instance>(
          '/yagura.v1.Instances/GetInstance',
          ($0.GetInstanceRequest value) => value.writeToBuffer(),
          $0.Instance.fromBuffer);
  static final _$watchInstances =
      $grpc.ClientMethod<$0.WatchInstancesRequest, $0.InstanceEvent>(
          '/yagura.v1.Instances/WatchInstances',
          ($0.WatchInstancesRequest value) => value.writeToBuffer(),
          $0.InstanceEvent.fromBuffer);
  static final _$createInstance =
      $grpc.ClientMethod<$0.CreateInstanceRequest, $0.Instance>(
          '/yagura.v1.Instances/CreateInstance',
          ($0.CreateInstanceRequest value) => value.writeToBuffer(),
          $0.Instance.fromBuffer);
  static final _$updateSettings =
      $grpc.ClientMethod<$0.UpdateSettingsRequest, $0.Instance>(
          '/yagura.v1.Instances/UpdateSettings',
          ($0.UpdateSettingsRequest value) => value.writeToBuffer(),
          $0.Instance.fromBuffer);
  static final _$setSecret =
      $grpc.ClientMethod<$0.SetSecretRequest, $0.Instance>(
          '/yagura.v1.Instances/SetSecret',
          ($0.SetSecretRequest value) => value.writeToBuffer(),
          $0.Instance.fromBuffer);
  static final _$deleteSecret =
      $grpc.ClientMethod<$0.DeleteSecretRequest, $0.Instance>(
          '/yagura.v1.Instances/DeleteSecret',
          ($0.DeleteSecretRequest value) => value.writeToBuffer(),
          $0.Instance.fromBuffer);
  static final _$deleteInstance =
      $grpc.ClientMethod<$0.DeleteInstanceRequest, $1.Operation>(
          '/yagura.v1.Instances/DeleteInstance',
          ($0.DeleteInstanceRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$importInstance =
      $grpc.ClientMethod<$0.ImportInstanceRequest, $0.ImportInstanceResponse>(
          '/yagura.v1.Instances/ImportInstance',
          ($0.ImportInstanceRequest value) => value.writeToBuffer(),
          $0.ImportInstanceResponse.fromBuffer);
  static final _$exportInstance =
      $grpc.ClientMethod<$0.ExportInstanceRequest, $0.ExportInstanceResponse>(
          '/yagura.v1.Instances/ExportInstance',
          ($0.ExportInstanceRequest value) => value.writeToBuffer(),
          $0.ExportInstanceResponse.fromBuffer);
  static final _$install =
      $grpc.ClientMethod<$0.LifecycleRequest, $1.Operation>(
          '/yagura.v1.Instances/Install',
          ($0.LifecycleRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$update = $grpc.ClientMethod<$0.LifecycleRequest, $1.Operation>(
      '/yagura.v1.Instances/Update',
      ($0.LifecycleRequest value) => value.writeToBuffer(),
      $1.Operation.fromBuffer);
  static final _$validate =
      $grpc.ClientMethod<$0.LifecycleRequest, $1.Operation>(
          '/yagura.v1.Instances/Validate',
          ($0.LifecycleRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$start = $grpc.ClientMethod<$0.LifecycleRequest, $1.Operation>(
      '/yagura.v1.Instances/Start',
      ($0.LifecycleRequest value) => value.writeToBuffer(),
      $1.Operation.fromBuffer);
  static final _$stop = $grpc.ClientMethod<$0.LifecycleRequest, $1.Operation>(
      '/yagura.v1.Instances/Stop',
      ($0.LifecycleRequest value) => value.writeToBuffer(),
      $1.Operation.fromBuffer);
  static final _$restart =
      $grpc.ClientMethod<$0.LifecycleRequest, $1.Operation>(
          '/yagura.v1.Instances/Restart',
          ($0.LifecycleRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$applyConfig =
      $grpc.ClientMethod<$0.LifecycleRequest, $1.Operation>(
          '/yagura.v1.Instances/ApplyConfig',
          ($0.LifecycleRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$acknowledge =
      $grpc.ClientMethod<$0.LifecycleRequest, $0.Instance>(
          '/yagura.v1.Instances/Acknowledge',
          ($0.LifecycleRequest value) => value.writeToBuffer(),
          $0.Instance.fromBuffer);
  static final _$listSnapshots =
      $grpc.ClientMethod<$0.GetInstanceRequest, $0.ListSnapshotsResponse>(
          '/yagura.v1.Instances/ListSnapshots',
          ($0.GetInstanceRequest value) => value.writeToBuffer(),
          $0.ListSnapshotsResponse.fromBuffer);
  static final _$restoreSnapshot =
      $grpc.ClientMethod<$0.RestoreSnapshotRequest, $1.Operation>(
          '/yagura.v1.Instances/RestoreSnapshot',
          ($0.RestoreSnapshotRequest value) => value.writeToBuffer(),
          $1.Operation.fromBuffer);
  static final _$listOrphanSnapshots = $grpc.ClientMethod<
          $0.ListOrphanSnapshotsRequest, $0.ListSnapshotsResponse>(
      '/yagura.v1.Instances/ListOrphanSnapshots',
      ($0.ListOrphanSnapshotsRequest value) => value.writeToBuffer(),
      $0.ListSnapshotsResponse.fromBuffer);
}

@$pb.GrpcServiceName('yagura.v1.Instances')
abstract class InstancesServiceBase extends $grpc.Service {
  $core.String get $name => 'yagura.v1.Instances';

  InstancesServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.ListInstancesRequest, $0.ListInstancesResponse>(
            'ListInstances',
            listInstances_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListInstancesRequest.fromBuffer(value),
            ($0.ListInstancesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetInstanceRequest, $0.Instance>(
        'GetInstance',
        getInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetInstanceRequest.fromBuffer(value),
        ($0.Instance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.WatchInstancesRequest, $0.InstanceEvent>(
        'WatchInstances',
        watchInstances_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.WatchInstancesRequest.fromBuffer(value),
        ($0.InstanceEvent value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateInstanceRequest, $0.Instance>(
        'CreateInstance',
        createInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateInstanceRequest.fromBuffer(value),
        ($0.Instance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateSettingsRequest, $0.Instance>(
        'UpdateSettings',
        updateSettings_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateSettingsRequest.fromBuffer(value),
        ($0.Instance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetSecretRequest, $0.Instance>(
        'SetSecret',
        setSecret_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetSecretRequest.fromBuffer(value),
        ($0.Instance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DeleteSecretRequest, $0.Instance>(
        'DeleteSecret',
        deleteSecret_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DeleteSecretRequest.fromBuffer(value),
        ($0.Instance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DeleteInstanceRequest, $1.Operation>(
        'DeleteInstance',
        deleteInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DeleteInstanceRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ImportInstanceRequest,
            $0.ImportInstanceResponse>(
        'ImportInstance',
        importInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ImportInstanceRequest.fromBuffer(value),
        ($0.ImportInstanceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ExportInstanceRequest,
            $0.ExportInstanceResponse>(
        'ExportInstance',
        exportInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ExportInstanceRequest.fromBuffer(value),
        ($0.ExportInstanceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $1.Operation>(
        'Install',
        install_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $1.Operation>(
        'Update',
        update_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $1.Operation>(
        'Validate',
        validate_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $1.Operation>(
        'Start',
        start_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $1.Operation>(
        'Stop',
        stop_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $1.Operation>(
        'Restart',
        restart_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $1.Operation>(
        'ApplyConfig',
        applyConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.LifecycleRequest, $0.Instance>(
        'Acknowledge',
        acknowledge_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LifecycleRequest.fromBuffer(value),
        ($0.Instance value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetInstanceRequest, $0.ListSnapshotsResponse>(
            'ListSnapshots',
            listSnapshots_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetInstanceRequest.fromBuffer(value),
            ($0.ListSnapshotsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RestoreSnapshotRequest, $1.Operation>(
        'RestoreSnapshot',
        restoreSnapshot_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RestoreSnapshotRequest.fromBuffer(value),
        ($1.Operation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListOrphanSnapshotsRequest,
            $0.ListSnapshotsResponse>(
        'ListOrphanSnapshots',
        listOrphanSnapshots_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListOrphanSnapshotsRequest.fromBuffer(value),
        ($0.ListSnapshotsResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListInstancesResponse> listInstances_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListInstancesRequest> $request) async {
    return listInstances($call, await $request);
  }

  $async.Future<$0.ListInstancesResponse> listInstances(
      $grpc.ServiceCall call, $0.ListInstancesRequest request);

  $async.Future<$0.Instance> getInstance_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetInstanceRequest> $request) async {
    return getInstance($call, await $request);
  }

  $async.Future<$0.Instance> getInstance(
      $grpc.ServiceCall call, $0.GetInstanceRequest request);

  $async.Stream<$0.InstanceEvent> watchInstances_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchInstancesRequest> $request) async* {
    yield* watchInstances($call, await $request);
  }

  $async.Stream<$0.InstanceEvent> watchInstances(
      $grpc.ServiceCall call, $0.WatchInstancesRequest request);

  $async.Future<$0.Instance> createInstance_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreateInstanceRequest> $request) async {
    return createInstance($call, await $request);
  }

  $async.Future<$0.Instance> createInstance(
      $grpc.ServiceCall call, $0.CreateInstanceRequest request);

  $async.Future<$0.Instance> updateSettings_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdateSettingsRequest> $request) async {
    return updateSettings($call, await $request);
  }

  $async.Future<$0.Instance> updateSettings(
      $grpc.ServiceCall call, $0.UpdateSettingsRequest request);

  $async.Future<$0.Instance> setSecret_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetSecretRequest> $request) async {
    return setSecret($call, await $request);
  }

  $async.Future<$0.Instance> setSecret(
      $grpc.ServiceCall call, $0.SetSecretRequest request);

  $async.Future<$0.Instance> deleteSecret_Pre($grpc.ServiceCall $call,
      $async.Future<$0.DeleteSecretRequest> $request) async {
    return deleteSecret($call, await $request);
  }

  $async.Future<$0.Instance> deleteSecret(
      $grpc.ServiceCall call, $0.DeleteSecretRequest request);

  $async.Future<$1.Operation> deleteInstance_Pre($grpc.ServiceCall $call,
      $async.Future<$0.DeleteInstanceRequest> $request) async {
    return deleteInstance($call, await $request);
  }

  $async.Future<$1.Operation> deleteInstance(
      $grpc.ServiceCall call, $0.DeleteInstanceRequest request);

  $async.Future<$0.ImportInstanceResponse> importInstance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ImportInstanceRequest> $request) async {
    return importInstance($call, await $request);
  }

  $async.Future<$0.ImportInstanceResponse> importInstance(
      $grpc.ServiceCall call, $0.ImportInstanceRequest request);

  $async.Future<$0.ExportInstanceResponse> exportInstance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ExportInstanceRequest> $request) async {
    return exportInstance($call, await $request);
  }

  $async.Future<$0.ExportInstanceResponse> exportInstance(
      $grpc.ServiceCall call, $0.ExportInstanceRequest request);

  $async.Future<$1.Operation> install_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return install($call, await $request);
  }

  $async.Future<$1.Operation> install(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$1.Operation> update_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return update($call, await $request);
  }

  $async.Future<$1.Operation> update(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$1.Operation> validate_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return validate($call, await $request);
  }

  $async.Future<$1.Operation> validate(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$1.Operation> start_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return start($call, await $request);
  }

  $async.Future<$1.Operation> start(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$1.Operation> stop_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return stop($call, await $request);
  }

  $async.Future<$1.Operation> stop(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$1.Operation> restart_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return restart($call, await $request);
  }

  $async.Future<$1.Operation> restart(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$1.Operation> applyConfig_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return applyConfig($call, await $request);
  }

  $async.Future<$1.Operation> applyConfig(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$0.Instance> acknowledge_Pre($grpc.ServiceCall $call,
      $async.Future<$0.LifecycleRequest> $request) async {
    return acknowledge($call, await $request);
  }

  $async.Future<$0.Instance> acknowledge(
      $grpc.ServiceCall call, $0.LifecycleRequest request);

  $async.Future<$0.ListSnapshotsResponse> listSnapshots_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetInstanceRequest> $request) async {
    return listSnapshots($call, await $request);
  }

  $async.Future<$0.ListSnapshotsResponse> listSnapshots(
      $grpc.ServiceCall call, $0.GetInstanceRequest request);

  $async.Future<$1.Operation> restoreSnapshot_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RestoreSnapshotRequest> $request) async {
    return restoreSnapshot($call, await $request);
  }

  $async.Future<$1.Operation> restoreSnapshot(
      $grpc.ServiceCall call, $0.RestoreSnapshotRequest request);

  $async.Future<$0.ListSnapshotsResponse> listOrphanSnapshots_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListOrphanSnapshotsRequest> $request) async {
    return listOrphanSnapshots($call, await $request);
  }

  $async.Future<$0.ListSnapshotsResponse> listOrphanSnapshots(
      $grpc.ServiceCall call, $0.ListOrphanSnapshotsRequest request);
}
