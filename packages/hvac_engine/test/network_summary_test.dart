import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

const unit = DuctNode(id: 'r', name: 'R', lengthM: 3, children: [
  DuctNode(id: 'a', name: 'A', flow: 0.2, lengthM: 4),
  DuctNode(id: 'b', name: 'B', flow: 0.3, lengthM: 4),
]);

void main() {
  test('a calm network is OK with no warnings', () {
    final r = computeNetwork(unit, const EngineSettings());
    expect(r.worstStatus, NodeStatus.optimal);
    expect(r.warningCount, 0);
    expect(r.sectionCount, 3);
  });

  test('a low velocity limit makes the worst status over limit and counts the warnings', () {
    final r = computeNetwork(unit, const EngineSettings(maxVelocity: 1.5));
    expect(r.worstStatus, NodeStatus.critical);
    expect(r.warningCount, greaterThan(0));
    expect(r.warningCount, r.nodes.values.fold(0, (a, n) => a + n.warnings.length));
  });

  test('a caution-only network reports caution', () {
    // aspect ratio above the limit gives a caution, not an over-limit
    const rect = DuctNode(id: 'x', name: 'X', flow: 0.5, lengthM: 5, shape: DuctShape.rectangular, fixedHeightM: 0.1);
    final r = computeNetwork(rect, const EngineSettings());
    expect(r.worstStatus, NodeStatus.caution);
  });

  test('status words', () {
    expect(statusWord(NodeStatus.optimal), 'OK');
    expect(statusWord(NodeStatus.caution), 'Caution');
    expect(statusWord(NodeStatus.critical), 'Over limit');
  });
}
