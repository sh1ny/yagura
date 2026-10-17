import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/schema.dart';
import 'package:yagura_desktop/src/transport.dart';
import 'package:yagura_desktop/src/ui/home_page.dart';
import 'package:yagura_desktop/src/ui/settings_editor.dart';
import 'package:yagura_desktop/src/ui/settings_form.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';

const _schema = {
  'serverName': {
    'type': 'string',
    'label': 'Server name',
    'required': true,
    'min': 3,
    'group': 'General',
  },
  'maxPlayers': {
    'type': 'integer',
    'label': 'Max players',
    'min': 1,
    'max': 64,
  },
};

Harness _harness({
  Map<String, Object?> schema = _schema,
  Map<String, Object?> settings = const {'serverName': 'Yagura'},
}) {
  final daemon = FakeDaemon(
    instances: [
      makeInstance(
        id: 'i1',
        name: 'Alpha',
        ports: [
          Port(name: 'game', number: 2456, protocol: Protocol.PROTOCOL_UDP),
        ],
        settings: settings,
        revision: 3,
      ),
    ],
  );
  daemon.plugins['testgame'] = PluginDetail(
    summary: PluginSummary(id: 'testgame', name: 'Test Game'),
    settingsSchema: JsonDocument(json: jsonEncode(schema), schemaVersion: 7),
  );
  return Harness(daemon: daemon);
}

Future<void> _pumpEditor(WidgetTester tester, Harness harness) async {
  await pumpApp(
    tester,
    harness,
    SettingsEditor(
      daemonId: kDevDaemonId,
      instance: harness.daemon.instances.single,
    ),
  );
}

Finder _field(String path) => find.byKey(ValueKey('field:$path'));

void main() {
  testWidgets('daemon_rejects_a_value', (tester) async {
    final harness = _harness();
    harness.daemon.updateFailure = const DaemonCallException(
      code: 3,
      reason: 'invalid_argument',
      fieldViolations: {'ports.game': 'port 2456 is already in use'},
    );
    await _pumpEditor(tester, harness);

    await tester.enterText(_field('serverName'), 'Renamed server');
    await tester.enterText(_field('maxPlayers'), '20');
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);

    expect(harness.daemon.updates, hasLength(1));
    // The error sits under the port field...
    expect(
      find.descendant(
        of: _field('ports.game'),
        matching: find.text('port 2456 is already in use'),
      ),
      findsOneWidget,
    );
    // ...and the other edits stay in the form.
    expect(
      find.descendant(
        of: _field('serverName'),
        matching: find.text('Renamed server'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _field('maxPlayers'), matching: find.text('20')),
      findsOneWidget,
    );
  });

  testWidgets('unknown_field_type', (tester) async {
    final harness = _harness(
      schema: {
        ..._schema,
        'tint': {'type': 'hologram', 'label': 'Tint'},
      },
      settings: const {
        'serverName': 'Yagura',
        'tint': {'a': 1},
      },
    );
    await _pumpEditor(tester, harness);

    // Read-only, with the raw JSON value and a notice.
    expect(find.text('{"a":1}'), findsOneWidget);
    expect(find.textContaining('hologram'), findsOneWidget);
    expect(find.byKey(const ValueKey('readonly:tint')), findsOneWidget);
    expect(_field('tint'), findsNothing);

    // The rest of the form works and the unknown value is kept as it was.
    await tester.enterText(_field('serverName'), 'Edited');
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);

    final request = harness.daemon.updates.single;
    expect(request.instanceId, 'i1');
    expect(request.expectedRevision.toInt(), 3);
    expect(request.settings.schemaVersion, 7);
    final sent = jsonDecode(request.settings.json) as Map<String, Object?>;
    expect(sent['serverName'], 'Edited');
    expect(sent['tint'], {'a': 1});
  });

  testWidgets('client_side_validation_uses_the_schema_constraints', (
    tester,
  ) async {
    final harness = _harness();
    await _pumpEditor(tester, harness);

    await tester.enterText(_field('serverName'), 'ab');
    await tester.enterText(_field('maxPlayers'), '100');
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);

    expect(harness.daemon.updates, isEmpty);
    expect(find.textContaining('at least 3'), findsOneWidget);
    expect(find.textContaining('at most 64'), findsOneWidget);
  });

  testWidgets('a_remote_update_does_not_ride_on_stale_form_values', (
    tester,
  ) async {
    final harness = _harness(settings: const {'serverName': 'Old'});
    await pumpApp(
      tester,
      harness,
      const InstanceDetail(daemonId: kDevDaemonId, instanceId: 'i1'),
    );

    harness.daemon.emitChanged(
      makeInstance(
        id: 'i1',
        name: 'Alpha',
        settings: const {'serverName': 'Remote'},
        revision: 4,
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);

    // The form still holds the old values, so the old revision goes with
    // them and the daemon can report the conflict.
    expect(harness.daemon.updates.single.expectedRevision.toInt(), 3);

    // Reloading takes the new values and the new revision together.
    await tester.tap(find.byKey(const ValueKey('settings:reload')));
    await settle(tester);
    expect(
      find.descendant(of: _field('serverName'), matching: find.text('Remote')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);
    expect(harness.daemon.updates.last.expectedRevision.toInt(), 4);
  });

  testWidgets('an_optional_object_stays_unset_until_enabled', (tester) async {
    final harness = _harness(
      schema: {
        ..._schema,
        'net': {
          'type': 'object',
          'label': 'Network',
          'fields': {
            'rate': {'type': 'integer', 'label': 'Rate', 'required': true},
          },
        },
      },
    );
    await _pumpEditor(tester, harness);

    await tester.enterText(_field('serverName'), 'Edited');
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);

    final sent = jsonDecode(
      harness.daemon.updates.single.settings.json,
    ) as Map<String, Object?>;
    expect(sent, {'serverName': 'Edited'});

    // Enabling it brings its required child along.
    await tester.tap(find.byKey(const ValueKey('object:enable:net')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);
    expect(harness.daemon.updates, hasLength(1));
    expect(find.text('Required'), findsOneWidget);
    await tester.enterText(_field('net.rate'), '60');
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);
    final again = jsonDecode(
      harness.daemon.updates.last.settings.json,
    ) as Map<String, Object?>;
    expect(again['net'], {'rate': 60});
  });

  testWidgets('numbers_that_are_not_finite_are_rejected', (tester) async {
    final harness = _harness(
      schema: {
        'ratio': {'type': 'number', 'label': 'Ratio'},
      },
      settings: const {},
    );
    await _pumpEditor(tester, harness);

    for (final text in ['NaN', 'Infinity', '-Infinity']) {
      await tester.enterText(_field('ratio'), text);
      await tester.tap(find.byKey(const ValueKey('form:save')));
      await settle(tester);
      expect(find.text('Enter a number'), findsOneWidget, reason: text);
    }
    expect(harness.daemon.updates, isEmpty);
  });

  testWidgets('a_cleared_list_is_sent_as_empty', (tester) async {
    final harness = _harness(
      schema: {
        'mods': {
          'type': 'string_list',
          'label': 'Mods',
          'default': ['a'],
        },
      },
      settings: const {
        'mods': ['a'],
      },
    );
    await _pumpEditor(tester, harness);

    await tester.enterText(_field('mods'), '');
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await settle(tester);

    final sent = jsonDecode(
      harness.daemon.updates.single.settings.json,
    ) as Map<String, Object?>;
    expect(sent, {'mods': <Object?>[]});
  });

  group('schema', () {
    test('parses_every_v1_field_type', () {
      final schema = SettingsSchema.tryParse(
        jsonEncode({
          'a': {'type': 'string', 'pattern': '^x'},
          'b': {'type': 'integer'},
          'c': {'type': 'number'},
          'd': {'type': 'boolean'},
          'e': {
            'type': 'enum',
            'values': ['x', 'y'],
          },
          'f': {'type': 'secret'},
          'g': {'type': 'string_list'},
          'h': {
            'type': 'object',
            'fields': {
              'inner': {'type': 'string'},
            },
          },
          'i': {
            'type': 'list',
            'fields': {
              'col': {'type': 'string', 'required': true},
            },
          },
          'j': {'type': 'wat'},
        }),
      )!;
      expect(schema.fields.map((f) => f.runtimeType), [
        StringField,
        IntegerField,
        NumberField,
        BooleanField,
        EnumField,
        SecretField,
        StringListField,
        ObjectField,
        ListField,
        UnknownField,
      ]);
    });

    test('rejects_documents_that_are_not_objects', () {
      expect(SettingsSchema.tryParse('[1]'), isNull);
      expect(SettingsSchema.tryParse('not json'), isNull);
    });
  });

  testWidgets('every_field_type_renders_and_submits', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SettingsSubmission? submitted;
    final schema = SettingsSchema.tryParse(
      jsonEncode({
        'flag': {'type': 'boolean', 'label': 'Flag', 'default': false},
        'mode': {
          'type': 'enum',
          'label': 'Mode',
          'values': ['easy', 'hard'],
          'default': 'easy',
        },
        'ratio': {'type': 'number', 'label': 'Ratio'},
        'pass': {'type': 'secret', 'label': 'Password'},
        'mods': {'type': 'string_list', 'label': 'Mods'},
        'net': {
          'type': 'object',
          'label': 'Network',
          'fields': {
            'rate': {'type': 'integer', 'label': 'Rate'},
          },
        },
        'rows': {
          'type': 'list',
          'label': 'Rows',
          'fields': {
            'class': {'type': 'string', 'label': 'Class', 'required': true},
          },
        },
        'tweak': {'type': 'string', 'label': 'Tweak', 'advanced': true},
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsForm(
            schema: schema,
            values: const {},
            ports: const [],
            onSubmit: (s) => submitted = s,
          ),
        ),
      ),
    );

    // Advanced settings stay hidden until asked for.
    expect(_field('tweak'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('form:advanced')));
    await tester.pump();
    expect(_field('tweak'), findsOneWidget);

    await tester.tap(_field('flag'));
    await tester.enterText(_field('ratio'), '1.5');
    await tester.enterText(_field('pass'), 's3cret');
    await tester.enterText(_field('mods'), 'a\nb');
    await tester.tap(find.byKey(const ValueKey('object:enable:net')));
    await tester.pump();
    await tester.enterText(_field('net.rate'), '60');
    await tester.tap(find.byKey(const ValueKey('list:add:rows')));
    await tester.pump();
    await tester.enterText(_field('rows[0].class'), 'Wood');
    await tester.tap(find.byKey(const ValueKey('form:save')));
    await tester.pump();

    expect(submitted, isNotNull);
    expect(submitted!.settings, {
      'flag': true,
      'mode': 'easy',
      'ratio': 1.5,
      'mods': ['a', 'b'],
      'net': {'rate': 60},
      'rows': [
        {'class': 'Wood'},
      ],
    });
    expect(submitted!.secrets, {'pass': 's3cret'});
  });

  testWidgets('a_schema_that_cannot_be_read_falls_back_to_read_only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsForm(
            schema: null,
            values: const {'serverName': 'Yagura'},
            ports: const [],
            onSubmit: (_) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('"serverName"'), findsOneWidget);
    expect(find.byKey(const ValueKey('form:save')), findsNothing);
  });
}
