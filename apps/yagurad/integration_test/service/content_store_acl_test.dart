@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test/support/account_support.dart';
import '../../test/support/service_rig.dart';

// host-service, "Content store protected" (design D6, ADR 0015). The service
// protects `<data>/content`: SYSTEM and Administrators full, `yagura-srv` read
// and execute, `yagura-steam` no entry. The row installs the real service, so
// it creates local accounts and a Windows service and runs only in the manual
// `elevated` workflow.

void main() {
  test('content_store_protected', tags: ['elevated'], () async {
    final rig = await ServiceRig.create(instances: 0);
    await rig.install();

    final content = p.join(rig.data, 'content');
    expect(Directory(content).existsSync(), isTrue);
    expect(Directory(p.join(content, '.staging')).existsSync(), isTrue);

    final srv = (await accountSid('yagura-srv'))!;
    final steam = (await accountSid('yagura-steam'))!;
    final sddl = await sddlOf(content);

    expect(sddl, contains(';;;SY)'));
    expect(sddl, contains(';;;BA)'));
    // Read and execute only for the game server account.
    expect(sddl, contains('0x1200a9;;;$srv)'));
    expect(sddl, isNot(contains('0x1301bf;;;$srv')));
    expect(sddl, isNot(contains(steam)));
    // What is inside inherits the same entries.
    final staging = await sddlOf(p.join(content, '.staging'));
    expect(staging, contains(srv));
    expect(staging, isNot(contains(steam)));
  });
}
