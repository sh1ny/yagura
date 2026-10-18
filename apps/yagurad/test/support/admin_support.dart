import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:yagurad/src/admin/admin_transport.dart';
import 'package:yagurad/src/admin/named_pipe.dart';
import 'package:yagurad/src/cli/run_command.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/platform/acl_writer.dart';
import 'package:yagurad/src/platform/win32_security.dart';

import 'daemon_support.dart';
import 'secret_support.dart';

/// One call of [FakeAclWriter].
class AclCall {
  AclCall(this.path, this.sddl, this.ownerSid);

  final String path;
  final String sddl;
  final String? ownerSid;

  @override
  String toString() => 'AclCall($path, $sddl, owner: $ownerSid)';
}

/// An ACL writer that records what it was asked to write and can be made to
/// fail like a volume that refuses security descriptors. It opens a
/// directory by its path (the real one opens a handle): an existing
/// directory that is not a link.
class FakeAclWriter implements AclWriter {
  final calls = <AclCall>[];

  /// Thrown by every write when set.
  Object? failure;

  @override
  ProtectedDirectory open(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw Exception('$path is not an existing directory (or is a link)');
    }
    return _FakeDirectory(this, Directory(path).resolveSymbolicLinksSync());
  }
}

class _FakeDirectory implements ProtectedDirectory {
  _FakeDirectory(this._writer, this.path);

  final FakeAclWriter _writer;

  @override
  final String path;

  @override
  void writeDacl(String sddl, {String? ownerSid}) {
    if (_writer.failure case final error?) throw error;
    _writer.calls.add(AclCall(path, sddl, ownerSid));
  }

  @override
  void close() {}
}

/// Opens directories like the daemon does, by handle, and records the writes
/// instead of making them (which needs administrator rights).
class OpeningAclWriter extends FakeAclWriter {
  @override
  ProtectedDirectory open(String path) {
    final real = const WindowsAclWriter().open(path);
    return _RecordingDirectory(this, real);
  }
}

class _RecordingDirectory implements ProtectedDirectory {
  _RecordingDirectory(this._writer, this._real);

  final FakeAclWriter _writer;
  final ProtectedDirectory _real;

  @override
  String get path => _real.path;

  @override
  void writeDacl(String sddl, {String? ownerSid}) {
    if (_writer.failure case final error?) throw error;
    _writer.calls.add(AclCall(path, sddl, ownerSid));
  }

  @override
  void close() => _real.close();
}

/// The 8.3 short form of [path] (which must exist), or null when the volume
/// makes no short names.
String? shortPath(String path) => using((arena) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final getShort = kernel
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('GetShortPathNameW');
  final buffer = arena<Uint16>(32768).cast<Utf16>();
  final length = getShort(path.toNativeUtf16(allocator: arena), buffer, 32768);
  if (length == 0 || length > 32768) return null;
  final short = buffer.toDartString(length: length);
  return short.toLowerCase() == path.toLowerCase() ? null : short;
});

/// Accounts that exist by name; the real ones are made in service mode only.
class FakeAccountSids implements AccountSids {
  FakeAccountSids([this.sids = const {}]);

  final Map<String, String> sids;

  @override
  String? sidOf(String account) => sids[account];
}

final _random = Random.secure();

/// A pipe name no other test (or installed daemon) uses.
String testPipeName() =>
    r'\\.\pipe\yagurad-admin-test-'
    '$pid-${_random.nextInt(1 << 32).toRadixString(16)}';

/// The pipe descriptor of the tests: like the real one, with the current
/// user in place of Administrators, so an ordinary run can reach it.
String currentUserPipeSddl() => 'D:P(A;;GA;;;SY)(A;;GA;;;${currentUserSid()})';

/// What a CLI run printed.
class CliResult {
  CliResult(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;

  @override
  String toString() => 'exit $code\nstdout: $out\nstderr: $err';
}

/// Runs `yagurad <arguments>` in this process against [connector].
Future<CliResult> runYagurad(
  List<String> arguments,
  AdminConnector connector,
) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(
    arguments,
    CliEnvironment(out: out, err: err, adminConnector: connector),
  );
  return CliResult(code, '$out', '$err');
}

/// A service-mode daemon serving its admin channel on a test pipe.
class AdminHarness {
  AdminHarness._(this.env, this.daemon, this.pipeName, this.acl);

  final TestEnv env;
  final Daemon daemon;
  final String pipeName;
  final FakeAclWriter acl;

  /// Starts the daemon on [env]. The pipe is the current user's; [acl] and
  /// [accounts] stand in for the Windows ACL calls.
  static Future<AdminHarness> start(
    TestEnv env, {
    FakeAclWriter? acl,
    AccountSids? accounts,
    String? pipeName,
    Future<List<InternetAddress>> Function()? hostAddresses,
    int port = apiPort,
  }) async {
    final name = pipeName ?? testPipeName();
    final writer = acl ?? FakeAclWriter();
    final daemon = await env.start(
      serviceMode: true,
      secretProtector: FakeSecretProtector(serviceSid),
      adminListener: () =>
          NamedPipeListener(name: name, sddl: currentUserPipeSddl()),
      aclWriter: writer,
      accountSids: accounts ?? FakeAccountSids(),
      hostAddresses:
          hostAddresses ??
          () async => [
            InternetAddress.loopbackIPv4,
            InternetAddress('192.168.10.20'),
            InternetAddress('10.1.2.3'),
          ],
      port: port,
    );
    return AdminHarness._(env, daemon, name, writer);
  }

  /// A connector to the daemon that trusts its server (the test process is
  /// not LocalSystem) unless [trust] is false.
  AdminConnector connector({
    bool trust = true,
    bool? elevationMissing,
    String? name,
  }) => NamedPipeConnector(
    name: name ?? pipeName,
    verifier: trust ? (_) => true : null,
    elevationMissing: elevationMissing == null ? null : () => elevationMissing,
    busyWait: const Duration(seconds: 5),
  );

  Future<CliResult> run(List<String> arguments, {AdminConnector? connector}) =>
      runYagurad(arguments, connector ?? this.connector());
}
