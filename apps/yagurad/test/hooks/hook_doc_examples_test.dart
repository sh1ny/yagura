import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/hooks/hooks.dart';

import 'hook_test_support.dart';

/// A fenced code block of the document: its info string and body.
class Block {
  Block(this.info, this.body);

  final List<String> info;
  final String body;

  String? attribute(String name) {
    for (final token in info) {
      if (token.startsWith('$name=')) return token.substring(name.length + 1);
    }
    return null;
  }
}

List<Block> readBlocks(String markdown) {
  final blocks = <Block>[];
  List<String>? info;
  final body = <String>[];
  for (final line in const LineSplitter().convert(markdown)) {
    if (info == null) {
      if (line.startsWith('```') && line.length > 3) {
        info = line.substring(3).trim().split(RegExp(r'\s+'));
        body.clear();
      }
    } else if (line.trim() == '```') {
      blocks.add(Block(info, body.join('\n')));
      info = null;
    } else {
      body.add(line);
    }
  }
  return blocks;
}

void main() {
  final doc = File(p.join('..', '..', 'docs', 'plugins', 'hooks.md'));
  final blocks = readBlocks(doc.readAsStringSync());

  final contextJson = jsonDecode(
    blocks.singleWhere((b) => b.info.join(' ') == 'json context').body,
  ) as Map<String, Object?>;
  final instanceFiles = (jsonDecode(
    blocks.singleWhere((b) => b.info.join(' ') == 'json instance').body,
  ) as Map<String, Object?>).cast<String, String>();

  HookContext contextFromDoc() => HookContext(
    instanceId: contextJson['instanceId']! as String,
    pluginId: contextJson['pluginId']! as String,
    pluginVersion: contextJson['pluginVersion']! as String,
    os: contextJson['os']! as String,
    paths: (contextJson['paths']! as Map).cast<String, String>(),
    settings: (contextJson['settings']! as Map).cast<String, Object?>(),
    ports: (contextJson['ports']! as Map).cast<String, int>(),
  );

  // Each `js hook=<name>` block with the `json result` block that follows it.
  final examples = <(String, String, Object?)>[];
  for (var i = 0; i < blocks.length; i++) {
    final hook = blocks[i].info.first == 'js'
        ? blocks[i].attribute('hook')
        : null;
    if (hook == null) continue;
    final next = blocks[i + 1];
    if (next.info.join(' ') != 'json result') {
      throw StateError('example $hook must be followed by its json result');
    }
    examples.add((hook, blocks[i].body, jsonDecode(next.body)));
  }

  test('the document has one example per hook point', () {
    expect(
      examples.map((e) => e.$1).toSet(),
      HookPoint.values.map((h) => h.exportName).toSet(),
    );
    expect(examples, hasLength(HookPoint.values.length));
  });

  for (final (hook, source, expected) in examples) {
    test(
      'example $hook returns the documented result and applies cleanly',
      () async {
        final instance = makeInstance();
        for (final entry in instanceFiles.entries) {
          writeInstanceFile(instance, entry.key, entry.value);
        }
        final point = HookPoint.values.byName(hook);

        final result = await HookHost().run(
          HookInvocation(
            point: point,
            source: source,
            context: contextFromDoc(),
            root: InstanceRoot(instance.path),
          ),
        );

        expect(result.ran, isTrue);
        expect(result.result.toJson(), expected);
        // The edits were applied: the file is still valid JSON.
        final config = File(p.join(instance.path, 'cfg', 'cfggameplay.json'));
        expect(() => jsonDecode(config.readAsStringSync()), returnsNormally);
      },
    );
  }
}
