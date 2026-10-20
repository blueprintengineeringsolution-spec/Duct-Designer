import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../state/project_controller.dart';
import '../../state/tree_ops.dart';
import '../schematic/status_colors.dart';

/// The run that sets the fan pressure, section by section, with the running total.
class CriticalPathCard extends StatelessWidget {
  final ProjectController c;
  final String? highlightId;
  final ValueChanged<String>? onOpen;
  final String? unitId; // null = the active unit
  final String? title;
  const CriticalPathCard({super.key, required this.c, this.highlightId, this.onOpen, this.unitId, this.title});

  DuctNode get _root => unitId == null ? c.root : c.units.firstWhere((u) => u.id == unitId, orElse: () => c.root);
  NetworkResult get _res => unitId == null ? c.result : (c.unitResults[unitId] ?? c.result);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final fmt = c.fmt;
    final path = _res.criticalPath;

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
            _row(context, path[i], isLast: i == path.length - 1),
          const Divider(height: 20),
          Row(children: [
            Expanded(child: Text('Total system', style: t.titleSmall)),
            Text(fmt.pressure(_res.requiredFanPa), style: t.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, String id, {required bool isLast}) {
    final scheme = Theme.of(context).colorScheme;
    final node = findNode(_root, id);
    final res = _res.nodes[id];
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
