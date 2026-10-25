import 'dart:math' as math;
import 'dart:ui';
import 'package:hvac_engine/hvac_engine.dart';

class LayoutConfig {
  final double nodeW, nodeH, colGap, rowGap, padding;
  const LayoutConfig({
    this.nodeW = 148,
    this.nodeH = 66,
    this.colGap = 76,
    this.rowGap = 20,
    this.padding = 32,
  });
}

class LaidOutNode {
  final DuctNode node;
  final Rect rect;
  final int depth;
  final String? parentId;
  final bool collapsedWithChildren;
  const LaidOutNode(this.node, this.rect, this.depth, this.parentId, this.collapsedWithChildren);
}

class SchematicLayout {
  final List<LaidOutNode> nodes;
  final Size size;
  final Map<String, LaidOutNode> _byId;
  SchematicLayout(this.nodes, this.size) : _byId = {for (final n in nodes) n.node.id: n};

  LaidOutNode? byId(String id) => _byId[id];

  /// Tap target of the "+" handle shown beside the selected node (adds a child).
  Rect plusRect(LaidOutNode n) => Rect.fromCircle(center: n.rect.centerRight + const Offset(16, 0), radius: 18);

  LaidOutNode? hitTest(Offset p) {
    for (final n in nodes.reversed) {
      if (n.rect.contains(p)) return n;
    }
    return null;
  }
}

class _Tmp {
  final DuctNode node;
  final int depth;
  final String? parentId;
  final bool collapsed;
  double y = 0;
  _Tmp(this.node, this.depth, this.parentId, this.collapsed);
}

/// Left-to-right tidy tree: depth sets x, leaves take consecutive rows,
/// parents sit at the mean row of their children. Collapsed nodes hide children.
SchematicLayout layoutNetwork(
  DuctNode root, {
  Set<String> collapsed = const {},
  LayoutConfig cfg = const LayoutConfig(),
}) {
  final tmp = <_Tmp>[];
  var leaves = 0;
  var maxDepth = 0;

  double place(DuctNode n, int depth, String? parentId) {
    maxDepth = math.max(maxDepth, depth);
    final isCollapsed = collapsed.contains(n.id) && n.children.isNotEmpty;
    final t = _Tmp(n, depth, parentId, isCollapsed);
    tmp.add(t);
    final kids = isCollapsed ? const <DuctNode>[] : n.children;
    if (kids.isEmpty) {
      t.y = leaves.toDouble();
      leaves++;
    } else {
      final ys = [for (final c in kids) place(c, depth + 1, n.id)];
      t.y = (ys.first + ys.last) / 2;
    }
    return t.y;
  }

  place(root, 0, null);

  final rows = math.max(leaves, 1);
  final laid = [
    for (final t in tmp)
      LaidOutNode(
        t.node,
        Rect.fromLTWH(
          cfg.padding + t.depth * (cfg.nodeW + cfg.colGap),
          cfg.padding + t.y * (cfg.nodeH + cfg.rowGap),
          cfg.nodeW,
          cfg.nodeH,
        ),
        t.depth,
        t.parentId,
        t.collapsed,
      ),
  ];
  final size = Size(
    cfg.padding * 2 + (maxDepth + 1) * cfg.nodeW + maxDepth * cfg.colGap,
    cfg.padding * 2 + rows * cfg.nodeH + (rows - 1) * cfg.rowGap,
  );
  return SchematicLayout(laid, size);
}
