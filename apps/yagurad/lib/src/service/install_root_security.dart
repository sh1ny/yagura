import 'package:path/path.dart' as p;

import '../platform/acl_inspector.dart';

/// `NT SERVICE\TrustedInstaller`, the owner of `%ProgramFiles%`.
const trustedInstallerSid =
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464';

const _system = 'S-1-5-18';
const _administrators = 'S-1-5-32-544';
const _users = 'S-1-5-32-545';

/// The principals that may own and change the folders above an install root.
const _trusted = {_system, _administrators, trustedInstallerSid};

/// SDDL aliases of the SIDs that matter here; any other alias or SID stays as
/// it is (and is not trusted).
const _aliases = {
  'SY': _system,
  'BA': _administrators,
  'BU': _users,
  'WD': 'S-1-1-0',
  'AU': 'S-1-5-11',
  'CO': 'S-1-3-0',
  'IU': 'S-1-5-4',
  'BG': 'S-1-5-32-546',
  'PU': 'S-1-5-32-547',
  'LS': 'S-1-5-19',
  'NS': 'S-1-5-20',
  'AC': 'S-1-15-2-1',
};

const _rights = {
  'GA': 0x10000000,
  'GW': 0x40000000,
  'GR': 0x80000000,
  'GX': 0x20000000,
  'FA': 0x1f01ff,
  'FR': 0x120089,
  'FW': 0x100116,
  'FX': 0x1200a0,
  'SD': 0x10000,
  'RC': 0x20000,
  'WD': 0x40000,
  'WO': 0x80000,
  // The directory-service names SDDL also prints for the same bits.
  'CC': 0x1,
  'DC': 0x2,
  'LC': 0x4,
  'SW': 0x8,
  'RP': 0x10,
  'WP': 0x20,
  'DT': 0x40,
  'LO': 0x80,
  'CR': 0x100,
};

/// `FILE_DELETE_CHILD`, `DELETE`, `WRITE_DAC`, `WRITE_OWNER` and
/// `GENERIC_ALL`: what lets a principal rename, remove or take over a folder
/// (or, on the parent, the folder below it).
///
/// The rights to add files and folders are not in the list: they let a user
/// create new names (`C:\` gives that to Authenticated Users) but not replace
/// an existing folder in the path.
const _delete = 0x10000;
const _takeoverRights = 0x40 | 0x10000 | 0x40000 | 0x80000 | 0x10000000;

/// One access-allowed entry of a DACL.
class Ace {
  const Ace(this.flags, this.mask, this.sid);

  /// Two-letter flags (`OI`, `CI`, `IO`, ...).
  final Set<String> flags;
  final int mask;
  final String sid;
}

/// The owner and the allow entries of an SDDL string.
class ParsedSecurity {
  const ParsedSecurity({
    required this.ownerSid,
    required this.protected,
    required this.aces,
  });

  final String? ownerSid;

  /// The DACL does not inherit from the parent.
  final bool protected;
  final List<Ace> aces;
}

String _sid(String text) => _aliases[text] ?? text;

int _mask(String text) {
  if (text.startsWith('0x') || text.startsWith('0X')) {
    return int.tryParse(text.substring(2), radix: 16) ?? 0xFFFFFFFF;
  }
  var mask = 0;
  for (var i = 0; i + 2 <= text.length; i += 2) {
    // An alias that is not known is taken to grant everything.
    mask |= _rights[text.substring(i, i + 2)] ?? 0xFFFFFFFF;
  }
  return mask;
}

/// ACE types that can only take rights away or record something.
const _grantNothing = {
  'D', 'OD', 'XD', 'AU', 'OU', 'XU', 'AL', 'OL', 'XL', 'ML', 'RA', 'SP', //
  'TL', 'FL',
};

/// An entry that is not understood: it is taken to give everything to [sid]
/// (a SID nobody trusts, when none could be read).
Ace _unknown(String sid) => Ace(const {}, 0xFFFFFFFF, sid);

/// Splits the DACL part into the text of each entry (without its outer
/// parentheses). A condition holds parentheses of its own, and quoted strings
/// may hold unbalanced ones, so the split follows the nesting. A DACL that
/// does not nest properly yields `null` for the part that is left.
List<String?> _splitEntries(String text) {
  final entries = <String?>[];
  var depth = 0;
  var inString = false;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inString) {
      if (c == '"') inString = false;
      continue;
    }
    if (depth == 0 && c != '(' && c != ')' && c.trim().isNotEmpty) {
      // Text between entries is not SDDL we know.
      entries.add(null);
    } else if (c == '"' && depth > 0) {
      inString = true;
    } else if (c == '(') {
      if (depth == 0) start = i + 1;
      depth++;
    } else if (c == ')') {
      if (depth == 0) {
        entries.add(null);
        continue;
      }
      depth--;
      if (depth == 0) entries.add(text.substring(start, i));
    }
  }
  if (depth != 0) entries.add(null);
  return entries;
}

/// Reads the output of `ConvertSecurityDescriptorToStringSecurityDescriptor`
/// for the owner and the DACL (`O:BAD:PAI(A;OICI;FA;;;SY)...`). Deny and
/// audit entries are left out: they can only take rights away. Any other
/// entry that is not a plain allow (conditional, callback, object) or does not
/// parse is returned as one that gives everything, so a check on the result
/// fails closed.
ParsedSecurity parseSecurity(String sddl) {
  final owner = RegExp(r'O:(.+?)(?=D:|G:|S:|$)').firstMatch(sddl)?[1];
  final dacl = RegExp(r'D:([A-Z]*)(.*)$').firstMatch(sddl);
  // A DACL that is missing, or is `NO_ACCESS_CONTROL` (a NULL DACL: everyone
  // has full access), or has text after its flags that is not an entry, is
  // not understood and gives everything.
  final entries = dacl?[2] ?? '';
  final understood =
      dacl != null && (entries.isEmpty || entries.startsWith('('));
  final aces = <Ace>[];
  if (!understood) aces.add(_unknown('?'));
  for (final entry in understood ? _splitEntries(entries) : <String?>[]) {
    if (entry == null) {
      aces.add(_unknown('?'));
      continue;
    }
    final parts = entry.split(';');
    final sid = parts.length > 5 ? _sid(parts[5].trim()) : '?';
    if (parts.length >= 6 && _grantNothing.contains(parts[0])) continue;
    if (parts.length < 6 || parts[0] != 'A') {
      aces.add(_unknown(sid));
      continue;
    }
    final flags = {
      for (var i = 0; i + 2 <= parts[1].length; i += 2)
        parts[1].substring(i, i + 2),
    };
    aces.add(Ace(flags, _mask(parts[2]), sid));
  }
  return ParsedSecurity(
    ownerSid: owner == null ? null : _sid(owner),
    protected: (dacl?[1] ?? '').contains('P'),
    aces: aces,
  );
}

/// Whether the folder at the end of the chain is one a non-administrator can
/// not replace. Returns why not, or null.
String? _unsafeAncestor(EntrySecurity found, {required bool volumeRoot}) {
  // A volume root cannot be deleted or renamed, so DELETE on it grants
  // nothing (a default secondary drive gives Users Modify on it).
  final rights = volumeRoot ? _takeoverRights & ~_delete : _takeoverRights;
  if (found.isLink) return 'it is a link';
  final security = parseSecurity(found.sddl);
  if (security.ownerSid == null || !_trusted.contains(security.ownerSid)) {
    return 'it is owned by ${security.ownerSid ?? 'nobody'}, not SYSTEM, '
        'Administrators or TrustedInstaller';
  }
  for (final ace in security.aces) {
    if (ace.flags.contains('IO') || _trusted.contains(ace.sid)) continue;
    if (ace.mask & rights != 0) {
      return '${ace.sid} may delete, take ownership of or change the '
          'permissions of it';
    }
  }
  return null;
}

/// The folders above [root], from the drive root down, that a user who is not
/// an administrator could rename, remove or take over, each with the reason.
/// Every one is opened without following links and a link is refused. The
/// parent of [root] must exist: a folder created on the way would inherit
/// whatever its parent grants.
List<String> ancestorProblems(String root, AclInspector inspector) {
  final problems = <String>[];
  final parts = p.split(p.normalize(p.absolute(root)));
  // Only a local drive letter: over a network path the owner and the entries
  // are the server's, and the share root is any folder on it.
  if (!RegExp(r'^[A-Za-z]:\\$').hasMatch(parts.first)) {
    return [
      '$root: it is not on a local drive letter (a network path or a prefixed one)',
    ];
  }
  // parts[0] is the drive (`C:\`) or the share of a UNC path.
  var current = parts.first;
  for (var i = 0; i < parts.length - 1; i++) {
    if (i > 0) current = p.join(current, parts[i]);
    try {
      final why = _unsafeAncestor(
        inspector.inspect(current),
        volumeRoot: i == 0,
      );
      if (why != null) problems.add('$current: $why');
    } on PathRefused catch (e) {
      problems.add('$current: ${e.why}');
    }
  }
  return problems;
}

/// Whether [found] carries the protection an install gives its root: owner
/// Administrators, a DACL that inherits nothing, and exactly SYSTEM and
/// Administrators full control and Users read and execute. Only an
/// administrator can set that owner, and nobody else can add entries to the
/// folder afterwards, so its contents are the install's own.
bool hasInstallRootProtection(EntrySecurity found) {
  if (found.isLink) return false;
  final security = parseSecurity(found.sddl);
  if (security.ownerSid != _administrators || !security.protected) {
    return false;
  }
  String key(Ace a) {
    final flags = (a.flags.toList()..sort()).join();
    return '${a.sid}/$flags/${a.mask.toRadixString(16)}';
  }

  final expected = {
    '$_system/CIOI/1f01ff',
    '$_administrators/CIOI/1f01ff',
    '$_users/CIOI/1200a9',
  };
  final actual = {for (final a in security.aces) key(a)};
  return actual.length == security.aces.length &&
      actual.length == expected.length &&
      actual.containsAll(expected);
}
