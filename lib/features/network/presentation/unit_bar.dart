import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../project_editor/domain/project_editor_state.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../schematic/presentation/status_colors.dart';

/// Switches between the units (air handling units, each its own duct network) of a project,
/// and adds, renames, duplicates and deletes them.
class UnitBar extends ConsumerWidget {
  const UnitBar({super.key});

  Future<String?> _askName(BuildContext context, String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename unit'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Unit name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete unit?'),
        content: Text('"$name" and all of its sections will be removed. You can undo this.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return r ?? false;
  }

  /// A chip with a status dot: the worst status of any section in that unit.
  Widget _chip(ProjectEditorState c, ProjectEditorNotifier n, DuctNode u) {
    final res = c.unitResults[u.id];
    final status = res?.worstStatus ?? NodeStatus.optimal;
    final warnings = res?.warningCount ?? 0;
    return ChoiceChip(
      key: ValueKey('unit-${u.id}'),
      tooltip: '${u.name}: ${statusWord(status)}${warnings > 0 ? ', $warnings warning${warnings == 1 ? '' : 's'}' : ''}',
      avatar: CircleAvatar(radius: 5, backgroundColor: statusColor(status)),
      showCheckmark: false,
      label: Text(u.name),
      selected: u.id == c.activeUnitId,
      onSelected: (_) => n.setActiveUnit(u.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currentProjectProvider);
    final n = ref.read(projectEditorProvider.notifier);
    final units = c.units;
    final active = c.root;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final u in units)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _chip(c, n, u),
                ),
            ]),
          ),
        ),
        IconButton(
          tooltip: 'Add unit',
          icon: const Icon(Icons.add_box_outlined),
          onPressed: () {
            if (n.addUnit() == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This project has the most units allowed.')));
            }
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'Unit actions',
          onSelected: (v) async {
            switch (v) {
              case 'rename':
                final name = await _askName(context, active.name);
                if (name != null) n.renameUnit(active.id, name);
              case 'dup':
                n.duplicateUnit(active.id);
              case 'del':
                if (await _confirmDelete(context, active.name)) n.deleteUnit(active.id);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename unit')),
            const PopupMenuItem(value: 'dup', child: Text('Duplicate unit')),
            PopupMenuItem(value: 'del', enabled: units.length > 1, child: const Text('Delete unit')),
          ],
        ),
      ]),
    );
  }
}
