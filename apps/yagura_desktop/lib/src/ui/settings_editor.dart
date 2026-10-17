import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

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
  });

  final String daemonId;
  final Instance instance;

  @override
  ConsumerState<SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends ConsumerState<SettingsEditor> {
  bool _loading = true;
  String? _loadError;
  SettingsSchema? _schema;
  int _schemaVersion = 0;
  Map<String, String> _violations = const {};
  String? _error;
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
      for (final MapEntry(:key, :value) in submission.secrets.entries) {
        updated = await transport.setSecret(
          SetSecretRequest(
            instanceId: instance.id,
            expectedRevision: updated.revision,
            key: key,
            value: value,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _violations = const {};
        _editing = updated;
      });
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Settings saved')));
    } on DaemonCallException catch (e) {
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

  void _reload() => setState(() {
    _editing = widget.instance;
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
        if (widget.instance.revision != _editing.revision)
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
