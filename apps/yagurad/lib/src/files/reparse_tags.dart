/// Which reparse points the confined file system treats as links.
///
/// A reparse point is the way Windows attaches extra behaviour to a name.
/// Most kinds redirect name resolution (symbolic links, junctions, app
/// execution aliases) and are refused. Two kinds only change how an ordinary
/// file's data is stored, so the file behaves as plain data and is accepted:
/// files compressed in place by the Windows Overlay Filter (`compact /EXE`,
/// CompactGUI) and files on a Data Deduplication volume.
///
/// Everything else is refused (fail closed): cloud-file placeholders, other
/// filter drivers' tags and tags nobody here has heard of.
library;

/// `IO_REPARSE_TAG_MOUNT_POINT`: a junction or a volume mount point.
const reparseTagMountPoint = 0xA0000003;

/// `IO_REPARSE_TAG_SYMLINK`.
const reparseTagSymlink = 0xA000000C;

/// `IO_REPARSE_TAG_APPEXECLINK`: an app execution alias.
const reparseTagAppExecLink = 0x8000001B;

/// `IO_REPARSE_TAG_WOF`: a file compressed by the Windows Overlay Filter.
const reparseTagWof = 0x80000017;

/// `IO_REPARSE_TAG_DEDUP`: a file on a Data Deduplication volume.
const reparseTagDedup = 0x80000013;

/// `IsReparseTagNameSurrogate`: the tag redirects to another named entity.
const reparseTagNameSurrogateBit = 0x20000000;

/// Whether a reparse point with [tag] is refused as a link.
///
/// Only the two data-only kinds are accepted; every name surrogate, every
/// app execution alias and every unknown tag is refused.
bool isLinkReparseTag(int tag) {
  final unsigned = tag & 0xFFFFFFFF;
  return unsigned != reparseTagWof && unsigned != reparseTagDedup;
}

/// What kind of reparse point [tag] is, for an error message.
String describeReparseTag(int tag) {
  final unsigned = tag & 0xFFFFFFFF;
  if (unsigned == reparseTagMountPoint) return 'a junction or mount point';
  if (unsigned == reparseTagSymlink) return 'a symbolic link';
  if (unsigned == reparseTagAppExecLink) return 'an app execution alias';
  if (unsigned & reparseTagNameSurrogateBit != 0) return 'a name redirection';
  return 'a reparse point of tag 0x${unsigned.toRadixString(16)}';
}
