import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../providers.dart';

/// The operations after which the daemon has written the bound files.
const _configPasses = {
  'start',
  'restart',
  'apply_config',
  'apply_mods',
  'update',
};

/// The fields a `settings_invalid` notice names, by path. The daemon's message
/// is `path: reason; path: reason`; a hook error has no such shape and names
/// no field.
Map<String, String> invalidFieldsOf(String? message) {
  final fields = <String, String>{};
  for (final part in (message ?? '').split('; ')) {
    final at = part.indexOf(': ');
    if (at <= 0) continue;
    final path = part.substring(0, at);
    if (RegExp(r'^[A-Za-z0-9_.\[\]]+$').hasMatch(path)) {
      fields[path] = part.substring(at + 2);
    }
  }
  return fields;
}

/// What the daemon wants the admin to know about one instance: configuration
/// files edited by hand and overwritten at the last start, and settings that
/// no longer validate.
class InstanceNotices extends ConsumerWidget {
  const InstanceNotices({
    super.key,
    required this.daemonId,
    required this.instance,
  });

  final String daemonId;
  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invalid = ref.watch(settingsInvalidProvider(daemonId)).value;
    final operations = [
      for (final o
          in ref.watch(operationsProvider(daemonId)).value ??
              const <OperationState>[])
        if (o.instanceId == instance.id &&
            o.ended &&
            _configPasses.contains(o.kind))
          o,
    ];
    // Only the latest pass counts: a later start that overwrote nothing
    // clears the notice.
    final edits = [
      for (final w in operations.lastOrNull?.warnings ?? const <String>[])
        if (w.startsWith('external_edit'))
          w.replaceFirst(RegExp(r'^external_edit:?\s*'), ''),
    ];
    final reason = invalid?[instance.id];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (instance.settingsInvalid)
          _Notice(
            key: ValueKey('notice:settings_invalid:${instance.id}'),
            color: scheme.errorContainer,
            lines: [
              reason == null
                  ? 'The settings are no longer valid. Fix them in Settings '
                        'and save; the instance cannot start until then.'
                  : 'The settings are no longer valid: $reason. Fix them in '
                        'Settings and save; the instance cannot start until '
                        'then.',
            ],
          ),
        if (edits.isNotEmpty)
          _Notice(
            key: ValueKey('notice:external_edit:${instance.id}'),
            color: scheme.tertiaryContainer,
            header: 'Edited by hand since the last start, and overwritten:',
            lines: edits,
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.color,
    required this.lines,
    this.header,
  });

  final Color color;
  final String? header;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) Text(header!),
          for (final line in lines) Text(line),
        ],
      ),
    ),
  );
}
