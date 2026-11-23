/// How the auth gate treats a method (design D2, D4).
enum MethodAccess {
  /// Served without a client certificate.
  exempt,

  /// Needs an enrolled device; changes nothing.
  read,

  /// Needs an enrolled device; changes state, so the call is audited.
  mutating,
}

/// Every method the daemon serves, by `package.Service/Method`. A method
/// missing here is refused by the gate (fail closed), and a test checks that
/// every method of the descriptor set is classified.
const methodAccess = <String, MethodAccess>{
  'yagura.v1.Pairing/Info': MethodAccess.exempt,
  'yagura.v1.Pairing/Enroll': MethodAccess.exempt,
  'yagura.v1.Pairing/ListDevices': MethodAccess.read,
  'yagura.v1.Pairing/RevokeDevice': MethodAccess.mutating,
  'yagura.v1.Pairing/RenameDevice': MethodAccess.mutating,
  'yagura.v1.Pairing/RenewCertificate': MethodAccess.mutating,
  'yagura.v1.System/GetInfo': MethodAccess.read,
  'yagura.v1.System/GetHealth': MethodAccess.read,
  'yagura.v1.System/ListAudit': MethodAccess.read,
  'yagura.v1.Plugins/ListPlugins': MethodAccess.read,
  'yagura.v1.Plugins/GetPlugin': MethodAccess.read,
  'yagura.v1.Plugins/ReloadPlugins': MethodAccess.mutating,
  'yagura.v1.Instances/ListInstances': MethodAccess.read,
  'yagura.v1.Instances/GetInstance': MethodAccess.read,
  'yagura.v1.Instances/WatchInstances': MethodAccess.read,
  'yagura.v1.Instances/CreateInstance': MethodAccess.mutating,
  'yagura.v1.Instances/UpdateSettings': MethodAccess.mutating,
  'yagura.v1.Instances/SetSecret': MethodAccess.mutating,
  'yagura.v1.Instances/DeleteSecret': MethodAccess.mutating,
  'yagura.v1.Instances/DeleteInstance': MethodAccess.mutating,
  'yagura.v1.Instances/ImportInstance': MethodAccess.mutating,
  'yagura.v1.Instances/ExportInstance': MethodAccess.mutating,
  'yagura.v1.Instances/Install': MethodAccess.mutating,
  'yagura.v1.Instances/Update': MethodAccess.mutating,
  'yagura.v1.Instances/Validate': MethodAccess.mutating,
  'yagura.v1.Instances/Start': MethodAccess.mutating,
  'yagura.v1.Instances/Stop': MethodAccess.mutating,
  'yagura.v1.Instances/Restart': MethodAccess.mutating,
  'yagura.v1.Instances/ApplyConfig': MethodAccess.mutating,
  'yagura.v1.Instances/Acknowledge': MethodAccess.mutating,
  'yagura.v1.Instances/ListSnapshots': MethodAccess.read,
  'yagura.v1.Instances/RestoreSnapshot': MethodAccess.mutating,
  'yagura.v1.Instances/ListOrphanSnapshots': MethodAccess.read,
  'yagura.v1.Operations/GetOperation': MethodAccess.read,
  'yagura.v1.Operations/ListOperations': MethodAccess.read,
  'yagura.v1.Operations/WatchOperation': MethodAccess.read,
  'yagura.v1.Operations/CancelOperation': MethodAccess.mutating,
  'yagura.v1.Operations/RespondToPrompt': MethodAccess.mutating,
  'yagura.v1.Operations/WatchPrompts': MethodAccess.read,
  'yagura.v1.Logs/ListSources': MethodAccess.read,
  'yagura.v1.Logs/Backlog': MethodAccess.read,
  'yagura.v1.Logs/Follow': MethodAccess.read,
  'yagura.v1.Mods/ListMods': MethodAccess.read,
  'yagura.v1.Mods/SetMods': MethodAccess.mutating,
  'yagura.v1.Mods/ApplyMods': MethodAccess.mutating,
  'yagura.v1.Mods/CheckModUpdates': MethodAccess.mutating,
  'yagura.v1.Mods/UpdateMods': MethodAccess.mutating,
  'yagura.v1.Rcon/Execute': MethodAccess.mutating,
  'yagura.v1.Rcon/Console': MethodAccess.mutating,
  'yagura.v1.Steam/ListAccounts': MethodAccess.read,
  'yagura.v1.Steam/AddAccount': MethodAccess.mutating,
  'yagura.v1.Steam/ReauthAccount': MethodAccess.mutating,
  'yagura.v1.Steam/RemoveAccount': MethodAccess.mutating,
  'yagura.v1.Firewall/ListRules': MethodAccess.read,
  'yagura.v1.Firewall/Reconcile': MethodAccess.mutating,
  'grpc.reflection.v1.ServerReflection/ServerReflectionInfo': MethodAccess.read,
  'grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo':
      MethodAccess.read,
};

/// The methods served without a client certificate.
final exemptMethods = <String>{
  for (final MapEntry(:key, :value) in methodAccess.entries)
    if (value == MethodAccess.exempt) key,
};
