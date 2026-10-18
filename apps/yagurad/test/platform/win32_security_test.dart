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

  test('dpapi_blob_of_an_unknown_master_key_is_a_wrong_key', () {
    // What a blob protected on another machine looks like: its master key
    // GUID (bytes 24 to 39) names a key this machine does not have. The code
    // must be read right after the call: it is NTE_BAD_KEY_STATE.
    for (var variant = 0; variant < 3; variant++) {
      final blob = dpapiProtect(Uint8List.fromList([1, 2, 3]));
      for (var i = 24; i < 40; i++) {
        blob[i] = (i * 37 + variant * 11) & 0xFF;
      }
      expect(
        () => dpapiUnprotect(blob),
        throwsA(
          isA<DpapiError>()
              .having((e) => e.isWrongKey, 'isWrongKey', isTrue)
              .having((e) => e.code, 'code', isNot(0)),
        ),
        reason: 'variant $variant',
      );
    }
  });

  test('dpapi_blob_that_is_too_short_is_not_a_wrong_key', () {
    expect(
      () => dpapiUnprotect(Uint8List(0)),
      throwsA(
        isA<DpapiError>()
            .having((e) => e.code, 'code', 87)
            .having((e) => e.isWrongKey, 'isWrongKey', isFalse),
      ),
    );
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
