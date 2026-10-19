import '../files/confined_fs.dart';
import '../files/instance_fs.dart';
import '../host/acl_layout.dart';
import '../instances/instance_roots.dart' show administratorsSid;
import '../platform/acl_writer.dart';
import '../service/service_accounts.dart' show gameServerAccount, steamAccount;

/// The ACLs of an instance directory (ADR 0015, design D6).
abstract interface class InstanceAcls {
  /// Gives [directory] the instance DACL (owner Administrators) and writes
  /// the entries its existing contents inherit, without following links.
  /// Returns the layout version reached: the current one when both service
  /// accounts exist, 0 when an entry had to be left out. Throws
  /// [AclLinkFound] for the first link met; the layout is then unchanged.
  int apply(String directory);
}

/// Writes the instance DACL through a no-follow handle on the instance
/// directory.
class HostInstanceAcls implements InstanceAcls {
  HostInstanceAcls(this.accounts, {ConfinedFs Function(String)? fs})
    : _fs = fs ?? InstanceFs.new;

  final AccountSids accounts;
  final ConfinedFs Function(String directory) _fs;

  @override
  int apply(String directory) {
    final server = accounts.sidOf(gameServerAccount);
    final steam = accounts.sidOf(steamAccount);
    final fs = _fs(directory);
    fs.setSecurity(
      '',
      instanceDacl(serverSid: server, steamSid: steam),
      ownerSid: administratorsSid,
    );
    inheritBelow(fs, '', instanceInherited(serverSid: server, steamSid: steam));
    return server != null && steam != null ? currentAclLayout : 0;
  }
}
