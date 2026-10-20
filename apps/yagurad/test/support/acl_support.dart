import 'dart:io';
import 'dart:typed_data';

import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/files/confined_fs.dart';
import 'package:yagurad/src/files/confined_fs_portable.dart';
import 'package:yagurad/src/host/data_dir_protector.dart';
import 'package:yagurad/src/host/secret_store.dart';
import 'package:yagurad/src/instances/instance_acls.dart';
import 'package:yagurad/src/process/process_verifier.dart';
import 'package:yagurad/src/process/process_host.dart';
import 'package:yagurad/src/service/service_accounts.dart';

/// A DACL write seen by [RecordingBackend].
class SecurityWrite {
  SecurityWrite(this.path, this.sddl, this.ownerSid, this.inherit);

  final String path;
  final String sddl;
  final String? ownerSid;
  final bool inherit;

  @override
  String toString() => 'SecurityWrite($path owner=$ownerSid inherit=$inherit)';
}

/// The portable backend with the ACL calls recorded, so that the walks are
/// tested on any machine without administrator rights. [links] names entries
/// (relative paths, `/`-separated) that [list] reports as links, [owners]
/// and [hardLinks] answer for the layout marker.
class RecordingBackend extends PortableConfinedBackend {
  RecordingBackend(super.root);

  final writes = <SecurityWrite>[];
  final links = <String>{};

  /// SDDL by relative path, for `securityOf`.
  final owners = <String, String>{};
  final hardLinks = <String, int>{};

  @override
  void setSecurity(
    ConfinedPath path,
    String sddl, {
    String? ownerSid,
    bool inherit = false,
  }) => writes.add(SecurityWrite('$path', sddl, ownerSid, inherit));

  @override
  String securityOf(ConfinedPath path) => owners['$path'] ?? '';

  @override
  ConfinedEntry? stat(ConfinedPath path) {
    final entry = super.stat(path);
    if (entry == null) return null;
    return _marked(path, entry);
  }

  @override
  List<ConfinedEntry> list(ConfinedPath path) => [
    for (final entry in super.list(path))
      _marked(path.child(entry.name), entry),
  ];

  ConfinedEntry _marked(ConfinedPath path, ConfinedEntry entry) {
    final key = '$path';
    return ConfinedEntry(
      name: entry.name,
      isDirectory: entry.isDirectory,
      isLink: entry.isLink || links.contains(key),
      size: entry.size,
      modified: entry.modified,
      created: entry.created,
      links: hardLinks[key] ?? 1,
    );
  }

  /// The paths written, in order.
  List<String> get paths => [for (final w in writes) w.path];

  SecurityWrite writeFor(String path) =>
      writes.lastWhere((w) => w.path == path);
}

/// A [DataDirProtector] that records its calls and fails on demand.
class FakeDataDirProtector implements DataDirProtector {
  final events = <String>[];
  YaguraException? failOpen;
  YaguraException? failProtect;
  YaguraException? failWalk;

  /// What the directory looked like when the protector was asked to open it.
  bool? existedAtOpen;

  @override
  HeldDataDir open(String path) {
    existedAtOpen = Directory(path).existsSync();
    events.add('open');
    if (failOpen case final e?) throw e;
    return _FakeHeld(this, path);
  }

  @override
  bool walk(
    String path, {
    String? serverSid,
    String? steamSid,
    required bool complete,
  }) {
    events.add('walk:${serverSid ?? '-'}:${steamSid ?? '-'}:$complete');
    if (failWalk case final e?) throw e;
    return true;
  }
}

class _FakeHeld implements HeldDataDir {
  _FakeHeld(this._owner, this.path);

  final FakeDataDirProtector _owner;

  @override
  final String path;

  @override
  void protect() {
    _owner.events.add('protect');
    if (_owner.failProtect case final e?) throw e;
  }

  @override
  void close() => _owner.events.add('close');
}

/// An [AccountBackend] that keeps the accounts in memory.
class FakeAccountBackend implements AccountBackend {
  final passwords = <String, String>{};
  final groups = <String, Set<String>>{};
  final rights = <String, int>{};
  final calls = <String>[];
  String? failOn;

  void _step(String call) {
    calls.add(call);
    if (failOn == call) throw StateError('$call failed');
  }

  @override
  bool exists(String name) => passwords.containsKey(name);

  @override
  void create(String name, String password) {
    _step('create:$name');
    passwords[name] = password;
    groups[name] = {'Administrators'};
  }

  @override
  void setPassword(String name, String password) {
    _step('setPassword:$name');
    passwords[name] = password;
  }

  @override
  void assignLogonRights(String name) {
    _step('rights:$name');
    rights[name] = (rights[name] ?? 0) + 1;
  }

  @override
  void restrictMembership(String name) {
    _step('membership:$name');
    groups[name] = {'Users'};
  }

  @override
  String? sidOf(String name) => passwords.containsKey(name)
      ? 'S-1-5-21-1-2-3-${name.hashCode & 0xffff}'
      : null;
}

/// A [ServiceAccounts] that records `ensure` and can be made to fail.
class FakeServiceAccounts implements ServiceAccounts {
  FakeServiceAccounts({this.fails = false});

  bool fails;
  var ensured = 0;
  final sids = <String, String>{
    gameServerAccount: 'S-1-5-21-1-2-3-2001',
    steamAccount: 'S-1-5-21-1-2-3-2002',
  };

  @override
  void ensure() {
    ensured++;
    if (fails) {
      throw YaguraException(
        'service_accounts',
        'the account could not be set up',
      );
    }
  }

  @override
  String? passwordOf(String account) => 'password-of-$account';

  @override
  String? sidOf(String account) => sids[account];
}

/// An [InstanceAcls] that records the directories and can be made to fail.
class FakeInstanceAcls implements InstanceAcls {
  final applied = <String>[];
  final failing = <String, Object>{};
  int reached = 1;

  @override
  int apply(String directory) {
    applied.add(directory);
    if (failing[directory] case final e?) throw e;
    return reached;
  }
}

/// A process table for the verifier: [processes] by PID.
class FakeProcessTable implements ProcessTable {
  final processes = <int, FakeProcess>{};

  FakeProcess add(
    int pid, {
    required String user,
    required int parent,
    required int created,
    String executable = r'C:\game\server.exe',
  }) => processes[pid] = FakeProcess(
    ProcessIdentity(pid: pid, executable: executable, created: created),
    user,
    parent,
  );

  @override
  ProcessIdentity? identityOf(int pid) => processes[pid]?.identity;

  @override
  String? userOf(int pid) => processes[pid]?.user;

  @override
  int? parentOf(int pid) => processes[pid]?.parent;

  @override
  List<int> childrenOf(int pid) => [
    for (final entry in processes.entries)
      if (entry.value.parent == pid) entry.key,
  ];
}

class FakeProcess {
  FakeProcess(this.identity, this.user, this.parent);

  final ProcessIdentity identity;
  final String user;
  final int parent;
}

/// A secret store in memory.
class MemorySecretStore implements SecretStore {
  final values = <String, Uint8List>{};

  @override
  void put(
    String id,
    Uint8List value, {
    String? instanceId,
    String setting = '',
  }) => values[id] = value;

  @override
  Uint8List? get(String id) => values[id];

  @override
  bool contains(String id) => values.containsKey(id);

  @override
  void delete(String id) => values.remove(id);
}
