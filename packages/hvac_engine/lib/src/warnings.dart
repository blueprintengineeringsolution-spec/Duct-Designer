import 'network.dart';

/// One warning on one section, with where it is.
class WarningEntry {
  final String unitId, unitName, nodeId, nodeName, text;
  final NodeStatus status; // the section's status
  const WarningEntry({
    required this.unitId,
    required this.unitName,
    required this.nodeId,
    required this.nodeName,
    required this.text,
    required this.status,
  });
}

List<DuctNode> _inOrder(DuctNode n) => [n, for (final c in n.children) ..._inOrder(c)];

/// Every warning in the project. Units keep their order; inside a unit, sections that are over
/// a limit come before sections that only need a look, and tree order is kept within each.
List<WarningEntry> collectWarnings(List<DuctNode> units, Map<String, NetworkResult> results) {
  final out = <WarningEntry>[];
  for (final u in units) {
    final res = results[u.id];
    if (res == null) continue;
    final critical = <WarningEntry>[];
    final other = <WarningEntry>[];
    for (final n in _inOrder(u)) {
      final r = res.nodes[n.id];
      if (r == null) continue;
      for (final w in r.warnings) {
        final e = WarningEntry(
          unitId: u.id,
          unitName: u.name,
          nodeId: n.id,
          nodeName: n.name,
          text: w,
          status: r.status,
        );
        (r.status == NodeStatus.critical ? critical : other).add(e);
      }
    }
    out
      ..addAll(critical)
      ..addAll(other);
  }
  return out;
}
