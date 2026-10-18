@Tags(['windows'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_security.dart';

void main() {
  test('dpapi_blob_round_trips', () {
    final plain = Uint8List.fromList(utf8.encode('correct horse battery'));
    final blob = dpapiProtect(plain);

    expect(blob, isNot(equals(plain)));
    expect(utf8.decode(blob, allowMalformed: true), isNot(contains('horse')));
    expect(dpapiUnprotect(blob), plain);
  });

  test('dpapi_rejects_a_damaged_blob', () {
    final blob = dpapiProtect(Uint8List.fromList([1, 2, 3]));
    blob[blob.length - 1] ^= 0xFF;
    expect(() => dpapiUnprotect(blob), throwsA(isA<Exception>()));
  });

  test('current_user_sid_is_read_from_the_process_token', () {
    final sid = currentUserSid();

    expect(sid, matches(RegExp(r'^S-1-5-\d+(-\d+)+$')));
    // `whoami /user` prints the same SID.
    final whoami = Process.runSync('whoami', ['/user', '/fo', 'csv', '/nh']);
    expect(whoami.stdout as String, contains(sid));
  });

  test('sid_converts_both_ways', () {
    final bytes = stringToSid('S-1-5-18');

    expect(bytes.first, 1, reason: 'revision');
    expect(sidToString(bytes), 'S-1-5-18');
    expect(sidToString(stringToSid(currentUserSid())), currentUserSid());
  });

  test('security_descriptor_calls_work', () {
    expect(sddlParses('D:P(A;;GA;;;SY)(A;;GA;;;BA)'), isTrue);
    expect(sddlParses('not sddl'), isFalse);

    final dir = Directory.systemTemp.createTempSync('yagurad_sddl_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'f.txt'))..writeAsStringSync('x');
    String acl() => Process.runSync('icacls', [file.path]).stdout as String;
    // A file in the temp folder inherits Administrators from its parent.
    expect(acl(), allOf(contains('Administrators'), contains('(I)')));

    setFileDacl(file.path, 'D:P(A;;GA;;;${currentUserSid()})(A;;GA;;;SY)');

    final after = acl();
    expect(after, contains(r'NT AUTHORITY\SYSTEM'));
    expect(after, isNot(contains('Administrators')));
    expect(after, isNot(contains('(I)')), reason: 'protected: no inheritance');
    expect(file.readAsStringSync(), 'x');
  });
}
