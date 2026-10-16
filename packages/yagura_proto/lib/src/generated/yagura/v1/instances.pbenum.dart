// This is a generated file - do not edit.
//
// Generated from yagura/v1/instances.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class InstanceState extends $pb.ProtobufEnum {
  static const InstanceState INSTANCE_STATE_UNSPECIFIED =
      InstanceState._(0, _omitEnumNames ? '' : 'INSTANCE_STATE_UNSPECIFIED');
  static const InstanceState INSTANCE_STATE_NOT_INSTALLED =
      InstanceState._(1, _omitEnumNames ? '' : 'INSTANCE_STATE_NOT_INSTALLED');
  static const InstanceState INSTANCE_STATE_INSTALLING =
      InstanceState._(2, _omitEnumNames ? '' : 'INSTANCE_STATE_INSTALLING');
  static const InstanceState INSTANCE_STATE_STOPPED =
      InstanceState._(3, _omitEnumNames ? '' : 'INSTANCE_STATE_STOPPED');
  static const InstanceState INSTANCE_STATE_STARTING =
      InstanceState._(4, _omitEnumNames ? '' : 'INSTANCE_STATE_STARTING');
  static const InstanceState INSTANCE_STATE_RUNNING =
      InstanceState._(5, _omitEnumNames ? '' : 'INSTANCE_STATE_RUNNING');
  static const InstanceState INSTANCE_STATE_STOPPING =
      InstanceState._(6, _omitEnumNames ? '' : 'INSTANCE_STATE_STOPPING');
  static const InstanceState INSTANCE_STATE_UPDATING =
      InstanceState._(7, _omitEnumNames ? '' : 'INSTANCE_STATE_UPDATING');
  static const InstanceState INSTANCE_STATE_ERROR =
      InstanceState._(8, _omitEnumNames ? '' : 'INSTANCE_STATE_ERROR');

  static const $core.List<InstanceState> values = <InstanceState>[
    INSTANCE_STATE_UNSPECIFIED,
    INSTANCE_STATE_NOT_INSTALLED,
    INSTANCE_STATE_INSTALLING,
    INSTANCE_STATE_STOPPED,
    INSTANCE_STATE_STARTING,
    INSTANCE_STATE_RUNNING,
    INSTANCE_STATE_STOPPING,
    INSTANCE_STATE_UPDATING,
    INSTANCE_STATE_ERROR,
  ];

  static final $core.List<InstanceState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 8);
  static InstanceState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const InstanceState._(super.value, super.name);
}

class Health extends $pb.ProtobufEnum {
  static const Health HEALTH_UNSPECIFIED =
      Health._(0, _omitEnumNames ? '' : 'HEALTH_UNSPECIFIED');
  static const Health HEALTH_OK =
      Health._(1, _omitEnumNames ? '' : 'HEALTH_OK');
  static const Health HEALTH_UNKNOWN =
      Health._(2, _omitEnumNames ? '' : 'HEALTH_UNKNOWN');
  static const Health HEALTH_FAILING =
      Health._(3, _omitEnumNames ? '' : 'HEALTH_FAILING');

  static const $core.List<Health> values = <Health>[
    HEALTH_UNSPECIFIED,
    HEALTH_OK,
    HEALTH_UNKNOWN,
    HEALTH_FAILING,
  ];

  static final $core.List<Health?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static Health? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Health._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
