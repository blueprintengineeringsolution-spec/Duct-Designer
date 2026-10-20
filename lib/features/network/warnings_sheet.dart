import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../state/project_controller.dart';
import '../inspector/node_inspector_sheet.dart';
import '../schematic/status_colors.dart';

/// Every warning in the project in one list. Tap one to open that section for editing.
void showWarnings(BuildContext context, ProjectController c) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        final entries = collectWarnings(c.units, c.unitResults);
        final t = Theme.of(context).textTheme;
        final multi = c.units.length > 1;
        final children = <Widget>[];
        String? lastUnit;
        for (var i = 0; i < entries.length; i++) {
          final e = entries[i];
          if (multi && e.unitId != lastUnit) {
            lastUnit = e.unitId;
            children.add(Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(e.unitName, style: t.titleSmall),
            ));
          }
          children.add(ListTile(
            key: ValueKey('warning-${e.nodeId}-$i'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              e.status == NodeStatus.critical ? Icons.error_outline : Icons.warning_amber_rounded,
              color: statusColor(e.status),
              semanticLabel: statusWord(e.status),
            ),
            title: Text(e.nodeName),
            subtitle: Text(e.text),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(sheet);
              c.setActiveUnit(e.unitId);
              showNodeInspector(context, c, e.nodeId);
            },
          ));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          shrinkWrap: true,
          children: [
            Text(entries.isEmpty ? 'No warnings' : 'Warnings (${entries.length})', style: t.titleLarge),
            const SizedBox(height: 4),
            if (entries.isEmpty)
              const Text('Every section is within the limits you set.')
            else
              const Text('Tap one to open that section.'),
            ...children,
          ],
        );
      },
    ),
  );
}
