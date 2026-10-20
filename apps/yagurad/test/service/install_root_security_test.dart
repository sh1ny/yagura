import 'package:test/test.dart';
import 'package:yagurad/src/platform/acl_inspector.dart';
import 'package:yagurad/src/service/install_root_security.dart';
import 'package:yagurad/src/service/service_installer.dart';

class _Inspector implements AclInspector {
  _Inspector(this.known);

  final Map<String, EntrySecurity> known;

  @override
  EntrySecurity inspect(String path) =>
      known[path] ?? (throw PathRefused(path, 'cannot be opened'));
}

EntrySecurity _dir(String sddl) => EntrySecurity(isLink: false, sddl: sddl);

// What a Windows install gives these folders (abridged).
const _driveRoot =
    'O:S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    'D:PAI(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)(A;OICI;0x1200a9;;;BU)'
    '(A;OICIIO;SDGXGWGR;;;AU)(A;;LC;;;AU)'
    '(A;;0x1000a1;;;S-1-15-3-65536-1888954469-739942743-1668119174)';
// C:\ProgramData: Users may create folders (DC, LC, RP, CR, CC) in it.
const _programData =
    'O:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICIIO;GA;;;CO)'
    '(A;OICI;0x1200a9;;;BU)(A;CI;DCLCRPCR;;;BU)';
// D:\ of a volume Windows formatted: Authenticated Users have Modify
// (0x1301bf, which includes DELETE) on the root itself.
const _secondaryDrive =
    'O:SYD:(A;;FA;;;BA)(A;OICIIO;GA;;;BA)(A;;FA;;;SY)(A;OICIIO;GA;;;SY)'
    '(A;;0x1301bf;;;AU)(A;OICIIO;SDGXGWGR;;;AU)(A;;0x1200a9;;;BU)'
    '(A;OICIIO;GXGR;;;BU)';
const _programFiles =
    'O:S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    'D:PAI(A;;FA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-'
    '2271478464)(A;CIIO;GA;;;S-1-5-80-956008885-3418522649-1831038044-'
    '1853292631-2271478464)(A;;FA;;;SY)(A;OICIIO;GA;;;SY)(A;;FA;;;BA)'
    '(A;OICIIO;GA;;;BA)(A;;0x1200a9;;;BU)(A;OICIIO;GXGR;;;BU)'
    '(A;OICIIO;GA;;;CO)';
const _userMade = 'O:S-1-5-21-1-2-3-1001D:(A;OICI;FA;;;S-1-5-21-1-2-3-1001)';

void main() {
  group('parseSecurity', () {
    test('reads_the_owner_the_flags_and_the_rights', () {
      final parsed = parseSecurity(
        'O:BAD:P(A;OICI;0x1200a9;;;BU)(A;;FA;;;SY)(D;;FA;;;WD)',
      );

      expect(parsed.ownerSid, 'S-1-5-32-544');
      expect(parsed.protected, isTrue);
      expect(parsed.aces, hasLength(2), reason: 'a deny entry is not a grant');
      expect(parsed.aces.first.sid, 'S-1-5-32-545');
      expect(parsed.aces.first.mask, 0x1200a9);
      expect(parsed.aces.first.flags, {'OI', 'CI'});
      expect(parsed.aces.last.mask, 0x1f01ff);
    });
  });

  group('parseSecurity with other entries', () {
    test('a_condition_with_parentheses_is_one_entry', () {
      final parsed = parseSecurity(
        'O:BAD:(XA;;FA;;;WD;(Member_of {SID(BA)}))(A;;FA;;;SY)',
      );

      expect(parsed.aces, hasLength(2));
      expect(parsed.aces.first.sid, 'S-1-1-0');
      expect(parsed.aces.first.mask, 0xFFFFFFFF, reason: "fail closed");
      expect(parsed.aces.last.sid, 'S-1-5-18');
    });

    test('a_parenthesis_in_a_quoted_string_does_not_end_the_entry', () {
      final parsed = parseSecurity(
        'O:BAD:(XA;;FA;;;WD;(@User.Name == "a)b"))(A;;FA;;;SY)',
      );

      expect(parsed.aces, hasLength(2));
    });

    test('an_object_entry_grants_everything_to_its_sid', () {
      final parsed = parseSecurity('O:BAD:(OA;;CC;guid;;WD)');

      expect(parsed.aces.single.sid, 'S-1-1-0');
      expect(parsed.aces.single.mask, 0xFFFFFFFF);
    });

    test('an_entry_that_does_not_parse_grants_everything', () {
      final parsed = parseSecurity('O:BAD:(A;;FA)(A;;FA;;;SY');

      expect(parsed.aces, hasLength(2));
      expect(parsed.aces.every((a) => a.mask == 0xFFFFFFFF), isTrue);
    });

    for (final text in [
      'O:BAD:NO_ACCESS_CONTROL',
      'O:BAD:PNO_ACCESS_CONTROL',
      'O:BA',
      'O:BAD:P(A;;FA;;;SY)garbage',
    ]) {
      test('a_null_or_missing_dacl_grants_everything_$text', () {
        final parsed = parseSecurity(text);

        expect(
          parsed.aces.any((a) => a.mask == 0xFFFFFFFF),
          isTrue,
          reason: text,
        );
      });
    }

    test('an_empty_dacl_grants_nothing', () {
      expect(parseSecurity('O:BAD:P').aces, isEmpty);
    });

    test('deny_and_audit_entries_grant_nothing', () {
      final parsed = parseSecurity('O:BAD:(D;;FA;;;WD)(XD;;FA;;;WD;(x))');

      expect(parsed.aces, isEmpty);
    });
  });

  group('ancestorProblems', () {
    final windows = {
      r'C:\': _dir(_driveRoot),
      r'C:\Program Files': _dir(_programFiles),
    };

    test('program_files_passes', () {
      expect(
        ancestorProblems(r'C:\Program Files\Yagura', _Inspector(windows)),
        isEmpty,
      );
    });

    test('the_documented_example_on_a_secondary_drive_passes', () {
      expect(
        ancestorProblems(
          r'D:\yagura-test',
          _Inspector({r'D:\': _dir(_secondaryDrive)}),
        ),
        isEmpty,
        reason: 'DELETE on a volume root grants nothing: it cannot be removed',
      );
    });

    for (final (name, mask) in [
      ('delete_tree', 'DT'),
      ('write_dac', 'WD'),
      ('write_owner', 'WO'),
      ('generic_all', 'GA'),
    ]) {
      test('${name}_on_a_drive_root_is_still_refused', () {
        expect(
          ancestorProblems(
            r'D:\yagura-test',
            _Inspector({r'D:\': _dir('$_secondaryDrive(A;;$mask;;;AU)')}),
          ),
          isNotEmpty,
        );
      });
    }

    test('delete_on_a_folder_below_the_drive_root_is_refused', () {
      expect(
        ancestorProblems(
          r'D:\apps\yagura',
          _Inspector({
            r'D:\': _dir(_secondaryDrive),
            r'D:\apps': _dir('O:BAD:(A;;0x1301bf;;;AU)(A;;FA;;;BA)'),
          }),
        ),
        isNotEmpty,
      );
    });

    for (final (name, ace) in [
      ('conditional', '(XA;OICI;FA;;;AU;(Member_of {SID(BA)}))'),
      ('object', '(OA;;CC;00000000-0000-0000-0000-000000000000;;AU)'),
      ('unbalanced', '(A;;FA;;;AU'),
      ('unknown_type', '(ZA;;FA;;;AU)'),
    ]) {
      test('a_${name}_entry_for_users_is_refused', () {
        expect(
          ancestorProblems(
            r'D:\apps\yagura',
            _Inspector({
              r'D:\': _dir(_secondaryDrive),
              r'D:\apps': _dir('O:BAD:(A;;FA;;;BA)$ace'),
            }),
          ),
          isNotEmpty,
        );
      });
    }

    test('a_conditional_entry_for_system_is_fine', () {
      expect(
        ancestorProblems(
          r'D:\apps\yagura',
          _Inspector({
            r'D:\': _dir(_secondaryDrive),
            r'D:\apps': _dir('O:BAD:(XA;;FA;;;SY;(Member_of {SID(BA)}))'),
          }),
        ),
        isEmpty,
      );
    });

    for (final text in ['O:BAD:NO_ACCESS_CONTROL', 'O:BA']) {
      test('an_ancestor_with_no_dacl_is_refused_$text', () {
        expect(
          ancestorProblems(
            r'D:\apps\yagura',
            _Inspector({r'D:\': _dir(_secondaryDrive), r'D:\apps': _dir(text)}),
          ),
          isNotEmpty,
        );
      });
    }

    for (final root in [
      r'\\server\share\yagura',
      r'\\?\UNC\server\share\yagura',
      r'\\?\C:\Program Files\Yagura',
    ]) {
      test('a_path_not_on_a_drive_letter_is_refused_$root', () {
        final problems = ancestorProblems(
          root,
          _Inspector({...windows, r'\\server\share': _dir(_secondaryDrive)}),
        );

        expect(problems, isNotEmpty);
        expect(problems.first, contains('drive'));
      });
    }

    test('program_data_passes', () {
      expect(
        ancestorProblems(
          r'C:\ProgramData\Yagura',
          _Inspector({...windows, r'C:\ProgramData': _dir(_programData)}),
        ),
        isEmpty,
      );
    });

    test('delete_tree_is_refused', () {
      expect(
        ancestorProblems(
          r'C:\data\yagura',
          _Inspector({...windows, r'C:\data': _dir('O:BAD:(A;;DT;;;BU)')}),
        ),
        isNotEmpty,
      );
    });

    test('a_folder_a_user_owns_is_refused', () {
      final problems = ancestorProblems(
        r'C:\games\yagura',
        _Inspector({...windows, r'C:\games': _dir(_userMade)}),
      );

      expect(problems.single, contains(r'C:\games'));
      expect(problems.single, contains('S-1-5-21-1-2-3-1001'));
    });

    test('a_link_is_refused', () {
      final problems = ancestorProblems(
        r'C:\Program Files\Yagura',
        _Inspector({
          ...windows,
          r'C:\Program Files': const EntrySecurity(
            isLink: true,
            sddl: _programFiles,
          ),
        }),
      );

      expect(problems.single, contains('link'));
    });

    for (final (name, mask) in [
      ('delete', 'SD'),
      ('delete_child', '0x40'),
      ('write_dac', 'WD'),
      ('write_owner', 'WO'),
      ('generic_all', 'GA'),
      ('full_control', 'FA'),
    ]) {
      test('a_user_grant_of_${name}_is_refused', () {
        final problems = ancestorProblems(
          r'C:\data\yagura',
          _Inspector({
            ...windows,
            r'C:\data': _dir('O:BAD:(A;;$mask;;;BU)(A;;FA;;;BA)'),
          }),
        );

        expect(problems.single, contains(r'C:\data'));
      });
    }

    test('an_inherit_only_entry_does_not_count_for_the_folder_itself', () {
      expect(
        ancestorProblems(
          r'C:\data\yagura',
          _Inspector({
            ...windows,
            r'C:\data': _dir('O:BAD:(A;;FA;;;BA)(A;OICIIO;GA;;;CO)'),
          }),
        ),
        isEmpty,
      );
    });

    test('a_folder_that_cannot_be_opened_is_refused', () {
      final problems = ancestorProblems(
        r'C:\missing\yagura',
        _Inspector(windows),
      );

      expect(problems.single, contains(r'C:\missing'));
    });
  });

  group('hasInstallRootProtection', () {
    String sddl(String owner, String dacl) => 'O:$owner$dacl';

    test('the_dacl_the_installer_writes_counts', () {
      expect(
        hasInstallRootProtection(_dir(sddl('BA', installRootDaclSddl))),
        isTrue,
      );
    });

    test('another_owner_does_not', () {
      expect(
        hasInstallRootProtection(_dir(sddl('SY', installRootDaclSddl))),
        isFalse,
      );
    });

    test('an_unprotected_dacl_does_not', () {
      expect(
        hasInstallRootProtection(
          _dir(sddl('BA', installRootDaclSddl.replaceFirst('D:P', 'D:'))),
        ),
        isFalse,
      );
    });

    test('an_extra_entry_does_not', () {
      expect(
        hasInstallRootProtection(
          _dir(sddl('BA', '$installRootDaclSddl(A;OICI;FA;;;AU)')),
        ),
        isFalse,
      );
    });

    test('a_link_does_not', () {
      expect(
        hasInstallRootProtection(
          EntrySecurity(isLink: true, sddl: sddl('BA', installRootDaclSddl)),
        ),
        isFalse,
      );
    });
  });
}
