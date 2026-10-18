@Tags(['windows'])
library;

import 'package:test/test.dart';
import 'package:yagurad/src/admin/named_pipe.dart';
import 'package:yagurad/src/platform/win32_pipes.dart';
import 'package:yagurad/src/platform/win32_security.dart';

import '../support/admin_support.dart';

const system = 'S-1-5-18';
const administrators = 'S-1-5-32-544';
const someUser = 'S-1-5-21-1-2-3-1001';

void main() {
  bool trusted({
    String? user = system,
    String owner = system,
    List<int> pids = const [100, 100],
  }) {
    final reads = [...pids];
    return isTrustedPipeServer(
      7,
      serverPid: (_) => reads.removeAt(0),
      userOf: (_) => user,
      ownerOf: (_) => owner,
    );
  }

  test('a_server_running_as_system_that_owns_its_pipe_is_trusted', () {
    expect(trusted(), isTrue);
    expect(trusted(owner: administrators), isTrue);
  });

  test('a_pipe_owned_by_an_ordinary_user_is_not_trusted', () {
    expect(trusted(owner: someUser), isFalse);
  });

  test('a_server_process_that_is_not_system_is_not_trusted', () {
    expect(trusted(user: someUser), isFalse);
    expect(trusted(user: null), isFalse, reason: 'the process is gone');
  });

  test('a_server_pid_that_changes_while_the_handle_is_held_is_not_trusted', () {
    expect(trusted(pids: [100, 200]), isFalse);
  });

  test('the_owner_of_a_real_pipe_is_read_from_its_handle', () async {
    final echo = await _echo();
    final handle = openClientPipe(echo);
    addTearDown(() => closePipeHandle(handle));

    final owner = pipeOwnerSid(handle);

    // Made by this process: owned by this user, or by Administrators when
    // the token's default owner is that group.
    expect(owner, anyOf(currentUserSid(), administrators));
    expect(
      isTrustedPipeServer(handle),
      isFalse,
      reason: 'this process is not LocalSystem',
    );
  });
}

Future<String> _echo() async {
  final name = testPipeName();
  final listener = NamedPipeListener(name: name, sddl: currentUserPipeSddl());
  await listener.open();
  addTearDown(listener.close);
  return name;
}
