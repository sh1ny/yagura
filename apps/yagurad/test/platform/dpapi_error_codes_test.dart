import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_security.dart';

void main() {
  test('wrong_key_codes_are_the_three_the_design_names', () {
    expect(isWrongKeyCode(0x8009000B), isTrue, reason: 'NTE_BAD_KEY_STATE');
    expect(isWrongKeyCode(0x80090005), isTrue, reason: 'NTE_BAD_DATA');
    expect(isWrongKeyCode(13), isTrue, reason: 'ERROR_INVALID_DATA');
  });

  test('a_signed_code_is_classified_by_its_unsigned_value', () {
    expect(isWrongKeyCode(0x8009000B.toSigned(32)), isTrue);
    expect(isWrongKeyCode(0x80090005.toSigned(32)), isTrue);
  });

  test('every_other_code_is_not_a_wrong_key', () {
    for (final (name, code) in [
      ('no error recorded', 0),
      ('ERROR_FILE_NOT_FOUND', 2),
      ('ERROR_ACCESS_DENIED', 5),
      ('ERROR_INVALID_PARAMETER', 87),
      ('ERROR_NO_SUCH_LOGON_SESSION', 1312),
      ('ERROR_PROFILE_NOT_FOUND-like', 1542),
      ('RPC_S_SERVER_UNAVAILABLE', 1722),
      ('NTE_BAD_KEY', 0x80090003),
      ('NTE_BAD_LEN', 0x80090004),
      ('NTE_FAIL', 0x80090020),
      ('NTE_NO_MEMORY', 0x8009000E),
    ]) {
      expect(isWrongKeyCode(code), isFalse, reason: name);
    }
  });

  test('a_dpapi_error_carries_the_code_and_the_classification', () {
    final wrong = DpapiError('CryptUnprotectData', 0x8009000B);
    final other = DpapiError('CryptUnprotectData', 1312);

    expect(wrong.code, 0x8009000B);
    expect(wrong.isWrongKey, isTrue);
    expect(wrong.toString(), contains('0x8009000b'));
    expect(other.isWrongKey, isFalse);
    expect(other.toString(), contains('1312'));
  });
}
