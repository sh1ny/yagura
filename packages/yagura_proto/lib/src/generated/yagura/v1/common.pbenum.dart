// This is a generated file - do not edit.
//
// Generated from yagura/v1/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class Protocol extends $pb.ProtobufEnum {
  static const Protocol PROTOCOL_UNSPECIFIED =
      Protocol._(0, _omitEnumNames ? '' : 'PROTOCOL_UNSPECIFIED');
  static const Protocol PROTOCOL_UDP =
      Protocol._(1, _omitEnumNames ? '' : 'PROTOCOL_UDP');
  static const Protocol PROTOCOL_TCP =
      Protocol._(2, _omitEnumNames ? '' : 'PROTOCOL_TCP');
  static const Protocol PROTOCOL_BOTH =
      Protocol._(3, _omitEnumNames ? '' : 'PROTOCOL_BOTH');

  static const $core.List<Protocol> values = <Protocol>[
    PROTOCOL_UNSPECIFIED,
    PROTOCOL_UDP,
    PROTOCOL_TCP,
    PROTOCOL_BOTH,
  ];

  static final $core.List<Protocol?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static Protocol? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Protocol._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
