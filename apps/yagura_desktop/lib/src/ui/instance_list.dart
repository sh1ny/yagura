import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../providers.dart';
import '../schema.dart';
import '../transport.dart';
import 'settings_form.dart';

String instanceStateLabel(InstanceState state) => switch (state) {
  InstanceState.INSTANCE_STATE_NOT_INSTALLED => 'not installed',
  InstanceState.INSTANCE_STATE_INSTALLING => 'installing',
  InstanceState.INSTANCE_STATE_STOPPED => 'stopped',
  InstanceState.INSTANCE_STATE_STARTING => 'starting',
  InstanceState.INSTANCE_STATE_RUNNING => 'running',
  InstanceState.INSTANCE_STATE_STOPPING => 'stopping',
  InstanceState.INSTANCE_STATE_UPDATING => 'updating',
  InstanceState.INSTANCE_STATE_ERROR => 'error',
  _ => 'unknown',
};

/// Instances of a daemon with create, install, start, stop and delete actions.
class InstanceListView extends ConsumerWidget {
  const InstanceListView({
    super.key,
    required this.daemonId,
    this.selectedId,
    this.onSelected,
  });

  final String daemonId;
  final String? selectedId;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instancesProvider(daemonId)).value ?? const [];
    final connection = ref.watch(daemonConnectionProvider(daemonId));
    final connected =
        ref.watch(connectionStatusProvider(daemonId)).value is Connected;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Instances',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const ValueKey('action:create'),
                tooltip: 'Create instance',
                icon: const Icon(Icons.add),
                onPressed: connected
                    ? () => _create(context, connection)
                    : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: instances.isEmpty
              ? const Center(child: Text('No instances yet'))
              : ListView.builder(
                  itemCount: instances.length,
                  itemBuilder: (context, index) {
                    final instance = instances[index];
                    return _InstanceTile(
                      instance: instance,
                      selected: instance.id == selectedId,
                      enabled: connected,
                      connection: connection,
                      onTap: onSelected == null
                          ? null
                          : () => onSelected!(instance.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _create(
    BuildContext context,
    DaemonConnection connection,
  ) async {
    final request = await showDialog<({String pluginId, String name})>(
      context: context,
      builder: (_) => _CreateDialog(connection: connection),
    );
    if (request == null || !context.mounted) return;
    await _run(context, () async {
      // A setting that is required and has no default cannot be left for the
      // settings editor: the daemon refuses to create the instance without it.
      final plugin = await connection.transport.getPlugin(request.pluginId);
      final schema = SettingsSchema.tryParse(plugin.settingsSchema.json);
      var settings = const <String, Object?>{};
      if (schema != null && _needsInput(schema.fields)) {
        if (!context.mounted) return;
        final entered = await showDialog<Map<String, Object?>>(
          context: context,
          builder: (_) => _SettingsDialog(
            // Secrets are write-only and set on the instance afterwards.
            schema: SettingsSchema([
              for (final f in schema.fields)
                if (f is! SecretField) f,
            ]),
          ),
        );
        if (entered == null) return;
        settings = entered;
      }
      await connection.createInstance(
        request.pluginId,
        request.name,
        settings: settings,
      );
    });
  }
}

/// Whether the admin has to enter a value before an instance can exist.
bool _needsInput(List<SettingField> fields) => fields.any(
  (f) => switch (f) {
    SecretField() || UnknownField() => false,
    ObjectField(:final fields) => f.required && _needsInput(fields),
    ListField(:final min) => f.required || (min ?? 0) > 0,
    _ => f.required && f.defaultValue == null,
  },
);

/// Runs a daemon call and reports a failure in a snack bar.
Future<void> _run(BuildContext context, Future<void> Function() call) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await call();
  } on DaemonCallException catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text(e.message.isEmpty ? e.reason : e.message)),
    );
  } on StateError catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _InstanceTile extends StatelessWidget {
  const _InstanceTile({
    required this.instance,
    required this.selected,
    required this.enabled,
    required this.connection,
    required this.onTap,
  });

  final Instance instance;
  final bool selected;
  final bool enabled;
  final DaemonConnection connection;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = instance.state;
    final busy = switch (state) {
      InstanceState.INSTANCE_STATE_INSTALLING ||
      InstanceState.INSTANCE_STATE_STARTING ||
      InstanceState.INSTANCE_STATE_STOPPING ||
      InstanceState.INSTANCE_STATE_UPDATING => true,
      _ => false,
    };
    final id = instance.id;
    Widget action(
      String key,
      String tooltip,
      IconData icon,
      VoidCallback run,
    ) => IconButton(
      key: ValueKey('action:$key:$id'),
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: enabled ? run : null,
    );
    return ListTile(
      selected: selected,
      onTap: onTap,
      title: Text(instance.name),
      subtitle: Wrap(
        spacing: 8,
        children: [
          Text(instanceStateLabel(state)),
          if (instance.pluginId.isNotEmpty) Text(instance.pluginId),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!busy) ...[
            if (state == InstanceState.INSTANCE_STATE_NOT_INSTALLED ||
                state == InstanceState.INSTANCE_STATE_ERROR)
              action(
                'install',
                'Install',
                Icons.download,
                () => _run(context, () => connection.install(instance)),
              ),
            if (state == InstanceState.INSTANCE_STATE_STOPPED ||
                state == InstanceState.INSTANCE_STATE_ERROR)
              action(
                'start',
                'Start',
                Icons.play_arrow,
                () => _run(context, () => connection.startInstance(instance)),
              ),
            if (state == InstanceState.INSTANCE_STATE_RUNNING)
              action(
                'stop',
                'Stop',
                Icons.stop,
                () => _run(context, () => connection.stopInstance(instance)),
              ),
            if (state != InstanceState.INSTANCE_STATE_RUNNING)
              action(
                'delete',
                'Delete',
                Icons.delete_outline,
                () => _delete(context),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final choice = await showDialog<({bool deleteFiles, String confirmName})>(
      context: context,
      builder: (_) => _DeleteDialog(name: instance.name),
    );
    if (choice == null || !context.mounted) return;
    await _run(
      context,
      () => connection.deleteInstance(
        instance,
        deleteFiles: choice.deleteFiles,
        confirmName: choice.confirmName,
      ),
    );
  }
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog({required this.connection});

  final DaemonConnection connection;

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  late final Future<List<PluginSummary>> _plugins = widget.connection.transport
      .listPlugins();
  final _name = TextEditingController();
  String? _pluginId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _pluginId != null && _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Create instance'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FutureBuilder<List<PluginSummary>>(
              future: _plugins,
              builder: (context, snapshot) => DropdownButtonFormField<String>(
                key: const ValueKey('create:plugin'),
                decoration: InputDecoration(
                  labelText: 'Game',
                  helperText: snapshot.hasError ? 'Could not load games' : null,
                ),
                items: [
                  for (final p in snapshot.data ?? const <PluginSummary>[])
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name.isEmpty ? p.id : p.name),
                    ),
                ],
                onChanged: (v) => setState(() => _pluginId = v),
              ),
            ),
            TextField(
              key: const ValueKey('create:name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('create:submit'),
          onPressed: valid
              ? () => Navigator.pop(context, (
                  pluginId: _pluginId!,
                  name: _name.text.trim(),
                ))
              : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Asks for the initial settings of an instance about to be created.
class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.schema});

  final SettingsSchema schema;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Initial settings'),
    content: SizedBox(
      width: 560,
      height: 480,
      child: SettingsForm(
        schema: schema,
        values: const {},
        ports: const [],
        onSubmit: (submission) => Navigator.pop(context, submission.settings),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.name});

  final String name;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _deleteFiles = false;
  String _confirm = '';

  @override
  Widget build(BuildContext context) {
    final valid = !_deleteFiles || _confirm == widget.name;
    return AlertDialog(
      title: Text('Delete ${widget.name}?'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              key: const ValueKey('delete:files'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Also delete its files'),
              subtitle: const Text(
                'A snapshot of its data is kept for 30 days.',
              ),
              value: _deleteFiles,
              onChanged: (v) => setState(() => _deleteFiles = v ?? false),
            ),
            if (_deleteFiles)
              TextField(
                key: const ValueKey('delete:confirm'),
                decoration: InputDecoration(
                  labelText: 'Type "${widget.name}" to confirm',
                ),
                onChanged: (v) => setState(() => _confirm = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('delete:submit'),
          onPressed: valid
              ? () => Navigator.pop(context, (
                  deleteFiles: _deleteFiles,
                  confirmName: _deleteFiles ? _confirm : '',
                ))
              : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
