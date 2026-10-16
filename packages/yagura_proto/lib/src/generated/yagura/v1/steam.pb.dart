// This is a generated file - do not edit.
//
// Generated from yagura/v1/steam.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class SteamAccount extends $pb.GeneratedMessage {
  factory SteamAccount({
    $core.String? id,
    $core.String? username,
    $core.String? status,
    $core.bool? passwordRemembered,
    $2.Timestamp? lastLoginAt,
    $core.Iterable<$core.String>? usedByInstanceIds,
  }) {
    final result = SteamAccount._();
    if (id != null) result.id = id;
    if (username != null) result.username = username;
    if (status != null) result.status = status;
    if (passwordRemembered != null)
      result.passwordRemembered = passwordRemembered;
    if (lastLoginAt != null) result.lastLoginAt = lastLoginAt;
    if (usedByInstanceIds != null)
      result.usedByInstanceIds.addAll(usedByInstanceIds);
    return result;
  }

  SteamAccount._();

  factory SteamAccount.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SteamAccount()..mergeFromBuffer(data, registry);
  factory SteamAccount.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SteamAccount()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SteamAccount',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: SteamAccount.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'status')
    ..aOB(4, _omitFieldNames ? '' : 'passwordRemembered')
    ..aOM<$2.Timestamp>(5, _omitFieldNames ? '' : 'lastLoginAt',
        subBuilder: $2.Timestamp.$_createMessage)
    ..pPS(6, _omitFieldNames ? '' : 'usedByInstanceIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SteamAccount clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SteamAccount copyWith(void Function(SteamAccount) updates) =>
      super.copyWith((message) => updates(message as SteamAccount))
          as SteamAccount;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SteamAccount() / SteamAccount.new instead')
  static SteamAccount create() => SteamAccount._();
  static $pb.GeneratedMessage $_createMessage() => SteamAccount._();
  @$core.override
  SteamAccount createEmptyInstance() => SteamAccount._();
  @$core.pragma('dart2js:noInline')
  static SteamAccount getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SteamAccount>(
          SteamAccount.$_createMessage);
  static SteamAccount? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get status => $_getSZ(2);
  @$pb.TagNumber(3)
  set status($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get passwordRemembered => $_getBF(3);
  @$pb.TagNumber(4)
  set passwordRemembered($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPasswordRemembered() => $_has(3);
  @$pb.TagNumber(4)
  void clearPasswordRemembered() => $_clearField(4);

  @$pb.TagNumber(5)
  $2.Timestamp get lastLoginAt => $_getN(4);
  @$pb.TagNumber(5)
  set lastLoginAt($2.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasLastLoginAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearLastLoginAt() => $_clearField(5);
  @$pb.TagNumber(5)
  $2.Timestamp ensureLastLoginAt() => $_ensure(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get usedByInstanceIds => $_getList(5);
}

class ListAccountsRequest extends $pb.GeneratedMessage {
  factory ListAccountsRequest() => ListAccountsRequest._();

  ListAccountsRequest._();

  factory ListAccountsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAccountsRequest()..mergeFromBuffer(data, registry);
  factory ListAccountsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAccountsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListAccountsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListAccountsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAccountsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAccountsRequest copyWith(void Function(ListAccountsRequest) updates) =>
      super.copyWith((message) => updates(message as ListAccountsRequest))
          as ListAccountsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListAccountsRequest() / ListAccountsRequest.new instead')
  static ListAccountsRequest create() => ListAccountsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListAccountsRequest._();
  @$core.override
  ListAccountsRequest createEmptyInstance() => ListAccountsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListAccountsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListAccountsRequest>(
          ListAccountsRequest.$_createMessage);
  static ListAccountsRequest? _defaultInstance;
}

class ListAccountsResponse extends $pb.GeneratedMessage {
  factory ListAccountsResponse({
    $core.Iterable<SteamAccount>? accounts,
  }) {
    final result = ListAccountsResponse._();
    if (accounts != null) result.accounts.addAll(accounts);
    return result;
  }

  ListAccountsResponse._();

  factory ListAccountsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAccountsResponse()..mergeFromBuffer(data, registry);
  factory ListAccountsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListAccountsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListAccountsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ListAccountsResponse.$_createMessage)
    ..pPM<SteamAccount>(1, _omitFieldNames ? '' : 'accounts',
        subBuilder: SteamAccount.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAccountsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAccountsResponse copyWith(void Function(ListAccountsResponse) updates) =>
      super.copyWith((message) => updates(message as ListAccountsResponse))
          as ListAccountsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListAccountsResponse() / ListAccountsResponse.new instead')
  static ListAccountsResponse create() => ListAccountsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListAccountsResponse._();
  @$core.override
  ListAccountsResponse createEmptyInstance() => ListAccountsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListAccountsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListAccountsResponse>(
          ListAccountsResponse.$_createMessage);
  static ListAccountsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SteamAccount> get accounts => $_getList(0);
}

class AddAccountRequest extends $pb.GeneratedMessage {
  factory AddAccountRequest({
    $core.String? username,
    $core.String? password,
    $core.bool? rememberPassword,
  }) {
    final result = AddAccountRequest._();
    if (username != null) result.username = username;
    if (password != null) result.password = password;
    if (rememberPassword != null) result.rememberPassword = rememberPassword;
    return result;
  }

  AddAccountRequest._();

  factory AddAccountRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddAccountRequest()..mergeFromBuffer(data, registry);
  factory AddAccountRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AddAccountRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AddAccountRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: AddAccountRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..aOB(3, _omitFieldNames ? '' : 'rememberPassword')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddAccountRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddAccountRequest copyWith(void Function(AddAccountRequest) updates) =>
      super.copyWith((message) => updates(message as AddAccountRequest))
          as AddAccountRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AddAccountRequest() / AddAccountRequest.new instead')
  static AddAccountRequest create() => AddAccountRequest._();
  static $pb.GeneratedMessage $_createMessage() => AddAccountRequest._();
  @$core.override
  AddAccountRequest createEmptyInstance() => AddAccountRequest._();
  @$core.pragma('dart2js:noInline')
  static AddAccountRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AddAccountRequest>(
          AddAccountRequest.$_createMessage);
  static AddAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get rememberPassword => $_getBF(2);
  @$pb.TagNumber(3)
  set rememberPassword($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRememberPassword() => $_has(2);
  @$pb.TagNumber(3)
  void clearRememberPassword() => $_clearField(3);
}

class ReauthAccountRequest extends $pb.GeneratedMessage {
  factory ReauthAccountRequest({
    $core.String? accountId,
    $core.String? password,
    $core.bool? rememberPassword,
  }) {
    final result = ReauthAccountRequest._();
    if (accountId != null) result.accountId = accountId;
    if (password != null) result.password = password;
    if (rememberPassword != null) result.rememberPassword = rememberPassword;
    return result;
  }

  ReauthAccountRequest._();

  factory ReauthAccountRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReauthAccountRequest()..mergeFromBuffer(data, registry);
  factory ReauthAccountRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReauthAccountRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReauthAccountRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: ReauthAccountRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..aOB(3, _omitFieldNames ? '' : 'rememberPassword')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReauthAccountRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReauthAccountRequest copyWith(void Function(ReauthAccountRequest) updates) =>
      super.copyWith((message) => updates(message as ReauthAccountRequest))
          as ReauthAccountRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReauthAccountRequest() / ReauthAccountRequest.new instead')
  static ReauthAccountRequest create() => ReauthAccountRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReauthAccountRequest._();
  @$core.override
  ReauthAccountRequest createEmptyInstance() => ReauthAccountRequest._();
  @$core.pragma('dart2js:noInline')
  static ReauthAccountRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReauthAccountRequest>(
          ReauthAccountRequest.$_createMessage);
  static ReauthAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get rememberPassword => $_getBF(2);
  @$pb.TagNumber(3)
  set rememberPassword($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRememberPassword() => $_has(2);
  @$pb.TagNumber(3)
  void clearRememberPassword() => $_clearField(3);
}

class RemoveAccountRequest extends $pb.GeneratedMessage {
  factory RemoveAccountRequest({
    $core.String? accountId,
  }) {
    final result = RemoveAccountRequest._();
    if (accountId != null) result.accountId = accountId;
    return result;
  }

  RemoveAccountRequest._();

  factory RemoveAccountRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RemoveAccountRequest()..mergeFromBuffer(data, registry);
  factory RemoveAccountRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RemoveAccountRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RemoveAccountRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'yagura.v1'),
      createEmptyInstance: RemoveAccountRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveAccountRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveAccountRequest copyWith(void Function(RemoveAccountRequest) updates) =>
      super.copyWith((message) => updates(message as RemoveAccountRequest))
          as RemoveAccountRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RemoveAccountRequest() / RemoveAccountRequest.new instead')
  static RemoveAccountRequest create() => RemoveAccountRequest._();
  static $pb.GeneratedMessage $_createMessage() => RemoveAccountRequest._();
  @$core.override
  RemoveAccountRequest createEmptyInstance() => RemoveAccountRequest._();
  @$core.pragma('dart2js:noInline')
  static RemoveAccountRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RemoveAccountRequest>(
          RemoveAccountRequest.$_createMessage);
  static RemoveAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
