import 'win32_security.dart';

/// Writes protected DACLs (ADR 0015). The real one calls
/// `SetKernelObjectSecurity`; tests use a fake, and only `elevated` rows use
/// the real one with the real accounts.
abstract interface class AclWriter {
  /// Replaces the DACL of the directory at [path] with the one in [sddl],
  /// protected, without following a link at [path]. With [ownerSid] the owner
  /// is set too. Throws when the descriptor cannot be written.
  void writeProtectedDacl(String path, String sddl, {String? ownerSid});
}

/// Resolves local account names to SIDs.
abstract interface class AccountSids {
  /// The string SID of [account], or null when no such account exists.
  String? sidOf(String account);
}

class WindowsAclWriter implements AclWriter {
  const WindowsAclWriter();

  @override
  void writeProtectedDacl(String path, String sddl, {String? ownerSid}) =>
      setFileDacl(path, sddl, ownerSid: ownerSid);
}

class WindowsAccountSids implements AccountSids {
  const WindowsAccountSids();

  @override
  String? sidOf(String account) => lookupAccountSid(account);
}
