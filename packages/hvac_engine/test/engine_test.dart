import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

void main() {
  test('velocity pressure', () {
    expect(velocityPressure(10, 1.2), closeTo(60, 1e-9));
  });

  test('Huebscher equivalent diameter 300x200', () {
    expect(equivalentDiameter(0.3, 0.2), closeTo(0.266, 0.002));
  });

  test('equal friction sizing round-trips to target rate', () {
    final d = sizeRoundForFriction(flow: 0.5, targetPaPerM: 1.0);
    expect(d, inInclusiveRange(0.27, 0.35));
    final fr = frictionRate(flow: 0.5, diameter: d, material: DuctMaterial.galvanized);
    expect(fr, closeTo(1.0, 0.01));
  });

  test('flex duct loses more than galvanized; slack adds more', () {
    double fr(DuctMaterial m, [double slack = 0]) =>
        frictionRate(flow: 0.3, diameter: 0.25, material: m, flexSlack: slack);
    expect(fr(DuctMaterial.flexible), greaterThan(fr(DuctMaterial.galvanized)));
    expect(fr(DuctMaterial.flexible, 0.15), greaterThan(fr(DuctMaterial.flexible)));
  });

  test('rectangular width reproduces equivalent diameter', () {
    final w = rectWidthFor(0.3, 0.2);
    expect(equivalentDiameter(0.2, w), closeTo(0.3, 1e-4));
  });

  test('static regain downstream velocity is below upstream', () {
    final d = sizeRoundStaticRegain(flow: 0.3, v1: 8, lengthM: 3);
    expect(0.3 / roundArea(d), lessThan(8));
  });

  test('noise rises with velocity and fitting turbulence', () {
    final lo = flowNoiseLw(velocity: 4, areaM2: 0.1);
    expect(flowNoiseLw(velocity: 8, areaM2: 0.1), greaterThan(lo));
    expect(flowNoiseLw(velocity: 4, areaM2: 0.1, fitting: FittingKind.damper), greaterThan(lo));
  });

  group('network', () {
    const root = DuctNode(id: 'ahu', name: 'AHU', kind: NodeKind.ahu, lengthM: 2, equipmentDropPa: 150, children: [
      DuctNode(id: 'short', name: 'Short', lengthM: 5, children: [
        DuctNode(id: 'a', name: 'A', kind: NodeKind.terminal, flow: 0.2, lengthM: 2, fittingC: 0.3),
      ]),
      DuctNode(id: 'long', name: 'Long', lengthM: 30, fittingC: 0.5, children: [
        DuctNode(id: 'b', name: 'B', kind: NodeKind.terminal, flow: 0.2, lengthM: 10, fittingC: 0.3),
      ]),
    ]);

    test('flows roll up and critical path follows longest run', () {
      final r = computeNetwork(root, const EngineSettings());
      expect(r.nodes['ahu']!.flow, closeTo(0.4, 1e-9));
      expect(r.criticalPath, ['ahu', 'long', 'b']);
      expect(r.requiredFanPa, r.nodes['b']!.cumulativePa);
    });

    test('longer parent raises required fan pressure', () {
      DuctNode mk(double len) => DuctNode(id: 'ahu', name: 'AHU', kind: NodeKind.ahu, lengthM: len, children: const [
            DuctNode(id: 'a', name: 'A', kind: NodeKind.terminal, flow: 0.2, lengthM: 2),
          ]);
      expect(computeNetwork(mk(20), const EngineSettings()).requiredFanPa,
          greaterThan(computeNetwork(mk(2), const EngineSettings()).requiredFanPa));
    });

    test('flags excessive aspect ratio', () {
      const n = DuctNode(id: 'x', name: 'X', flow: 0.5, lengthM: 5, fixedHeightM: 0.1, shape: DuctShape.rectangular);
      final r = computeNetwork(n, const EngineSettings()).nodes['x']!;
      expect(r.aspect!, greaterThan(4));
      expect(r.warnings.any((w) => w.contains('Aspect')), isTrue);
    });

    test('all three methods produce finite results', () {
      for (final m in SizingMethod.values) {
        expect(computeNetwork(root, EngineSettings(method: m)).requiredFanPa.isFinite, isTrue);
      }
    });
  });
}
