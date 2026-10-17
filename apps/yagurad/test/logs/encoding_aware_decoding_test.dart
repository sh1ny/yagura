import 'dart:convert';

import 'package:test/test.dart';
import 'package:yagurad/src/logs/logs.dart';

import 'log_test_support.dart';

/// UTF-16LE bytes of [text], optionally behind a byte-order mark.
List<int> utf16le(String text, {bool bom = false}) => [
  if (bom) ...const [0xFF, 0xFE],
  for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
];

void main() {
  test('scum_utf_16_log', () async {
    final rig = LogRig();
    // The game has not created its log yet; it starts with a byte-order mark
    // and Windows line breaks.
    await rig.attach([
      rig.fileSource(
        'scum',
        'Saved/Logs/SCUM.log',
        encoding: LogEncoding.utf16le,
      ),
    ]);
    final followed = Collector(rig.hub.follow(rigInstance));

    rig.write(
      'Saved/Logs/SCUM.log',
      utf16le('LogInit: Welcome\r\nLogNet: Player é世 joined\r\n', bom: true),
    );
    await rig.poll();
    await followed.settle();

    expect(followed.texts, ['LogInit: Welcome', 'LogNet: Player é世 joined']);
    expect(followed.texts.join(), isNot(contains('\u0000')));
    expect(followed.entries.map((e) => e.source), everyElement('scum'));

    // Lines that arrive later are not misaligned by a split code unit.
    final tail = utf16le('LogGame: next\r\n');
    rig.append('Saved/Logs/SCUM.log', tail.sublist(0, 7));
    await rig.poll();
    rig.append('Saved/Logs/SCUM.log', tail.sublist(7));
    await rig.poll();
    await followed.settle();
    expect(followed.texts.last, 'LogGame: next');
    expect(rig.hub.backlog(rigInstance, lines: 10).entries.map((e) => e.text), [
      'LogInit: Welcome',
      'LogNet: Player é世 joined',
      'LogGame: next',
    ]);
  });

  test('invalid_bytes', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([rig.fileSource('server', 'server.log')]);
    final followed = Collector(rig.hub.follow(rigInstance));

    rig.append('server.log', [
      ...utf8.encode('bad '),
      0xFF,
      0xFE,
      ...utf8.encode(' bytes\nafter\n'),
    ]);
    await rig.poll();
    await followed.settle();

    // The line is delivered, not dropped, with U+FFFD for the invalid bytes.
    expect(followed.texts, ['bad �� bytes', 'after']);
  });

  test('latin_1_bytes_decode_to_their_code_points', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([
      rig.fileSource('server', 'server.log', encoding: LogEncoding.latin1),
    ]);
    rig.append('server.log', [0x63, 0x61, 0x66, 0xE9, 0x0A]);
    await rig.poll();
    expect(rig.hub.backlog(rigInstance, lines: 5).entries.single.text, 'café');
  });
}
