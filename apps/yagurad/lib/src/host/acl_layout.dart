import 'dart:convert';
import 'dart:typed_data';

import '../files/confined_fs.dart';
import '../service/install_root_security.dart' show parseSecurity;
import '../instances/instance_roots.dart' show administratorsSid, rootDaclSddl;

/// The version of the ACL layout this daemon writes (ADR 0015). The data
/// directory records it in `<data>/acl-layout`, an instance in
/// `instances.acl_layout`; both are walked again while they are below it.
const currentAclLayout = 1;

/// The file in the data directory that records the layout version.
const aclLayoutFile = 'acl-layout';

/// The directory of the content store in the data directory.
const contentStoreName = 'content';

/// `SYNCHRONIZE | READ_CONTROL | DELETE | FILE_GENERIC_READ/WRITE/EXECUTE`
/// without `WRITE_DAC` and `WRITE_OWNER`: what the SDDL alias `0x1301bf` is.
const modifyMask = '0x1301bf';

/// Read and execute: `FILE_GENERIC_READ | FILE_GENERIC_EXECUTE`.
const readExecuteMask = '0x1200a9';

/// On an instance directory itself: read and execute, list, add file, add
/// subdirectory and `FILE_DELETE_CHILD`, but not `DELETE`, so the account can
/// neither rename nor remove the directory (ADR 0015).
const instanceDirectoryMask = '0x1200ef';

/// One allow entry that is added to SYSTEM and Administrators.
class AclEntry {
  const AclEntry(this.mask, this.sid);

  final String mask;
  final String sid;
}

/// The SID of the SYSTEM account.
const systemSid = 'S-1-5-18';

String _pair(String flags) => '(A;$flags;FA;;;SY)(A;$flags;FA;;;BA)';

/// The protected DACL of the data directory itself: SYSTEM and
/// Administrators, inherited by what is created below.
String dataDirectoryDacl() => 'D:P${_pair('OICI')}';

/// The protected DACL of `<data>/steamcmd`: `yagura-steam` modify.
String steamcmdDacl(String? steamSid) =>
    'D:P${_pair('OICI')}'
    '${steamSid == null ? '' : '(A;OICI;$modifyMask;;;$steamSid)'}';

/// The protected DACL of the content store: `yagura-srv` read and execute.
String contentDacl(String? serverSid) =>
    'D:P${_pair('OICI')}'
    '${serverSid == null ? '' : '(A;OICI;$readExecuteMask;;;$serverSid)'}';

/// The protected DACL of an instance directory (ADR 0015): SYSTEM and
/// Administrators full; for each account that exists one entry on the
/// directory itself ([instanceDirectoryMask]) and one `(OI)(CI)(IO)` modify
/// entry for what is inside.
String instanceDacl({String? serverSid, String? steamSid}) =>
    'D:P${_pair('OICI')}'
    '${_instanceEntries(serverSid)}${_instanceEntries(steamSid)}';

String _instanceEntries(String? sid) => sid == null
    ? ''
    : '(A;;$instanceDirectoryMask;;;$sid)(A;OICIIO;$modifyMask;;;$sid)';

/// The entries an instance's contents inherit from [instanceDacl].
List<AclEntry> instanceInherited({String? serverSid, String? steamSid}) => [
  if (serverSid != null) AclEntry(modifyMask, serverSid),
  if (steamSid != null) AclEntry(modifyMask, steamSid),
];

/// The DACL of an existing child that takes its entries from the parent's
/// (SYSTEM, Administrators and [extra]); the walk writes these itself because
/// no call propagates them (ADR 0015).
String inheritedDacl({
  required bool directory,
  List<AclEntry> extra = const [],
}) {
  final flags = directory ? 'OICIID' : 'ID';
  return 'D:AI${_pair(flags)}'
      '${[for (final e in extra) '(A;$flags;${e.mask};;;${e.sid})'].join()}';
}

/// Whether a walk must treat [entry] as a link: a reparse point, or a file
/// with more than one name (setting its DACL would change the other name's
/// target too).
bool _isLinkLike(ConfinedEntry entry) =>
    entry.isLink || (!entry.isDirectory && entry.links != 1);

/// A link met by a walk.
class AclLinkFound implements Exception {
  const AclLinkFound(this.path, {this.hardLinks = false});

  /// The walk's [entry] at [path], which [_isLinkLike] found.
  factory AclLinkFound.of(String path, ConfinedEntry entry) =>
      AclLinkFound(path, hardLinks: !entry.isLink);

  /// Whether it is a file with several names (hard links) rather than a
  /// symbolic link or junction: it looks like any file to an administrator.
  final bool hardLinks;

  /// How to name it in a message.
  String get kind => hardLinks
      ? 'a file with several names (hard links)'
      : 'a link or junction (reparse point)';

  /// Relative to the walked root.
  final String path;

  @override
  String toString() => 'AclLinkFound($path)';
}

/// Writes the inherited entries on everything below [directory] (relative to
/// the root of [fs]; `''` is the root), one handle at a time and without
/// following links, with owner Administrators. A link (or a file with several names) met
/// anywhere throws [AclLinkFound] for the first one, and nothing under it is touched.
void inheritBelow(
  ConfinedFs fs,
  String directory,
  List<AclEntry> extra, {
  void Function(String path)? visited,
}) {
  for (final child in fs.list(directory)) {
    final path = directory.isEmpty ? child.name : '$directory/${child.name}';
    if (_isLinkLike(child)) throw AclLinkFound.of(path, child);
    fs.setSecurity(
      path,
      inheritedDacl(directory: child.isDirectory, extra: extra),
      ownerSid: administratorsSid,
      inherit: true,
    );
    visited?.call(path);
    if (child.isDirectory) {
      inheritBelow(fs, path, extra, visited: visited);
    }
  }
}

/// The layout version recorded in the data directory [fs] is rooted in. It is
/// 0 unless `acl-layout` opens without following a link, is a regular file
/// with one hard link and is owned by SYSTEM or Administrators: before the
/// first service start any `Users` process could have created it.
int readAclLayout(ConfinedFs fs) {
  try {
    final entry = fs.stat(aclLayoutFile);
    if (entry == null || entry.isDirectory || entry.isLink) return 0;
    if (entry.links != 1) return 0;
    final owner = parseSecurity(fs.securityOf(aclLayoutFile)).ownerSid;
    if (owner != systemSid && owner != administratorsSid) return 0;
    final text = utf8.decode(
      fs.readBytes(aclLayoutFile, maxBytes: 64),
      allowMalformed: true,
    );
    return int.tryParse(text.trim()) ?? 0;
  } on Object {
    return 0;
  }
}

/// Records [version] atomically; the data directory is SYSTEM and
/// Administrators only by now.
void writeAclLayout(ConfinedFs fs, int version) {
  fs.writeAtomic(aclLayoutFile, Uint8List.fromList(utf8.encode('$version\n')));
}

/// Protects the contents of the data directory that [fs] is rooted in, once
/// per layout version: owner Administrators and the entries each child
/// inherits from its parent, `<data>/instances` and the two special folders
/// with their explicit DACLs. `<data>/instances` is not entered: its
/// instance directories have their own DACL and walk.
///
/// A link met throws [AclLinkFound]. The version is recorded only with
/// [complete], that is when both accounts exist and so every entry is in.
/// Returns whether the walk ran.
bool walkDataDirectory(
  ConfinedFs fs, {
  String? serverSid,
  String? steamSid,
  required bool complete,
  void Function(String path)? visited,
}) {
  if (readAclLayout(fs) >= currentAclLayout) return false;
  void explicit(String path, String dacl) {
    fs.setSecurity(path, dacl, ownerSid: administratorsSid);
    visited?.call(path);
  }

  for (final child in fs.list('')) {
    if (_isLinkLike(child)) throw AclLinkFound.of(child.name, child);
    final name = child.name;
    final lower = name.toLowerCase();
    if (child.isDirectory && lower == 'instances') {
      explicit(name, rootDaclSddl(serverSid: serverSid, steamSid: steamSid));
    } else if (child.isDirectory && lower == 'steamcmd') {
      explicit(name, steamcmdDacl(steamSid));
      inheritBelow(fs, name, [
        if (steamSid != null) AclEntry(modifyMask, steamSid),
      ], visited: visited);
    } else if (child.isDirectory && lower == contentStoreName) {
      explicit(name, contentDacl(serverSid));
      inheritBelow(fs, name, [
        if (serverSid != null) AclEntry(readExecuteMask, serverSid),
      ], visited: visited);
    } else {
      fs.setSecurity(
        name,
        inheritedDacl(directory: child.isDirectory),
        ownerSid: administratorsSid,
        inherit: true,
      );
      visited?.call(name);
      if (child.isDirectory) inheritBelow(fs, name, const [], visited: visited);
    }
  }
  if (complete) writeAclLayout(fs, currentAclLayout);
  return true;
}
