// This is a generated file - do not edit.
//
// Generated from yagura/v1/operations.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class OperationStatus extends $pb.ProtobufEnum {
  static const OperationStatus OPERATION_STATUS_UNSPECIFIED = OperationStatus._(
      0, _omitEnumNames ? '' : 'OPERATION_STATUS_UNSPECIFIED');
  static const OperationStatus OPERATION_STATUS_QUEUED =
      OperationStatus._(1, _omitEnumNames ? '' : 'OPERATION_STATUS_QUEUED');
  static const OperationStatus OPERATION_STATUS_RUNNING =
      OperationStatus._(2, _omitEnumNames ? '' : 'OPERATION_STATUS_RUNNING');
  static const OperationStatus OPERATION_STATUS_WAITING_FOR_INPUT =
      OperationStatus._(
          3, _omitEnumNames ? '' : 'OPERATION_STATUS_WAITING_FOR_INPUT');
  static const OperationStatus OPERATION_STATUS_SUCCEEDED =
      OperationStatus._(4, _omitEnumNames ? '' : 'OPERATION_STATUS_SUCCEEDED');
  static const OperationStatus OPERATION_STATUS_FAILED =
      OperationStatus._(5, _omitEnumNames ? '' : 'OPERATION_STATUS_FAILED');
  static const OperationStatus OPERATION_STATUS_CANCELLED =
      OperationStatus._(6, _omitEnumNames ? '' : 'OPERATION_STATUS_CANCELLED');
  static const OperationStatus OPERATION_STATUS_INTERRUPTED = OperationStatus._(
      7, _omitEnumNames ? '' : 'OPERATION_STATUS_INTERRUPTED');

  static const $core.List<OperationStatus> values = <OperationStatus>[
    OPERATION_STATUS_UNSPECIFIED,
    OPERATION_STATUS_QUEUED,
    OPERATION_STATUS_RUNNING,
    OPERATION_STATUS_WAITING_FOR_INPUT,
    OPERATION_STATUS_SUCCEEDED,
    OPERATION_STATUS_FAILED,
    OPERATION_STATUS_CANCELLED,
    OPERATION_STATUS_INTERRUPTED,
  ];

  static final $core.List<OperationStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static OperationStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const OperationStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
