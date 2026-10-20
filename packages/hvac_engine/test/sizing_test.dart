import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

const _tree = DuctNode(id: 'r', name: 'R', lengthM: 5, children: [
  DuctNode(id: 'a', name: 'A', kind: NodeKind.terminal, flow: 0.12, lengthM: 4),
  DuctNode(id: 'b', name: 'B', kind: NodeKind.terminal, flow: 0.4, lengthM: 8),
]);

void main() {
  test('round: next standard size up is recommended, one below is undersized', () {
    final o = recommendRound(requiredDe: 0.33, flow: 0.5);
    expect(o.firstWhere((x) => x.recommended).size.diameterM, 0.4);
    expect(o.first.size.diameterM, 0.315);
    expect(o.first.undersized, isTrue);
  });

  test('rect with fixed height snaps width to the 50 mm step', () {
    final o = recommendRect(requiredDe: 0.33, flow: 0.5, fixedHeightM: 0.1);
    final rec = o.firstWhere((x) => x.recommended);
    final steps = rec.size.widthM! / 0.05;
    expect((steps - steps.round()).abs(), lessThan(1e-6));
    expect(rec.size.equivalentDiameterM, greaterThanOrEqualTo(0.33 - 1e-6));
  });

  test('rect auto: respects max height and aspect, meets required size', () {
    final o = recommendRect(
        requiredDe: 0.33, flow: 0.5, limits: const SizeLimits(maxHeightM: 0.3));
    final rec = o.firstWhere((x) => x.recommended);
    expect(rec.size.heightM!, lessThanOrEqualTo(0.3 + 1e-9));
    expect(rec.size.aspect!, lessThanOrEqualTo(4 + 1e-9));
    expect(rec.undersized, isFalse);
    expect(o.length, lessThanOrEqualTo(3));
  });

  test('imperial catalog holds 10 in round', () {
    expect(SizeCatalog.imperial.roundM.any((d) => (d - 0.254).abs() < 1e-6), isTrue);
  });

  test('standard sizes: round results come from the catalog and stay at/below target friction', () {
    final r = computeNetwork(_tree, const EngineSettings());
    for (final n in r.nodes.values) {
      expect(SizeCatalog.metric.roundM.any((d) => (d - n.diameterM).abs() < 1e-9), isTrue);
      expect(n.frictionPaPerM, lessThanOrEqualTo(0.8 + 1e-6));
    }
  });

  test('exact sizing hits the constant pressure-drop target', () {
    final r = computeNetwork(_tree, const EngineSettings(useStandardSizes: false));
    for (final n in r.nodes.values) {
      expect(n.frictionPaPerM, closeTo(0.8, 0.01));
    }
  });

  test('constant velocity method gives the target velocity (exact sizes)', () {
    final r = computeNetwork(
        _tree, const EngineSettings(method: SizingMethod.constantVelocity, constantVelocity: 6, useStandardSizes: false));
    for (final n in r.nodes.values) {
      expect(n.velocity, closeTo(6, 0.01));
    }
  });

  test('project default shape rectangular produces rect sizes within limits', () {
    final r = computeNetwork(
        _tree, const EngineSettings(defaultShape: DuctShape.rectangular, maxRectHeightM: 0.3));
    for (final n in r.nodes.values) {
      expect(n.size.shape, DuctShape.rectangular);
      expect(n.heightM!, lessThanOrEqualTo(0.3 + 1e-9));
    }
  });

  test('node shape overrides project default; size override is honoured', () {
    const node = DuctNode(
        id: 'x', name: 'X', flow: 0.3, lengthM: 4,
        shape: DuctShape.rectangular, sizeOverride: DuctSize.rect(0.5, 0.2));
    final n = computeNetwork(node, const EngineSettings()).nodes['x']!;
    expect(n.size.label, '500×200');
    expect(n.velocity, closeTo(0.3 / 0.1, 1e-9));
  });

  test('method labels', () {
    expect(methodLabel(SizingMethod.equalFriction), 'Constant pressure drop per length');
  });
}
