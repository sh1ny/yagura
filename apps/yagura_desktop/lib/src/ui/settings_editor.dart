import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../providers.dart';
import '../schema.dart';
import '../transport.dart';
import 'settings_form.dart';

/// Loads the instance's plugin schema and edits the instance's settings.
class SettingsEditor extends ConsumerStatefulWidget {
  const SettingsEditor({
    super.key,
    required this.daemonId,
    required this.instance,
    this.invalidFields = const {},
  });

  final String daemonId;
  final Instance instance;

  /// Fields the daemon says no longer validate (a plugin update), with the
  /// reason; they are marked in the form until the settings are saved.
  final Map<String, String> invalidFields;

  @override
  ConsumerState<SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends ConsumerState<SettingsEditor> {
  bool _loading = true;
  String? _loadError;
  SettingsSchema? _schema;
  int _schemaVersion = 0;
  late Map<String, String> _violations = widget.invalidFields;
  String? _error;

  /// After a `revision_conflict`: the fields where the saved settings differ
  /// from what the user is about to save.
  List<FieldDifference> _conflict = const [];
  String? _conflictHeader;
  bool _saving = false;

  /// The instance the form was filled from. The form copies its values once,
  /// so the revision a save expects stays paired with them: a newer revision
  /// from the daemon only takes effect on [_reload] or after our own save.
  late Instance _editing;
  int _formEpoch = 0;

  @override
  void initState() {
    super.initState();
    _editing = widget.instance;
    _load();
  }

  @override
  void didUpdateWidget(SettingsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.invalidFields, widget.invalidFields)) {
      _violations = widget.invalidFields;
    }
  }

  Future<void> _load() async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    try {
      final transport = await connection.whenConnected();
      final plugin = await transport.getPlugin(widget.instance.pluginId);
      if (!mounted) return;
      setState(() {
        _schema = SettingsSchema.tryParse(plugin.settingsSchema.json);
        _schemaVersion = plugin.settingsSchema.schemaVersion;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is DaemonCallException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Map<String, Object?> get _values =>
      switch (_jsonDecodeOrNull(_editing.settings.json)) {
        final Map<String, Object?> values => values,
        _ => const {},
      };

  Future<void> _save(SettingsSubmission submission) async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    final instance = _editing;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final transport = connection.transport;
      var updated = await transport.updateSettings(
        UpdateSettingsRequest(
          instanceId: instance.id,
          expectedRevision: instance.revision,
          settings: JsonDocument(
            json: jsonEncode(submission.settings),
            schemaVersion: _schemaVersion,
          ),
          ports: [
            for (final p in instance.ports)
              Port(
                name: p.name,
                number: submission.ports[p.name] ?? p.number,
                protocol: p.protocol,
                purpose: p.purpose,
                exposed: p.exposed,
              ),
          ],
        ),
      );
      // The settings are saved: the form moves to this revision now, so a
      // failure below does not leave it on a revision the daemon has passed.
      if (mounted) setState(() => _editing = updated);
      final pending = submission.secrets.entries.toList();
      for (var i = 0; i < pending.length; i++) {
        final MapEntry(:key, :value) = pending[i];
        try {
          updated = await transport.setSecret(
            SetSecretRequest(
              instanceId: instance.id,
              expectedRevision: updated.revision,
              key: key,
              value: value,
            ),
          );
          if (mounted) setState(() => _editing = updated);
        } on DaemonCallException catch (e) {
          final notSet = [for (final p in pending.skip(i)) '"${p.key}"'];
          if (e.reason == 'revision_conflict') {
            // Someone else changed the instance after the settings were
            // saved: show what differs and keep the edits, like a conflict on
            // the settings themselves. The form does not move on silently.
            await _onConflict(
              connection,
              instance,
              submission,
              header:
                  'The settings were saved, but someone else changed this '
                  'instance before the secrets ${notSet.join(', ')} could be '
                  'set. Your edits are still in the form. These fields differ '
                  'from your values; saving again sets the secrets and '
                  'replaces the saved values with yours.',
              emptyNotice:
                  'The settings were saved, but someone else changed this '
                  'instance before the secrets ${notSet.join(', ')} could be '
                  'set. No setting shown here differs. Save again to set the '
                  'secrets.',
            );
            return;
          }
          if (!mounted) return;
          setState(() {
            _violations = const {};
            _conflict = const [];
            _editing = updated;
            _error =
                'The settings were saved. The secrets ${notSet.join(', ')} '
                'were not: ${e.message.isEmpty ? e.reason : e.message}. '
                'Enter them again and save.';
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _violations = const {};
        _conflict = const [];
        _editing = updated;
      });
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Settings saved')));
    } on DaemonCallException catch (e) {
      if (e.reason == 'revision_conflict') {
        await _onConflict(connection, instance, submission);
        return;
      }
      if (!mounted) return;
      setState(() {
        _violations = {
          for (final MapEntry(:key, :value) in e.fieldViolations.entries)
            key.startsWith('settings.') ? key.substring(9) : key: value,
        };
        _error = e.fieldViolations.isEmpty
            ? (e.message.isEmpty ? e.reason : e.message)
            : 'Some values were rejected.';
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Someone else saved first: loads the instance as it is now, keeps the
  /// user's edits in the form and lists the fields that differ. The next save
  /// goes against the revision just loaded.
  Future<void> _onConflict(
    DaemonConnection connection,
    Instance mine,
    SettingsSubmission submission, {
    String? header,
    String? emptyNotice,
  }) async {
    var current = widget.instance;
    try {
      current = await connection.transport.getInstance(mine.id);
    } on Object {
      // The cached instance is the best there is.
    }
    if (!mounted) return;
    setState(() {
      _editing = current;
      _violations = const {};
      _conflict = differences(submission, current);
      _conflictHeader = header;
      _error = _conflict.isEmpty
          ? emptyNotice ??
                'Someone else saved first and none of your changes were '
                    'saved. No setting shown here differs (secrets are never '
                    'compared). Save again to apply your changes.'
          : null;
    });
  }

  void _reload() => setState(() {
    _editing = widget.instance;
    _conflict = const [];
    _violations = const {};
    _error = null;
    _formEpoch++;
  });

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Could not load the settings schema: $_loadError'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_conflict.isNotEmpty)
          _ConflictPanel(
            differences: _conflict,
            header: _conflictHeader,
            onReload: _reload,
          ),
        if (widget.instance.revision > _editing.revision)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'These settings changed elsewhere. Reload to see the new '
                    'values; saving now is checked against the old revision.',
                  ),
                ),
                TextButton(
                  key: const ValueKey('settings:reload'),
                  onPressed: _reload,
                  child: const Text('Reload'),
                ),
              ],
            ),
          ),
        if (_saving) const LinearProgressIndicator(),
        Expanded(
          child: SettingsForm(
            key: ValueKey(_formEpoch),
            schema: _schema,
            values: _values,
            ports: _editing.ports,
            violations: _violations,
            onSubmit: _save,
          ),
        ),
      ],
    );
  }
}

Object? _jsonDecodeOrNull(String json) {
  try {
    return jsonDecode(json);
  } on FormatException {
    return null;
  }
}

/// One setting where the user's edit and the saved value differ.
final class FieldDifference {
  const FieldDifference(this.path, this.mine, this.saved);

  /// JSON path, e.g. `serverName`, `net.rate`, `ports.game`.
  final String path;

  /// The value in the form, null when unset.
  final Object? mine;

  /// The value the daemon has now, null when unset.
  final Object? saved;

  String get text => '$path: yours ${_show(mine)}, saved ${_show(saved)}';

  static String _show(Object? value) =>
      value == null ? '(not set)' : jsonEncode(value);
}

/// The settings and ports where [submission] differs from [current]. Secrets
/// are write-only and never compared.
List<FieldDifference> differences(
  SettingsSubmission submission,
  Instance current,
) {
  final saved = switch (_jsonDecodeOrNull(current.settings.json)) {
    final Map<String, Object?> values => values,
    _ => const <String, Object?>{},
  };
  final mine = _flatten(submission.settings);
  final theirs = _flatten(saved);
  final result = <FieldDifference>[
    for (final path in {...mine.keys, ...theirs.keys})
      if (jsonEncode(mine[path]) != jsonEncode(theirs[path]))
        FieldDifference(path, mine[path], theirs[path]),
  ];
  for (final port in current.ports) {
    final edited = submission.ports[port.name];
    if (edited != null && edited != port.number) {
      result.add(FieldDifference('ports.${port.name}', edited, port.number));
    }
  }
  return result;
}

/// Nested objects as dotted paths; lists and scalars stay whole. Secret
/// markers (`{"secret": true, ...}`) are left out.
Map<String, Object?> _flatten(
  Map<String, Object?> values, [
  String prefix = '',
]) {
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in values.entries) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, Object?>) {
      if (value['secret'] == true) continue;
      out.addAll(_flatten(value, path));
    } else {
      out[path] = value;
    }
  }
  return out;
}

class _ConflictPanel extends StatelessWidget {
  const _ConflictPanel({
    required this.differences,
    required this.onReload,
    this.header,
  });

  final List<FieldDifference> differences;
  final String? header;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('settings:conflict'),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          header ??
              'Someone else saved these settings first. Your edits are still '
                  'in the form and nothing was changed. These fields differ '
                  'from what is saved now; saving again replaces the saved '
                  'values with yours.',
        ),
        for (final d in differences)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(d.text),
          ),
        TextButton(
          key: const ValueKey('settings:reload'),
          onPressed: onReload,
          child: const Text('Discard my edits and reload'),
        ),
      ],
    ),
  );
}
