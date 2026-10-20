import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagurad/src/admin/admin_wire.dart';
import 'package:yagurad/src/errors.dart';

Uint8List bytes(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

Matcher failsWithReason(String reason) =>
    throwsA(isA<YaguraException>().having((e) => e.reason, 'reason', reason));

void main() {
  test('a_request_round_trips_with_the_protocol_version', () {
    final payload = encodeRequest(
      AdminRequest('roots.add', {'path': r'D:\servers'}),
    );

    expect(jsonDecode(utf8.decode(payload)), {
      'admin_api': adminApi,
      'command': 'roots.add',
      'args': {'path': r'D:\servers'},
    });
    final request = decodeRequest(payload);
    expect(request.command, 'roots.add');
    expect(request.args, {'path': r'D:\servers'});
  });

  test('a_request_of_another_protocol_version_is_refused', () {
    expect(
      () => decodeRequest(bytes({'admin_api': 2, 'command': 'status'})),
      failsWithReason('admin_api_unsupported'),
    );
  });

  test('a_request_that_is_not_a_command_is_refused', () {
    for (final bad in <Uint8List>[
      Uint8List.fromList([0xFF, 0xFE]),
      bytes([1, 2]),
      bytes({'admin_api': adminApi}),
      bytes({'admin_api': adminApi, 'command': 7}),
      bytes({'admin_api': adminApi, 'command': 'status', 'args': 'x'}),
    ]) {
      expect(
        () => decodeRequest(bad),
        failsWithReason('admin_request_invalid'),
        reason: '$bad',
      );
    }
  });

  test('a_reply_carries_a_result_or_a_reason', () {
    final ok = decodeReply(
      encodeReply(AdminReply.ok({'devices': <Object?>[]})),
    );
    expect(ok.isOk, isTrue);
    expect(ok.result, {'devices': <Object?>[]});

    final error = decodeReply(
      encodeReply(
        AdminReply.error(
          'root_in_use',
          'the root is in use',
          details: {'instance': 'A'},
        ),
      ),
    );
    expect(error.isOk, isFalse);
    expect(error.reason, 'root_in_use');
    expect(error.message, 'the root is in use');
    expect(error.details, {'instance': 'A'});
  });

  test('a_message_over_64_kib_is_not_encoded', () {
    expect(maxAdminMessage, 64 * 1024);
    expect(
      () => encodeReply(AdminReply.ok({'text': 'x' * maxAdminMessage})),
      failsWithReason('message_too_large'),
    );
  });
}
