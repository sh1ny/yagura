import 'win32_paths.dart';

export 'win32_paths.dart' show EntrySecurity, PathExists, PathRefused;
import 'win32_security.dart';

/// A directory held open to be protected (ADR 0015).
abstract interface class ProtectedDirectory {
  /// The directory's real name: links resolved, short names expanded, the
  /// case it has on disk.
  String get path;

  /// The owner and the DACL, read on this handle: what is checked is the
  /// directory that is then changed.
  EntrySecurity security();

  /// Replaces the DACL with the one in [sddl], protected; with [ownerSid] the
  /// owner is set too. Throws when the descriptor cannot be written.
  void writeDacl(String sddl, {String? ownerSid});

  void close();
}

/// Writes protected DACLs (ADR 0015). The real one opens the directory by
/// handle and calls `SetKernelObjectSecurity` on that handle; tests use a
/// fake, and only `elevated` rows use the real one with the real accounts.
abstract interface class AclWriter {
  /// Opens the directory at [path] for protection. Throws when [path] is not
  /// an existing directory, is a link, or leads through one.
  ProtectedDirectory open(String path);

  /// Creates the directory [path] (its parent exists) with owner [ownerSid]
  /// and the DACL [dacl] from the start, and opens it. Throws [PathExists]
  /// when it exists already.
  ProtectedDirectory create(
    String path,
    String dacl, {
    required String ownerSid,
  });
}

/// Resolves local account names to SIDs.
abstract interface class AccountSids {
  /// The string SID of [account], or null when no such account exists.
  String? sidOf(String account);
}

class WindowsAclWriter implements AclWriter {
  const WindowsAclWriter();

  @override
  ProtectedDirectory open(String path) =>
      _WindowsDirectory(openDirectoryForProtection(path));

  @override
  ProtectedDirectory create(
    String path,
    String dacl, {
    required String ownerSid,
  }) => _WindowsDirectory(createProtectedDirectory(path, 'O:$ownerSid$dacl'));
}

class _WindowsDirectory implements ProtectedDirectory {
  _WindowsDirectory(this._opened);

  final OpenedDirectory _opened;

  @override
  String get path => _opened.path;

  @override
  EntrySecurity security() => _opened.security();

  @override
  void writeDacl(String sddl, {String? ownerSid}) =>
      setHandleDacl(_opened.handle, sddl, ownerSid: ownerSid);

  @override
  void close() => _opened.close();
}

class WindowsAccountSids implements AccountSids {
  const WindowsAccountSids();

  @override
  String? sidOf(String account) => lookupAccountSid(account);
}
