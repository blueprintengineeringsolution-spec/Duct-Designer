import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../project_editor/domain/project_editor_state.dart';
import '../../project_editor/domain/tree_ops.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../schematic/presentation/status_colors.dart';

/// The run that sets the fan pressure, section by section, with the running total.
class CriticalPathCard extends ConsumerWidget {
  final String? highlightId;
  final ValueChanged<String>? onOpen;
  final String? unitId; // null = the active unit
  final String? title;
  const CriticalPathCard({super.key, this.highlightId, this.onOpen, this.unitId, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currentProjectProvider);
    final root = unitId == null ? c.root : c.units.firstWhere((u) => u.id == unitId, orElse: () => c.root);
    final res = unitId == null ? c.result : (c.unitResults[unitId] ?? c.result);
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final fmt = c.fmt;
    final path = res.criticalPath;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title == null ? 'Critical path' : 'Critical path · $title', style: t.titleSmall),
          const SizedBox(height: 2),
          Text('The run that sets the fan pressure', style: t.bodySmall),
          const SizedBox(height: 8),
          for (var i = 0; i < path.length; i++)
            _row(context, c, root, res, path[i], isLast: i == path.length - 1),
          const Divider(height: 20),
          Row(children: [
            Expanded(child: Text('Total system', style: t.titleSmall)),
            Text(fmt.pressure(res.requiredFanPa), style: t.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ProjectEditorState c,
    DuctNode root,
    NetworkResult results,
    String id, {
    required bool isLast,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final node = findNode(root, id);
    final res = results.nodes[id];
    if (node == null || res == null) return const SizedBox.shrink();
    final current = id == highlightId;
    return InkWell(
      onTap: onOpen == null ? null : () => onOpen!(id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 18,
              child: Column(children: [
                const SizedBox(height: 8),
                CircleAvatar(radius: 5, backgroundColor: statusColor(res.status)),
                if (!isLast) Expanded(child: Container(width: 2, color: scheme.outlineVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w400, color: current ? scheme.primary : null),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(c.fmt.pressure(res.cumulativePa), style: Theme.of(context).textTheme.bodySmall),
            ),
          ]),
        ),
      ),
    );
  }
}
