@Tags(['windows'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/platform/acl_inspector.dart';
import 'package:yagurad/src/platform/win32_paths.dart';
import 'package:yagurad/src/platform/win32_security.dart';
import 'package:yagurad/src/service/install_root_security.dart';

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
    final temp = Directory.systemTemp.path;

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
    final temp = Directory.systemTemp.createTempSync('yagurad_create_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = p.join(temp.path, 'root');
    final dacl =
        'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)'
        '(A;OICI;FA;;;$me)';

    final created = createProtectedDirectory(path, 'O:$me$dacl');
    addTearDown(created.close);

    expect(created.security().sddl, 'O:$me$dacl');
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
