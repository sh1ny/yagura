import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'connection_banner.dart';
import 'instance_list.dart';
import 'log_view.dart';
import 'operations_panel.dart';
import 'settings_editor.dart';

/// Window width from which the list and the detail sit side by side.
const double _wideBreakpoint = 900;

/// Daemon page: instance list and, for the selected instance, settings and logs.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.daemonId});

  final String daemonId;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selected;

  void _select(String id, {required bool wide}) {
    if (wide) {
      setState(() => _selected = id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Instance')),
          body: InstanceDetail(daemonId: widget.daemonId, instanceId: id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daemonId = widget.daemonId;
    return Scaffold(
      appBar: AppBar(title: const Text('Yagura')),
      body: Column(
        children: [
          ConnectionBanner(daemonId: daemonId),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                final list = Column(
                  children: [
                    Expanded(
                      child: InstanceListView(
                        daemonId: daemonId,
                        selectedId: wide ? _selected : null,
                        onSelected: (id) => _select(id, wide: wide),
                      ),
                    ),
                    SizedBox(
                      height: 180,
                      child: OperationsPanel(daemonId: daemonId),
                    ),
                  ],
                );
                if (!wide) return list;
                final selected = _selected;
                return Row(
                  children: [
                    SizedBox(width: 380, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected == null
                          ? const Center(child: Text('Select an instance'))
                          : InstanceDetail(
                              key: ValueKey(selected),
                              daemonId: daemonId,
                              instanceId: selected,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings and logs of one instance.
class InstanceDetail extends ConsumerWidget {
  const InstanceDetail({
    super.key,
    required this.daemonId,
    required this.instanceId,
  });

  final String daemonId;
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instancesProvider(daemonId)).value ?? const [];
    final instance = instances.where((i) => i.id == instanceId).firstOrNull;
    if (instance == null) {
      return const Center(child: Text('This instance no longer exists'));
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                instance.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Settings'),
              Tab(text: 'Logs'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SettingsEditor(
                  key: ValueKey(instance.id),
                  daemonId: daemonId,
                  instance: instance,
                ),
                LogView(daemonId: daemonId, instanceId: instance.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
