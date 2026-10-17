import 'dart:convert';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

/// An index over a serialized `google.protobuf.FileDescriptorSet`: which file
/// defines which symbol, and what each file imports. Reads only the parts of
/// the descriptor protos that reflection needs.
class DescriptorIndex {
  DescriptorIndex(Uint8List descriptorSet) {
    for (final file in _Wire(descriptorSet).bytesFields(1)) {
      _addFile(file);
    }
  }

  final _files = <String, Uint8List>{};
  final _dependencies = <String, List<String>>{};
  final _symbols = <String, String>{};

  /// The fully-qualified names of every indexed service.
  final services = <String>[];

  /// The method names of each indexed service, by fully-qualified service
  /// name.
  final methods = <String, List<String>>{};

  bool hasSymbol(String name) => _symbols.containsKey(name);

  /// The file that defines the fully-qualified symbol [name].
  String? fileOfSymbol(String name) => _symbols[name];

  /// [fileName] followed by everything it imports, each file once; empty
  /// when the file is unknown.
  List<Uint8List> withDependencies(String fileName) {
    final seen = <String>{};
    final out = <Uint8List>[];
    void visit(String name) {
      if (!seen.add(name)) return;
      if (_files[name] case final bytes?) out.add(bytes);
      for (final dependency in _dependencies[name] ?? const <String>[]) {
        visit(dependency);
      }
    }

    visit(fileName);
    return out;
  }

  void _addFile(Uint8List bytes) {
    final wire = _Wire(bytes);
    final name = wire.stringField(1) ?? '';
    final package = wire.stringField(2) ?? '';
    final prefix = package.isEmpty ? '' : '$package.';
    _files[name] = bytes;
    _dependencies[name] = wire.stringFields(3);

    void defineMessage(Uint8List message, String scope) {
      final m = _Wire(message);
      final full = '$scope${m.stringField(1)}';
      _symbols[full] = name;
      for (final nested in m.bytesFields(3)) {
        defineMessage(nested, '$full.');
      }
      for (final enumType in m.bytesFields(4)) {
        _symbols['$full.${_Wire(enumType).stringField(1)}'] = name;
      }
    }

    for (final message in wire.bytesFields(4)) {
      defineMessage(message, prefix);
    }
    for (final enumType in wire.bytesFields(5)) {
      _symbols['$prefix${_Wire(enumType).stringField(1)}'] = name;
    }
    for (final service in wire.bytesFields(6)) {
      final s = _Wire(service);
      final full = '$prefix${s.stringField(1)}';
      _symbols[full] = name;
      services.add(full);
      for (final method in s.bytesFields(2)) {
        final methodName = _Wire(method).stringField(1);
        _symbols['$full.$methodName'] = name;
        methods.putIfAbsent(full, () => []).add(methodName!);
      }
    }
  }
}

/// `grpc.reflection.v1.ServerReflection`: lists the served services and
/// answers file-descriptor requests so `grpcurl` and similar tools work
/// against a dev-mode daemon.
class ReflectionApi extends pb.ServerReflectionServiceBase {
  ReflectionApi(this._index, this._served);

  final DescriptorIndex _index;

  /// The names of the services this server lists.
  final List<String> Function() _served;

  @override
  Stream<pb.ServerReflectionResponse> serverReflectionInfo(
    ServiceCall call,
    Stream<pb.ServerReflectionRequest> request,
  ) async* {
    await for (final r in request) {
      yield _answer(r);
    }
  }

  pb.ServerReflectionResponse _answer(pb.ServerReflectionRequest request) {
    pb.ServerReflectionResponse files(List<Uint8List> descriptors) =>
        pb.ServerReflectionResponse(
          originalRequest: request,
          fileDescriptorResponse: pb.FileDescriptorResponse(
            fileDescriptorProto: descriptors,
          ),
        );
    pb.ServerReflectionResponse error(int code, String message) =>
        pb.ServerReflectionResponse(
          originalRequest: request,
          errorResponse: pb.ErrorResponse(
            errorCode: code,
            errorMessage: message,
          ),
        );

    switch (request.whichMessageRequest()) {
      case pb.ServerReflectionRequest_MessageRequest.listServices:
        return pb.ServerReflectionResponse(
          originalRequest: request,
          listServicesResponse: pb.ListServiceResponse(
            service: [
              for (final name in _served()) pb.ServiceResponse(name: name),
            ],
          ),
        );
      case pb.ServerReflectionRequest_MessageRequest.fileByFilename:
        final descriptors = _index.withDependencies(request.fileByFilename);
        return descriptors.isEmpty
            ? error(
                StatusCode.notFound,
                'file not found: ${request.fileByFilename}',
              )
            : files(descriptors);
      case pb.ServerReflectionRequest_MessageRequest.fileContainingSymbol:
        final file = _index.fileOfSymbol(request.fileContainingSymbol);
        return file == null
            ? error(
                StatusCode.notFound,
                'symbol not found: ${request.fileContainingSymbol}',
              )
            : files(_index.withDependencies(file));
      case pb.ServerReflectionRequest_MessageRequest.allExtensionNumbersOfType:
        final type = request.allExtensionNumbersOfType;
        return _index.hasSymbol(type)
            ? pb.ServerReflectionResponse(
                originalRequest: request,
                allExtensionNumbersResponse: pb.ExtensionNumberResponse(
                  baseTypeName: type,
                ),
              )
            : error(StatusCode.notFound, 'type not found: $type');
      case pb.ServerReflectionRequest_MessageRequest.fileContainingExtension:
        return error(StatusCode.notFound, 'no extensions are defined');
      case pb.ServerReflectionRequest_MessageRequest.notSet:
        return error(
          StatusCode.unimplemented,
          'unsupported reflection request',
        );
    }
  }
}

/// The same service under the older package name, which many tools still
/// ask for first. The two are wire-compatible.
class ReflectionV1AlphaApi extends ReflectionApi {
  ReflectionV1AlphaApi(super.index, super.served);

  @override
  String get $name => 'grpc.reflection.v1alpha.ServerReflection';
}

/// Minimal reader of protobuf wire format: the fields of one message.
class _Wire {
  _Wire(this._bytes);

  final Uint8List _bytes;

  /// The values of length-delimited field [number], in order.
  List<Uint8List> bytesFields(int number) => [
    for (final (n, value) in _fields())
      if (n == number && value is Uint8List) value,
  ];

  List<String> stringFields(int number) => [
    for (final value in bytesFields(number)) utf8.decode(value),
  ];

  String? stringField(int number) => stringFields(number).firstOrNull;

  /// `(field number, value)` pairs; a value is bytes for length-delimited
  /// fields and an int for the others.
  Iterable<(int, Object)> _fields() sync* {
    var i = 0;
    int varint() {
      var result = 0;
      var shift = 0;
      while (true) {
        final byte = _bytes[i++];
        result |= (byte & 0x7f) << shift;
        if (byte & 0x80 == 0) return result;
        shift += 7;
      }
    }

    while (i < _bytes.length) {
      final tag = varint();
      final number = tag >> 3;
      switch (tag & 7) {
        case 0:
          yield (number, varint());
        case 1:
          yield (number, 0);
          i += 8;
        case 2:
          final length = varint();
          yield (number, Uint8List.sublistView(_bytes, i, i + length));
          i += length;
        case 5:
          yield (number, 0);
          i += 4;
        default:
          throw FormatException('unsupported wire type ${tag & 7}');
      }
    }
  }
}
