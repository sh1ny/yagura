// Generates Dart code for the yagura.v1 protocol into packages/yagura_proto.
//
// protoc is pinned in mise.toml and must be on PATH (`mise exec` or an
// activated mise shell). protoc_plugin is pinned as an exact dev dependency of
// packages/yagura_proto; this script compiles its plugin executable into
// .dart_tool/ once per version and hands it to protoc.
//
// Usage: dart run tool/gen_proto.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final protoDir = '$root/proto';
  final outDir = '$root/packages/yagura_proto/lib/src/generated';

  final plugin = await _pluginExecutable(root);
  final protoc = _which('protoc');
  final wellKnown = '${File(protoc).parent.parent.path}/include';

  // The yagura.v1 contract, plus the standard reflection service the daemon
  // serves in dev mode (package:grpc has none).
  final protos = [
    for (final dir in const ['yagura/v1', 'grpc/reflection/v1'])
      ...(Directory('$protoDir/$dir')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.proto'))
          .map((f) => '$dir/${f.uri.pathSegments.last}')
          .toList()
        ..sort()),
  ];

  final out = Directory(outDir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final descriptorSet = File('$outDir/descriptor_set.bin');
  await _run(protoc, [
    '--plugin=protoc-gen-dart=$plugin',
    '--dart_out=grpc:$outDir',
    '--descriptor_set_out=${descriptorSet.path}',
    '--include_imports',
    '-I$protoDir',
    '-I$wellKnown',
    ...protos,
  ], workingDirectory: root);
  _writeDescriptorSet(descriptorSet, File('$outDir/descriptor_set.dart'));
  await _run(Platform.resolvedExecutable, [
    'format',
    outDir,
  ], workingDirectory: root);
  stdout.writeln('Generated ${protos.length} protocol files into $outDir');
}

/// Embeds the serialized `FileDescriptorSet` (every proto with its imports) as
/// Dart source, for the daemon's server reflection, and removes the binary.
void _writeDescriptorSet(File binary, File dart) {
  final encoded = base64Encode(binary.readAsBytesSync());
  binary.deleteSync();
  final chunks = <String>[
    for (var i = 0; i < encoded.length; i += 72)
      "  '${encoded.substring(i, math.min(i + 72, encoded.length))}'",
  ];
  dart.writeAsStringSync(
    [
      '// This is a generated file - do not edit.',
      '//',
      '// A FileDescriptorSet of every yagura.v1 proto, the reflection proto and',
      '// their imports, made by tool/gen_proto.dart.',
      '',
      "import 'dart:convert';",
      "import 'dart:typed_data';",
      '',
      '/// The serialized `google.protobuf.FileDescriptorSet` the daemon\'s server',
      '/// reflection answers from.',
      'final Uint8List yaguraDescriptorSet = base64Decode(',
      chunks.join('\n'),
      ');',
      '',
    ].join('\n'),
  );
}

/// Compiles `protoc_plugin` at the version resolved for the workspace.
Future<String> _pluginExecutable(String root) async {
  final config = jsonDecode(
    File('$root/.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final packages = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final entry = packages.firstWhere(
    (p) => p['name'] == 'protoc_plugin',
    orElse: () => throw StateError(
      'protoc_plugin is not resolved; run `flutter pub get` first',
    ),
  );
  final rootUri = entry['rootUri'] as String;
  final packageRoot = Uri.parse(rootUri.endsWith('/') ? rootUri : '$rootUri/');
  final version = packageRoot.pathSegments
      .lastWhere((s) => s.isNotEmpty)
      .split('-')
      .last;
  final exe = Platform.isWindows ? '.exe' : '';
  final target = File(
    '$root/.dart_tool/protoc_plugin/$version/protoc-gen-dart$exe',
  );
  if (!target.existsSync()) {
    target.parent.createSync(recursive: true);
    await _run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '--packages=$root/.dart_tool/package_config.json',
      File.fromUri(packageRoot.resolve('bin/protoc_plugin.dart')).path,
      '-o',
      target.path,
    ], workingDirectory: root);
  }
  return target.path;
}

String _which(String name) {
  final separator = Platform.isWindows ? ';' : ':';
  final suffixes = Platform.isWindows ? ['.exe', ''] : [''];
  for (final dir in (Platform.environment['PATH'] ?? '').split(separator)) {
    for (final suffix in suffixes) {
      final candidate = File('$dir${Platform.pathSeparator}$name$suffix');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  throw StateError('$name not found on PATH; run through `mise exec --`');
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'exit code $code', code);
  }
}
