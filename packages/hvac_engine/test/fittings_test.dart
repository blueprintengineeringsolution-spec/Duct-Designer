import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

FittingContext ctx({double a1 = 0.1, double a2 = 0.1, double v1 = 5, double v2 = 5, bool rect = false}) =>
    FittingContext(upstreamArea: a1, downstreamArea: a2, upstreamV: v1, downstreamV: v2, rectangular: rect);

void main() {
  test('round smooth elbow: C from r/D table, scaled by angle', () {
    expect(const Elbow(radiusRatio: 1.0).evaluate(ctx()).$1, closeTo(0.22, 1e-9));
    expect(const Elbow(angleDeg: 45, radiusRatio: 1.0).evaluate(ctx()).$1, closeTo(0.22 * 0.6, 1e-9));
  });

  test('mitered is worse than smooth; vanes help', () {
    final smooth = const Elbow().evaluate(ctx()).$1;
    final mitered = const Elbow(style: ElbowStyle.mitered).evaluate(ctx()).$1;
    final vanes = const Elbow(style: ElbowStyle.miteredVanes).evaluate(ctx()).$1;
    expect(mitered, greaterThan(smooth));
    expect(vanes, lessThan(mitered));
  });

  test('tighter radius costs more', () {
    expect(const Elbow(radiusRatio: 0.5).evaluate(ctx()).$1,
        greaterThan(const Elbow(radiusRatio: 1.5).evaluate(ctx()).$1));
  });

  test('count multiplies the loss', () {
    final one = const Elbow().loss(ctx(), 1.2).pa;
    final three = const Elbow(count: 3).loss(ctx(), 1.2);
    expect(three.pa, closeTo(3 * one, 1e-9));
    expect(three.label, startsWith('3×'));
  });

  test('reducer: no change = no loss; contraction uses downstream V; expansion upstream V', () {
    expect(const Reducer().evaluate(ctx()).$1, 0);
    final con = const Reducer(angleDeg: 30).evaluate(ctx(a1: 0.1, a2: 0.025, v1: 4, v2: 16));
    expect(con.$1, closeTo(0.05, 1e-9));
    expect(con.$2, 16);
    final exp = const Reducer(angleDeg: 30).evaluate(ctx(a1: 0.025, a2: 0.1, v1: 16, v2: 4));
    expect(exp.$2, 16);
    expect(exp.$1, greaterThan(0.2));
    expect(exp.$1, lessThan(0.5625));
  });

  test('abrupt contraction costs more than gradual', () {
    final gradual = const Reducer(angleDeg: 30).evaluate(ctx(a1: 0.1, a2: 0.05)).$1;
    final abrupt = const Reducer(angleDeg: 180).evaluate(ctx(a1: 0.1, a2: 0.05)).$1;
    expect(abrupt, greaterThan(gradual));
  });

  test('custom fitting uses given C and reference velocity', () {
    const f = CustomFitting(name: 'Damper', c: 0.5, reference: ReferenceVelocity.upstream);
    final l = f.loss(ctx(v1: 10, v2: 5), 1.2);
    expect(l.pa, closeTo(0.5 * 0.5 * 1.2 * 100, 1e-9));
  });

  test('junction: branch costs more than main; tee more than wye', () {
    FittingLoss j(JunctionType t, bool main) =>
        junctionLoss(t, isMain: main, velocityRatio: 1, velocity: 5, rho: 1.2);
    expect(j(JunctionType.tee90, false).pa, greaterThan(j(JunctionType.tee90, true).pa));
    expect(j(JunctionType.tee90, false).pa, greaterThan(j(JunctionType.wye45, false).pa));
  });

  group('in the network', () {
    const root = DuctNode(id: 'r', name: 'R', lengthM: 5, junction: JunctionType.tee90, children: [
      DuctNode(id: 'a', name: 'A', kind: NodeKind.terminal, flow: 0.12, lengthM: 4),
      DuctNode(id: 'b', name: 'B', kind: NodeKind.terminal, flow: 0.4, lengthM: 8,
          fittings: [Elbow(count: 2)]),
    ]);

    test('junction roles: largest flow is main, other is branch', () {
      final r = computeNetwork(root, const EngineSettings());
      expect(r.nodes['a']!.fittingBreakdown.any((f) => f.label.contains('branch')), isTrue);
      expect(r.nodes['b']!.fittingBreakdown.any((f) => f.label.contains('main')), isTrue);
    });

    test('explicit fittings add to section fitting loss and breakdown', () {
      final r = computeNetwork(root, const EngineSettings()).nodes['b']!;
      expect(r.fittingBreakdown.any((f) => f.label.startsWith('2×')), isTrue);
      final sum = r.fittingBreakdown.fold(0.0, (a, f) => a + f.pa);
      expect(r.fittingLossPa, closeTo(sum, 1e-9));
    });

    test('fitting loss raises required fan pressure', () {
      const plain = DuctNode(id: 'x', name: 'X', flow: 0.3, lengthM: 5);
      const withElbows = DuctNode(id: 'x', name: 'X', flow: 0.3, lengthM: 5, fittings: [Elbow(count: 4)]);
      expect(computeNetwork(withElbows, const EngineSettings()).requiredFanPa,
          greaterThan(computeNetwork(plain, const EngineSettings()).requiredFanPa));
    });

    test('auto reducer appears when an inline section changes size', () {
      const chain = DuctNode(id: 'r', name: 'R', lengthM: 3, children: [
        DuctNode(id: 'c', name: 'C', flow: 1.0, lengthM: 5),
      ]);
      final r = computeNetwork(chain,
          const EngineSettings(method: SizingMethod.velocityReduction, useStandardSizes: false));
      expect(r.nodes['c']!.fittingBreakdown.any((f) => f.label.contains('Reducer')), isTrue);
      final off = computeNetwork(chain,
          const EngineSettings(method: SizingMethod.velocityReduction, useStandardSizes: false, autoReducers: false));
      expect(off.nodes['c']!.fittingBreakdown, isEmpty);
    });
  });
}
