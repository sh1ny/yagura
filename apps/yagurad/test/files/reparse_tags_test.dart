import 'package:test/test.dart';
import 'package:yagurad/src/files/reparse_tags.dart';

void main() {
  test('link_like_reparse_tags_are_refused', () {
    for (final (name, tag) in [
      ('mount point', reparseTagMountPoint),
      ('symlink', reparseTagSymlink),
      ('app exec link', reparseTagAppExecLink),
      ('any name surrogate', 0x20001234),
      ('wsl symlink (name surrogate)', 0xA000001D),
    ]) {
      expect(isLinkReparseTag(tag), isTrue, reason: name);
    }
  });

  test('data_reparse_tags_are_allowed', () {
    expect(isLinkReparseTag(reparseTagWof), isFalse, reason: 'WOF');
    expect(isLinkReparseTag(reparseTagDedup), isFalse, reason: 'dedup');
  });

  test('cloud_and_unknown_reparse_tags_fail_closed', () {
    for (final (name, tag) in [
      ('cloud files placeholder', 0x9000001A),
      ('cloud files root', 0x9000F01A),
      ('onedrive', 0x9000701A),
      ('hsm', 0xC0000004),
      ('zero', 0),
      ('unknown', 0x80001234),
    ]) {
      expect(isLinkReparseTag(tag), isTrue, reason: name);
    }
  });

  test('a_signed_tag_is_classified_by_its_unsigned_value', () {
    expect(isLinkReparseTag(reparseTagWof.toSigned(32)), isFalse);
    expect(isLinkReparseTag(reparseTagSymlink.toSigned(32)), isTrue);
  });

  test('descriptions_name_the_kind', () {
    expect(describeReparseTag(reparseTagMountPoint), contains('junction'));
    expect(describeReparseTag(reparseTagSymlink), contains('symbolic'));
    expect(describeReparseTag(0x9000001A), contains('0x9000001a'));
  });
}
