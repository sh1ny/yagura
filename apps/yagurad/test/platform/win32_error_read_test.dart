@Tags(['windows'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32.dart';
import 'package:yagurad/src/platform/win32_security.dart';

void main() {
  test('a_failure_that_reads_as_error_0_is_repeated_to_read_the_true_code', () {
    var calls = 0;
    final reads = [0, 0, 1312];

    final result = callReadingError(
      () {
        calls++;
        return 0;
      },
      (r) => r == 0,
      readError: () => reads.removeAt(0),
    );

    expect(result.error, 1312);
    expect(calls, 3, reason: 'repeated until the error reads non-zero');
  });

  test('a_failure_that_always_reads_0_is_given_up_after_five_calls', () {
    var calls = 0;

    final result = callReadingError(
      () {
        calls++;
        return 0;
      },
      (r) => r == 0,
      readError: () => 0,
    );

    expect(result.error, 0);
    expect(calls, errorReadAttempts);
    expect(errorReadAttempts, 5);
  });

  test('a_success_is_not_repeated_and_reads_no_error', () {
    var calls = 0;
    var reads = 0;

    final result = callReadingError(
      () {
        calls++;
        return 7;
      },
      (r) => r == 0,
      readError: () {
        reads++;
        return 5;
      },
    );

    expect(result.value, 7);
    expect(result.error, 0);
    expect((calls, reads), (1, 0));
  });

  test('a_failure_with_a_code_is_not_repeated', () {
    var calls = 0;

    final result = callReadingError(
      () {
        calls++;
        return 0;
      },
      (r) => r == 0,
      readError: () => 5,
    );

    expect((result.error, calls), (5, 1));
  });

  test('a_dpapi_failure_always_carries_its_code', () {
    // The blob is garbage, so DPAPI fails every time; the code must never
    // read as 0 (which would hide the failure's kind).
    for (var i = 0; i < 200; i++) {
      try {
        dpapiUnprotect(Uint8List.fromList([1, 2, 3, i & 0xFF]));
        fail('garbage was unprotected');
      } on DpapiError catch (e) {
        expect(e.code, isNot(0), reason: 'attempt $i');
      }
    }
  });
}
