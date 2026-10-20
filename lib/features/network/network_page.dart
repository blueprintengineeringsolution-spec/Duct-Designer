import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../state/auto_saver.dart';
import '../../state/project_controller.dart';
import '../inspector/critical_path_card.dart';
import '../inspector/node_inspector_sheet.dart';
import '../schematic/schematic_canvas.dart';
import 'unit_bar.dart';
import 'warnings_sheet.dart';

/// The project's duct network as a diagram. Tap a section to select it, double-tap to edit it
/// (name, size, flow, fittings, add, duplicate, delete); the + handle beside the selected section
/// adds a child.
class NetworkPage extends StatefulWidget {
  final ProjectController c;
  final ValueListenable<SaveStatus>? saveStatus;
  const NetworkPage({super.key, required this.c, this.saveStatus});
  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  void _showCriticalPath(BuildContext context) {
    final c = widget.c;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListenableBuilder(
          listenable: c,
          builder: (_, __) => CriticalPathCard(
            c: c,
            onOpen: (id) {
              Navigator.pop(sheet);
              showNodeInspector(context, c, id);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final warnCount = c.unitResults.values.fold(0, (a, r) => a + r.warningCount);
        return Scaffold(
          appBar: AppBar(
            title: Text(c.name),
            actions: [
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: c.canUndo ? c.undo : null,
              ),
              IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: c.canRedo ? c.redo : null,
              ),
              IconButton(
                tooltip: 'Warnings ($warnCount)',
                icon: Badge(
                  isLabelVisible: warnCount > 0,
                  label: Text('$warnCount'),
                  child: const Icon(Icons.warning_amber_outlined),
                ),
                onPressed: () => showWarnings(context, c),
              ),
              if (widget.saveStatus != null)
                ValueListenableBuilder<SaveStatus>(
                  valueListenable: widget.saveStatus!,
                  builder: (context, st, child) => Tooltip(
                    message: switch (st) {
                      SaveStatus.saved => 'Saved on this device',
                      SaveStatus.pending || SaveStatus.saving => 'Saving…',
                      SaveStatus.error => 'Could not save. Will retry on the next change.',
                    },
                    child: Icon(switch (st) {
                      SaveStatus.saved => Icons.cloud_done_outlined,
                      SaveStatus.pending || SaveStatus.saving => Icons.sync,
                      SaveStatus.error => Icons.error_outline,
                    }),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ActionChip(
                  tooltip: 'Show the critical path of ${c.root.name}',
                  label: Text('Fan SP ${c.fmt.pressure(c.result.requiredFanPa)}'),
                  onPressed: () => _showCriticalPath(context),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => c.addChild(c.selectedId ?? c.root.id),
            icon: const Icon(Icons.add),
            label: const Text('Add Node'),
          ),
          body: Column(children: [
            UnitBar(c: c),
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
                    onPressed: () => showNodeInspector(context, c, c.selectedId!),
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
                onNodeTap: c.select,
                onNodeDoubleTap: (id) => showNodeInspector(context, c, id),
                onNodeLongPress: c.toggleCollapsed,
                onAddChild: c.addChild,
                onBackgroundTap: () => c.select(null),
              ),
            ),
          ]),
        );
      },
    );
  }
}
