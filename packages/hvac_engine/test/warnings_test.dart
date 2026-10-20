import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

const unit1 = DuctNode(id: 'r', name: 'R', lengthM: 3, children: [
  DuctNode(id: 'a', name: 'A', flow: 0.2, lengthM: 4),
  DuctNode(id: 'b', name: 'B', flow: 0.3, lengthM: 4, shape: DuctShape.rectangular, fixedHeightM: 0.1), // aspect: caution
  DuctNode(id: 'c', name: 'C', flow: 0.5, lengthM: 4, sizeOverride: DuctSize.round(0.1)), // far too fast: over limit
]);

Map<String, NetworkResult> calc(List<DuctNode> units, [EngineSettings s = const EngineSettings()]) =>
    {for (final u in units) u.id: computeNetwork(u, s)};

void main() {
  test('every warning is listed with its unit and section', () {
    final res = calc([unit1]);
    final w = collectWarnings([unit1], res);
    expect(w.length, res['r']!.warningCount);
    expect(w.every((e) => e.unitName == 'R' && e.unitId == 'r'), isTrue);
    expect(w.where((e) => e.nodeId == 'a'), isEmpty);
    expect(w.any((e) => e.nodeId == 'b' && e.text.contains('Aspect')), isTrue);
    expect(w.any((e) => e.nodeId == 'c' && e.text.contains('Velocity')), isTrue);
  });

  test('over-limit sections come before caution ones', () {
    final w = collectWarnings([unit1], calc([unit1]));
    final lastCritical = w.lastIndexWhere((e) => e.status == NodeStatus.critical);
    final firstCaution = w.indexWhere((e) => e.status == NodeStatus.caution);
    expect(lastCritical, greaterThanOrEqualTo(0));
    expect(firstCaution, greaterThan(lastCritical));
    expect(w.first.nodeId, 'c');
  });

  test('units keep their order even when a later unit is worse', () {
    const calm = DuctNode(id: 'u1', name: 'Calm', children: [
      DuctNode(id: 'u1b', name: 'Flat', flow: 0.5, shape: DuctShape.rectangular, fixedHeightM: 0.1),
    ]);
    const bad = DuctNode(id: 'u2', name: 'Bad', children: [
      DuctNode(id: 'u2c', name: 'Fast', flow: 0.5, sizeOverride: DuctSize.round(0.1)),
    ]);
    final w = collectWarnings([calm, bad], calc([calm, bad]));
    final firstBad = w.indexWhere((e) => e.unitId == 'u2');
    expect(w.sublist(0, firstBad).every((e) => e.unitId == 'u1'), isTrue);
    expect(w.sublist(firstBad).every((e) => e.unitId == 'u2'), isTrue);
  });

  test('nothing to report for a calm project', () {
    const calm = DuctNode(id: 'r', name: 'R', children: [DuctNode(id: 'a', name: 'A', flow: 0.2)]);
    expect(collectWarnings([calm], calc([calm])), isEmpty);
  });

  test('units without results are skipped', () {
    expect(collectWarnings([unit1], {}), isEmpty);
  });
}
