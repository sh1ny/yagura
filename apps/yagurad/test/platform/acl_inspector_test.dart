@Tags(['windows'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/platform/acl_inspector.dart';
import 'package:yagurad/src/platform/win32_paths.dart';
import 'package:yagurad/src/platform/win32_security.dart';
import 'package:yagurad/src/service/install_root_security.dart';

import '../support/temp_support.dart';

/// [sddl] with the owner and the trustee of every entry written as a full SID,
/// whichever form (alias or SID) the text used.
String _normalized(String sddl) {
  String sid(String text) => sidToString(stringToSid(text));
  final owner = RegExp(r'^O:(.+?)(?=D:|G:|S:|$)').firstMatch(sddl)![1]!;
  final rest = sddl.substring('O:$owner'.length);
  final entries = rest.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
    final parts = m[1]!.split(';');
    parts[5] = sid(parts[5]);
    return '(${parts.join(';')})';
  });
  return 'O:${sid(owner)}$entries';
}

// Read only: the real inspector over folders every Windows machine has. It
// creates nothing and changes no permissions.
void main() {
  const inspector = WindowsAclInspector();

  test('program_files_and_program_data_pass_the_ancestor_check', () {
    final programFiles = Platform.environment['ProgramFiles']!;
    final programData = Platform.environment['ProgramData']!;

    expect(
      ancestorProblems(p.join(programFiles, 'Yagura'), inspector),
      isEmpty,
    );
    expect(ancestorProblems(p.join(programData, 'Yagura'), inspector), isEmpty);
  });

  test('a_folder_in_the_users_profile_does_not', () {
    final temp = canonicalSystemTemp().path;

    expect(
      ancestorProblems(p.join(temp, 'Yagura'), inspector),
      isNotEmpty,
      reason: 'the profile belongs to a user, not to the administrators',
    );
  });

  test('a_folder_that_is_missing_is_refused', () {
    expect(
      () => inspector.inspect(
        p.join(Platform.environment['ProgramFiles']!, 'no-such-yagura'),
      ),
      throwsA(isA<PathRefused>()),
    );
  });

  test('the_security_of_a_folder_names_its_owner_and_dacl', () {
    final found = inspector.inspect(Platform.environment['ProgramFiles']!);

    expect(found.isLink, isFalse);
    expect(found.sddl, startsWith('O:'));
    expect(found.sddl, contains('D:'));
  });

  test('a_folder_is_created_with_its_owner_and_dacl_in_one_call', () {
    // Not elevated: the owner is the current user and the DACL gives it
    // full control as well. Only the form of the read-back matters here.
    final me = lookupAccountSid(Platform.environment['USERNAME']!)!;
    final temp = createCanonicalTempSync('yagurad_create_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = p.join(temp.path, 'root');
    final dacl =
        'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)'
        '(A;OICI;FA;;;$me)';

    final created = createProtectedDirectory(path, 'O:$me$dacl');
    addTearDown(created.close);

    // Windows prints some SIDs as aliases (the built-in Administrator is
    // `LA`), so the two are compared by the SIDs they name.
    expect(_normalized(created.security().sddl), _normalized('O:$me$dacl'));
    expect(Directory(path).existsSync(), isTrue);
    expect(
      () => createProtectedDirectory(path, 'O:$me$dacl'),
      throwsA(isA<PathExists>()),
    );
    expect(
      () => createProtectedDirectory(p.join(temp.path, 'a', 'b'), 'O:$me$dacl'),
      throwsA(isA<PathRefused>()),
      reason: 'the parent must exist',
    );
  });
}
