import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../providers.dart';
import '../transport.dart';

const _workshop = 'steam_workshop';

/// One mod of the list being edited.
final class _Entry {
  const _Entry(this.source, this.itemId, this.role);

  final String source;
  final String itemId;
  final String role;

  _Entry withRole(String role) => _Entry(source, itemId, role);

  bool sameItem(_Entry other) =>
      source == other.source && itemId == other.itemId;
}

/// Workshop ids from pasted text: bare ids and `...?id=<id>` links separated by
/// whitespace, commas or semicolons; [invalid] lists the pieces that are
/// neither.
({List<String> ids, List<String> invalid}) parseWorkshopIds(String text) {
  final ids = <String>[];
  final invalid = <String>[];
  for (final token in text.split(RegExp(r'[\s,;]+'))) {
    if (token.isEmpty) continue;
    final id =
        RegExp(r'[?&]id=(\d+)').firstMatch(token)?.group(1) ??
        (RegExp(r'^\d+$').hasMatch(token) ? token : null);
    if (id == null) {
      invalid.add(token);
    } else if (!ids.contains(id)) {
      ids.add(id);
    }
  }
  return (ids: ids, invalid: invalid);
}

String _warningText(String warning) => switch (warning.split(':')) {
  ['key_conflict', ...final rest] => 'Key conflict: ${rest.join(':')}',
  _ => warning,
};

String _reason(DaemonCallException e) =>
    e.message.isEmpty ? e.reason : e.message;

/// An instance's mods in load order per role: add by workshop id or link,
/// remove, reorder, change roles, apply, check for updates and update.
class ModsView extends ConsumerStatefulWidget {
  const ModsView({super.key, required this.daemonId, required this.instance});

  final String daemonId;
  final Instance instance;

  @override
  ConsumerState<ModsView> createState() => _ModsViewState();
}

class _ModsViewState extends ConsumerState<ModsView> {
  final _ids = TextEditingController();
  bool _loading = true;
  String? _loadError;
  bool _supportsMods = true;
  List<String> _roles = const [];
  String _addRole = '';

  /// The mods as the daemon has them.
  List<Mod> _saved = const [];

  /// The list being edited, in load order.
  List<_Entry> _draft = const [];

  /// The instance revision the saved list was read at: a save is checked
  /// against it, so another device's change is never overwritten silently.
  Int64 _revision = Int64.ZERO;
  bool _saving = false;
  String? _error;

  /// After a `revision_conflict`: what the admin changed, still unsaved.
  List<String>? _conflict;

  @override
  void initState() {
    super.initState();
    _revision = widget.instance.revision;
    unawaited(_load());
  }

  @override
  void dispose() {
    _ids.dispose();
    super.dispose();
  }

  List<_Entry> _entriesOf(List<Mod> mods) => [
    for (final m in mods) _Entry(m.source, m.itemId, m.role),
  ];

  Mod? _savedFor(_Entry e) => _saved
      .where((m) => m.source == e.source && m.itemId == e.itemId)
      .firstOrNull;

  Future<void> _load() async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    try {
      final transport = await connection.whenConnected();
      final plugin = await transport.getPlugin(widget.instance.pluginId);
      final supports = plugin.summary.supportsMods;
      final list = supports
          ? await transport.listMods(widget.instance.id)
          : ListModsResponse();
      if (!mounted) return;
      setState(() {
        _supportsMods = supports;
        _roles = plugin.modRoles;
        _addRole = _roles.firstOrNull ?? '';
        _saved = list.mods;
        _draft = _entriesOf(list.mods);
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is DaemonCallException ? _reason(e) : '$e';
        _loading = false;
      });
    }
  }

  bool get _dirty {
    final saved = _entriesOf(_saved);
    if (saved.length != _draft.length) return true;
    for (var i = 0; i < saved.length; i++) {
      if (!saved[i].sameItem(_draft[i]) || saved[i].role != _draft[i].role) {
        return true;
      }
    }
    return false;
  }

  void _add() {
    final parsed = parseWorkshopIds(_ids.text);
    if (parsed.invalid.isNotEmpty) {
      setState(
        () =>
            _error = 'Not a workshop id or link: ${parsed.invalid.join(', ')}',
      );
      return;
    }
    setState(() {
      _error = null;
      _draft = [
        ..._draft,
        for (final id in parsed.ids)
          if (!_draft.any((e) => e.source == _workshop && e.itemId == id))
            _Entry(_workshop, id, _addRole),
      ];
      _ids.clear();
    });
  }

  /// Swaps [entry] with its neighbour of the same role.
  void _move(_Entry entry, int direction) {
    final index = _draft.indexOf(entry);
    var other = index + direction;
    while (other >= 0 &&
        other < _draft.length &&
        _draft[other].role != entry.role) {
      other += direction;
    }
    if (other < 0 || other >= _draft.length) return;
    setState(() {
      final list = [..._draft];
      list[index] = list[other];
      list[other] = entry;
      _draft = list;
    });
  }

  Future<void> _save() async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final transport = connection.transport;
      final response = await transport.setMods(
        SetModsRequest(
          instanceId: widget.instance.id,
          expectedRevision: _revision,
          mods: [
            for (final e in _draft)
              ModRef(source: e.source, itemId: e.itemId, role: e.role),
          ],
        ),
      );
      // The save moved the revision: the next one is checked against it.
      var revision = _revision + 1;
      try {
        revision = (await transport.getInstance(widget.instance.id)).revision;
      } on Object {
        // One past the old revision is the best there is.
      }
      if (!mounted) return;
      setState(() {
        _saved = response.mods;
        _draft = _entriesOf(response.mods);
        _revision = revision;
        _conflict = null;
      });
    } on DaemonCallException catch (e) {
      if (e.reason == 'revision_conflict') {
        await _onConflict(connection);
      } else if (mounted) {
        setState(() => _error = _reason(e));
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Someone else changed the mods first: loads the list as it is now, keeps
  /// the admin's edits and says what they were. The next save goes against the
  /// revision just loaded.
  Future<void> _onConflict(DaemonConnection connection) async {
    final mine = _changesFrom(_entriesOf(_saved), _draft);
    try {
      final transport = connection.transport;
      final current = await transport.getInstance(widget.instance.id);
      final list = await transport.listMods(widget.instance.id);
      if (!mounted) return;
      setState(() {
        _saved = list.mods;
        _revision = current.revision;
        _conflict = mine;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            'Someone else changed the mods, and the list could not be '
            'reloaded: ${e is DaemonCallException ? _reason(e) : e}',
      );
    }
  }

  static List<String> _changesFrom(List<_Entry> before, List<_Entry> after) {
    final changes = <String>[];
    for (final e in after) {
      final old = before.where((b) => b.sameItem(e)).firstOrNull;
      if (old == null) {
        changes.add('add ${e.itemId}');
      } else if (old.role != e.role) {
        changes.add('${e.itemId}: role ${old.role} to ${e.role}');
      }
    }
    for (final b in before) {
      if (!after.any((e) => e.sameItem(b))) changes.add('remove ${b.itemId}');
    }
    final common = [
      for (final e in after)
        if (before.any((b) => b.sameItem(e))) e.itemId,
    ];
    final was = [
      for (final b in before)
        if (after.any((e) => e.sameItem(b))) b.itemId,
    ];
    if (common.join(',') != was.join(',')) changes.add('new load order');
    return changes;
  }

  void _discard() => setState(() {
    _draft = _entriesOf(_saved);
    _conflict = null;
    _error = null;
  });

  Future<void> _run(Future<void> Function() call) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await call();
    } on DaemonCallException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(_reason(e))));
    } on StateError catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(child: Text('Could not load the mods: $_loadError'));
    }
    if (!_supportsMods) {
      return const Center(child: Text('This game does not use mods.'));
    }
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    final dirty = _dirty;
    final roles = [
      ..._roles,
      for (final r in {for (final e in _draft) e.role})
        if (!_roles.contains(r)) r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_conflict case final mine?)
          _ConflictPanel(changes: mine, onDiscard: _discard),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('mods:ids'),
                  controller: _ids,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Workshop ids or links',
                    helperText: 'One per line, or separated by commas.',
                  ),
                ),
              ),
              if (_roles.length > 1) ...[
                const SizedBox(width: 12),
                DropdownButton<String>(
                  key: const ValueKey('mods:role'),
                  value: _addRole,
                  items: [
                    for (final r in _roles)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (r) => setState(() => _addRole = r ?? _addRole),
                ),
              ],
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  key: const ValueKey('mods:add'),
                  onPressed: _add,
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('mods:save'),
                onPressed: dirty && !_saving ? () => unawaited(_save()) : null,
                child: const Text('Save'),
              ),
              OutlinedButton(
                key: const ValueKey('mods:apply'),
                onPressed: dirty
                    ? null
                    : () => unawaited(
                        _run(() => connection.applyMods(widget.instance)),
                      ),
                child: const Text('Apply'),
              ),
              OutlinedButton(
                key: const ValueKey('mods:check'),
                onPressed: dirty
                    ? null
                    : () => unawaited(
                        _run(() => connection.checkModUpdates(widget.instance)),
                      ),
                child: const Text('Check for updates'),
              ),
              OutlinedButton(
                key: const ValueKey('mods:update'),
                onPressed: dirty
                    ? null
                    : () => unawaited(
                        _run(() => connection.updateMods(widget.instance)),
                      ),
                child: const Text('Update'),
              ),
            ],
          ),
        ),
        if (_saving) const LinearProgressIndicator(),
        Expanded(
          child: _draft.isEmpty
              ? const Center(child: Text('No mods yet'))
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final role in roles)
                      if (_draft.any((e) => e.role == role)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                          child: Text(
                            role.isEmpty ? 'Mods' : role,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        for (final entry in _draft.where((e) => e.role == role))
                          _ModTile(
                            entry: entry,
                            mod: _savedFor(entry),
                            roles: _roles,
                            onMove: (d) => _move(entry, d),
                            onRole: (r) => setState(() {
                              _draft = [
                                for (final e in _draft)
                                  if (identical(e, entry)) e.withRole(r) else e,
                              ];
                            }),
                            onRemove: () => setState(
                              () => _draft = [
                                for (final e in _draft)
                                  if (!identical(e, entry)) e,
                              ],
                            ),
                          ),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ModTile extends StatelessWidget {
  const _ModTile({
    required this.entry,
    required this.mod,
    required this.roles,
    required this.onMove,
    required this.onRole,
    required this.onRemove,
  });

  final _Entry entry;
  final Mod? mod;
  final List<String> roles;
  final ValueChanged<int> onMove;
  final ValueChanged<String> onRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mod = this.mod;
    final id = entry.itemId;
    final staged = mod?.stagedVersion ?? '';
    final desired = mod?.desiredVersion ?? '';
    return Card(
      key: ValueKey('mod:$id'),
      child: ListTile(
        title: Text(
          mod != null && mod.name.isNotEmpty ? mod.name : 'Workshop item $id',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mod?.status.isNotEmpty == true ? mod!.status : 'not saved'),
            if (staged.isNotEmpty || desired.isNotEmpty)
              Text(
                staged == desired || desired.isEmpty
                    ? 'Version $staged'
                    : 'Version ${staged.isEmpty ? 'none' : staged} '
                          '(next start: $desired)',
              ),
            if (mod?.updateAvailable == true) const Text('Update available'),
            for (final w in mod?.warnings ?? const <String>[])
              Text(_warningText(w), style: TextStyle(color: scheme.error)),
            if (mod != null && mod.lastError.isNotEmpty)
              Text(mod.lastError, style: TextStyle(color: scheme.error)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (roles.length > 1)
              DropdownButton<String>(
                key: ValueKey('mod:role:$id'),
                value: roles.contains(entry.role) ? entry.role : null,
                items: [
                  for (final r in roles)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (r) {
                  if (r != null) onRole(r);
                },
              ),
            IconButton(
              key: ValueKey('mod:up:$id'),
              tooltip: 'Load earlier',
              icon: const Icon(Icons.arrow_upward),
              onPressed: () => onMove(-1),
            ),
            IconButton(
              key: ValueKey('mod:down:$id'),
              tooltip: 'Load later',
              icon: const Icon(Icons.arrow_downward),
              onPressed: () => onMove(1),
            ),
            IconButton(
              key: ValueKey('mod:remove:$id'),
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictPanel extends StatelessWidget {
  const _ConflictPanel({required this.changes, required this.onDiscard});

  final List<String> changes;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('mods:conflict'),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Someone else changed the mods first and nothing was saved. The '
          'list was reloaded; your unsaved changes are still below. Saving '
          'again replaces the saved list with yours.',
        ),
        for (final change in changes)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text('Your change: $change'),
          ),
        TextButton(
          key: const ValueKey('mods:reload'),
          onPressed: onDiscard,
          child: const Text('Discard my changes'),
        ),
      ],
    ),
  );
}
