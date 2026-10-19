import 'package:path/path.dart' as p;

import '../errors.dart';
import 'install_layout.dart';

/// The WinSW release the bundle carries (`tool/winsw/README.md`).
const winswVersion = '2.12.0';

/// SHA-256 of `WinSW.NET461.exe` [winswVersion]; install refuses a bundle
/// whose copy differs.
const winswSha256 =
    'b5066b7bbdfba1293e5d15cda3caaea88fbeab35bd5b38c41c913d492aadfc4f';

/// The default API bind of the service (design D6).
const defaultServiceBindText = '0.0.0.0:7443';

/// What the WinSW configuration of one installed version says.
class ServiceConfig {
  const ServiceConfig({
    required this.layout,
    required this.version,
    required this.bind,
    this.dataDirectory,
  });

  final InstallLayout layout;
  final String version;
  final String bind;

  /// Passed as `--data-dir`; null leaves the daemon's default.
  final String? dataDirectory;

  String get serviceName => layout.serviceName;
  String get executable => layout.executable(version);

  /// The command line after the executable.
  String get arguments {
    final data = dataDirectory;
    return 'run --service --bind $bind'
        '${data == null ? '' : ' --data-dir "${_trimSeparator(data)}"'}';
  }

  ServiceConfig withVersion(String version) => ServiceConfig(
    layout: layout,
    version: version,
    bind: bind,
    dataDirectory: dataDirectory,
  );

  ServiceConfig withBind(String bind) => ServiceConfig(
    layout: layout,
    version: version,
    bind: bind,
    dataDirectory: dataDirectory,
  );

  /// Fills the WinSW [template] (`tool/winsw/yagurad.xml.template`). Every
  /// value is XML-escaped; a placeholder left over is a broken template.
  String render(String template) {
    final values = {
      'service_name': serviceName,
      'display_name': serviceName == defaultServiceName
          ? 'Yagura daemon'
          : 'Yagura daemon ($serviceName)',
      'executable': executable,
      'arguments': arguments,
      'log_path': layout.logDirectory,
    };
    var xml = template;
    for (final MapEntry(:key, :value) in values.entries) {
      xml = xml.replaceAll('{{$key}}', _escape(value));
    }
    final left = RegExp(r'\{\{[a-z_]+\}\}').firstMatch(xml);
    if (left != null) {
      throw YaguraException(
        'bundle_invalid',
        'the WinSW template has an unknown placeholder ${left[0]}',
      );
    }
    return xml;
  }

  /// [xml] with the `<arguments>` element replaced by this configuration's
  /// arguments: how `service configure` changes the bind without the
  /// template.
  String replaceArguments(String xml) {
    final element = RegExp(r'<arguments>.*?</arguments>', dotAll: true);
    if (!element.hasMatch(xml)) {
      throw YaguraException(
        'service_config_invalid',
        'the WinSW configuration has no <arguments> element',
      );
    }
    return xml.replaceFirstMapped(
      element,
      (_) => '<arguments>${_escape(arguments)}</arguments>',
    );
  }

  /// Reads back what [render] wrote; null when [xml] is not ours (no
  /// executable under a version directory, no bind).
  static ServiceConfig? parse(String xml, InstallLayout layout) {
    final executable = _element(xml, 'executable');
    final arguments = _element(xml, 'arguments');
    if (executable == null || arguments == null) return null;
    final installed = InstallLayout.containing(executable);
    final bind = RegExp(r'--bind\s+(\S+)').firstMatch(arguments)?[1];
    if (installed == null || bind == null) return null;
    final data =
        RegExp(r'--data-dir\s+"([^"]*)"').firstMatch(arguments)?[1] ??
        RegExp(r'--data-dir\s+([^\s"]+)').firstMatch(arguments)?[1];
    return ServiceConfig(
      layout: layout,
      version: installed.$2,
      bind: bind,
      dataDirectory: data,
    );
  }

  static String? _element(String xml, String name) {
    final match = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
    return match == null ? null : _unescape(match[1]!.trim());
  }

  static String _trimSeparator(String path) {
    final normal = p.normalize(path);
    return normal.length > 3 && normal.endsWith(p.separator)
        ? normal.substring(0, normal.length - 1)
        : normal;
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _unescape(String text) => text
      .replaceAll('&quot;', '"')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
