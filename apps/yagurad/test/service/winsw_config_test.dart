import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/service/install_layout.dart';
import 'package:yagurad/src/service/winsw_config.dart';

import '../support/service_support.dart';

final _template = File(p.join(winswSourceDirectory, 'yagurad.xml.template'))
    .readAsStringSync();

const _layout = InstallLayout(root: r'C:\Program Files\Yagura');

ServiceConfig _config({String? data, String bind = '0.0.0.0:7443'}) =>
    ServiceConfig(
      layout: _layout,
      version: '0.1.0',
      bind: bind,
      dataDirectory: data,
    );

void main() {
  group('the WinSW configuration', () {
    test('points_at_the_version_directory_and_runs_in_service_mode', () {
      final xml = _config().render(_template);

      expect(xml, contains('<id>yagurad</id>'));
      expect(
        xml,
        contains(
          r'<executable>C:\Program Files\Yagura\0.1.0\bin\yagurad.exe'
          '</executable>',
        ),
      );
      expect(
        xml,
        contains('<arguments>run --service --bind 0.0.0.0:7443</arguments>'),
      );
      expect(xml, contains('<logpath>C:\\Program Files\\Yagura\\logs'));
    });

    test('starts_automatically_as_localsystem_and_restarts_on_failure', () {
      final xml = _config().render(_template);

      expect(xml, contains('<startmode>Automatic</startmode>'));
      expect(xml, contains('<onfailure action="restart"'));
      // No account element: WinSW registers the service as LocalSystem.
      expect(xml, isNot(contains('serviceaccount')));
    });

    test('quotes_the_data_directory', () {
      final xml = _config(data: r'D:\Yagura Data').render(_template);

      expect(
        xml,
        contains(
          '<arguments>run --service --bind 0.0.0.0:7443 '
          '--data-dir &quot;D:\\Yagura Data&quot;</arguments>',
        ),
      );
    });

    test('escapes_xml_in_every_value', () {
      final xml = _config(data: r'D:\A&B <x>').render(_template);

      expect(xml, contains('D:\\A&amp;B &lt;x&gt;'));
      expect(xml, isNot(contains('A&B')));
    });

    test('a_custom_service_name_is_in_the_id_and_the_display_name', () {
      final xml = ServiceConfig(
        layout: const InstallLayout(root: r'C:\t', serviceName: 'yagurad-t1'),
        version: '0.1.0',
        bind: '0.0.0.0:7443',
      ).render(_template);

      expect(xml, contains('<id>yagurad-t1</id>'));
      expect(xml, contains('<name>Yagura daemon (yagurad-t1)</name>'));
    });

    test('reads_back_what_it_wrote', () {
      for (final data in [null, r'D:\Yagura Data', r'D:\A&B <x>']) {
        final written = _config(data: data, bind: '10.1.2.3:9000');

        final read = ServiceConfig.parse(written.render(_template), _layout)!;

        expect(read.version, '0.1.0');
        expect(read.bind, '10.1.2.3:9000');
        expect(read.dataDirectory, data);
      }
    });

    test('a_file_that_is_not_ours_does_not_parse', () {
      expect(ServiceConfig.parse('<service/>', _layout), isNull);
      expect(
        ServiceConfig.parse(
          '<service><executable>C:\\x\\a.exe</executable>'
          '<arguments>run</arguments></service>',
          _layout,
        ),
        isNull,
      );
    });

    test('a_template_with_an_unknown_placeholder_is_refused', () {
      expect(
        () => _config().render('<id>{{service_name}}</id>{{surprise}}'),
        throwsA(
          isA<YaguraException>().having(
            (e) => e.reason,
            'reason',
            'bundle_invalid',
          ),
        ),
      );
    });

    test('the_repository_template_has_only_known_placeholders', () {
      // Rendering throws on a leftover placeholder.
      expect(() => _config().render(_template), returnsNormally);
    });
  });

  group('the install layout', () {
    test('is_under_program_files', () {
      final layout = InstallLayout.standard(
        environment: {'ProgramFiles': r'C:\Program Files'},
      );

      expect(layout.root, r'C:\Program Files\Yagura');
      expect(layout.winswExecutable, r'C:\Program Files\Yagura\yagurad.exe');
      expect(layout.configFile, r'C:\Program Files\Yagura\yagurad.xml');
      expect(
        layout.executable('0.1.0'),
        r'C:\Program Files\Yagura\0.1.0\bin\yagurad.exe',
      );
    });

    test('finds_its_root_from_a_versioned_executable', () {
      final found = InstallLayout.containing(
        r'C:\Program Files\Yagura\0.2.0\bin\yagurad.exe',
      )!;

      expect(found.$1.root, r'C:\Program Files\Yagura');
      expect(found.$2, '0.2.0');
    });

    test('an_executable_outside_a_version_directory_has_no_install', () {
      expect(InstallLayout.containing(r'C:\dev\build\bin\yagurad.exe'), isNull);
      expect(InstallLayout.containing(r'C:\dart\bin\dart.exe'), isNull);
      expect(InstallLayout.containing(r'C:\Yagura\0.1.0\yagurad.exe'), isNull);
    });

    test('orders_versions', () {
      expect(compareVersions('0.1.0', '0.2.0'), lessThan(0));
      expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.0.0-rc.1', '1.0.0'), lessThan(0));
      expect(compareVersions('1.0.1', '1.0.0-rc.1'), greaterThan(0));
    });
  });
}
