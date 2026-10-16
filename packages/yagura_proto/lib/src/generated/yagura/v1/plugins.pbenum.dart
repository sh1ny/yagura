// This is a generated file - do not edit.
//
// Generated from yagura/v1/plugins.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class PluginStatus extends $pb.ProtobufEnum {
  static const PluginStatus PLUGIN_STATUS_UNSPECIFIED =
      PluginStatus._(0, _omitEnumNames ? '' : 'PLUGIN_STATUS_UNSPECIFIED');
  static const PluginStatus PLUGIN_STATUS_LOADED =
      PluginStatus._(1, _omitEnumNames ? '' : 'PLUGIN_STATUS_LOADED');
  static const PluginStatus PLUGIN_STATUS_REJECTED =
      PluginStatus._(2, _omitEnumNames ? '' : 'PLUGIN_STATUS_REJECTED');

  static const $core.List<PluginStatus> values = <PluginStatus>[
    PLUGIN_STATUS_UNSPECIFIED,
    PLUGIN_STATUS_LOADED,
    PLUGIN_STATUS_REJECTED,
  ];

  static final $core.List<PluginStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static PluginStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PluginStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
