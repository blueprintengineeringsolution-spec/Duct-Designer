import 'package:hvac_engine/hvac_engine.dart';

DuctNode? findNode(DuctNode n, String id) {
  if (n.id == id) return n;
  for (final c in n.children) {
    final f = findNode(c, id);
    if (f != null) return f;
  }
  return null;
}

String? parentIdOf(DuctNode root, String id) {
  for (final c in root.children) {
    if (c.id == id) return root.id;
    final p = parentIdOf(c, id);
    if (p != null) return p;
  }
  return null;
}

DuctNode mapNode(DuctNode n, String id, DuctNode Function(DuctNode) f) {
  if (n.id == id) return f(n);
  return n.copyWith(children: [for (final c in n.children) mapNode(c, id, f)]);
}

DuctNode removeNode(DuctNode n, String id) =>
    n.copyWith(children: [for (final c in n.children) if (c.id != id) removeNode(c, id)]);

DuctNode cloneWithNewIds(DuctNode n, String Function() nextId, {bool top = true}) => n.copyWith(
      id: nextId(),
      name: top ? '${n.name} copy' : n.name,
      children: [for (final c in n.children) cloneWithNewIds(c, nextId, top: false)],
    );

Iterable<DuctNode> allNodes(DuctNode n) sync* {
  yield n;
  for (final c in n.children) {
    yield* allNodes(c);
  }
}

/// Index of the unit (root) whose tree contains [id], or -1. A unit's own id counts.
int unitIndexContaining(List<DuctNode> units, String id) {
  for (var i = 0; i < units.length; i++) {
    if (findNode(units[i], id) != null) return i;
  }
  return -1;
}
