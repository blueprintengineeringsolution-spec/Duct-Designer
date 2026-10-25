import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../inspector/presentation/critical_path_card.dart';
import '../../inspector/presentation/node_inspector_sheet.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../projects/domain/auto_saver.dart';
import '../../projects/presentation/providers/auto_save_notifier.dart';
import '../../schematic/presentation/schematic_canvas.dart';
import 'unit_bar.dart';
import 'warnings_sheet.dart';

/// The project's duct network as a diagram. Tap a section to select it, double-tap to edit it
/// (name, size, flow, fittings, add, duplicate, delete); the + handle beside the selected section
/// adds a child.
class NetworkPage extends ConsumerWidget {
  const NetworkPage({super.key});

  void _showCriticalPath(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: CriticalPathCard(
          onOpen: (id) {
            Navigator.pop(sheet);
            showNodeInspector(context, ref, id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currentProjectProvider);
    final n = ref.read(projectEditorProvider.notifier);
    final saveStatus = ref.watch(autoSaveProvider);
    final warnCount =
        c.unitResults.values.fold(0, (a, r) => a + r.warningCount);
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: c.canUndo ? n.undo : null,
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
            onPressed: c.canRedo ? n.redo : null,
          ),
          IconButton(
            tooltip: 'Warnings ($warnCount)',
            icon: Badge(
              isLabelVisible: warnCount > 0,
              label: Text('$warnCount'),
              child: const Icon(Icons.warning_amber_outlined),
            ),
            onPressed: () => showWarnings(context),
          ),
          if (saveStatus != null)
            Tooltip(
              message: switch (saveStatus) {
                SaveStatus.saved => 'Saved on this device',
                SaveStatus.pending || SaveStatus.saving => 'Saving…',
                SaveStatus.error =>
                  'Could not save. Will retry on the next change.',
              },
              child: Icon(switch (saveStatus) {
                SaveStatus.saved => Icons.cloud_done_outlined,
                SaveStatus.pending || SaveStatus.saving => Icons.sync,
                SaveStatus.error => Icons.error_outline,
              }),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              tooltip: 'Show the critical path of ${c.root.name}',
              label: Text('Fan SP ${c.fmt.pressure(c.result.requiredFanPa)}'),
              onPressed: () => _showCriticalPath(context, ref),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => n.addChild(c.selectedId ?? c.root.id),
        icon: const Icon(Icons.add),
        label: const Text('Add Node'),
      ),
      body: Column(children: [
        const UnitBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                'Tap to select, double-tap to edit, long-press to collapse.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (c.selectedId != null)
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit section'),
                onPressed: () => showNodeInspector(context, ref, c.selectedId!),
              ),
          ]),
        ),
        Expanded(
          child: SchematicCanvas(
            root: c.root,
            result: c.result,
            collapsed: c.collapsed,
            selectedId: c.selectedId,
            fmt: c.fmt,
            defaultJunction: c.settings.defaultJunction,
            onNodeTap: n.select,
            onNodeDoubleTap: (id) => showNodeInspector(context, ref, id),
            onNodeLongPress: n.toggleCollapsed,
            onAddChild: n.addChild,
            onBackgroundTap: () => n.select(null),
          ),
        ),
      ]),
    );
  }
}
