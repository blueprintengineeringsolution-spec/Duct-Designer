import 'dart:convert';
import 'dart:math' as math;
import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

BoqSummary boq(DuctNode root, [EngineSettings s = const EngineSettings(), double waste = 5]) =>
    computeBoq(root, computeNetwork(root, s), s, options: BoqOptions(wastePercent: waste));

void main() {
  test('surface area: round and rectangular', () {
    final b = boq(const DuctNode(id: 'r', name: 'R', lengthM: 3, children: [
      DuctNode(id: 'a', name: 'A', flow: 0.2, lengthM: 10, sizeOverride: DuctSize.round(0.4)),
      DuctNode(id: 'b', name: 'B', flow: 0.2, lengthM: 5, shape: DuctShape.rectangular, sizeOverride: DuctSize.rect(0.5, 0.2)),
    ]));
    final a = b.sections.firstWhere((s) => s.nodeId == 'a');
    final c = b.sections.firstWhere((s) => s.nodeId == 'b');
    expect(a.areaM2, closeTo(math.pi * 0.4 * 10, 1e-9));
    expect(c.areaM2, closeTo(2 * (0.5 + 0.2) * 5, 1e-9));
  });

  test('same material and size are grouped', () {
    final b = boq(const DuctNode(id: 'r', name: 'R', lengthM: 3, sizeOverride: DuctSize.round(0.5), children: [
      DuctNode(id: 'a', name: 'A', flow: 0.2, lengthM: 10, sizeOverride: DuctSize.round(0.4)),
      DuctNode(id: 'b', name: 'B', flow: 0.2, lengthM: 6, sizeOverride: DuctSize.round(0.4)),
    ]));
    final g = b.groups.firstWhere((g) => g.size.label == 'Ø400');
    expect(g.sections, 2);
    expect(g.lengthM, 16);
  });

  test('insulation totals skip un-insulated sections; waste applies to areas', () {
    final b = boq(const DuctNode(id: 'r', name: 'R', lengthM: 4, insulated: false, children: [
      DuctNode(id: 'a', name: 'A', flow: 0.2, lengthM: 10),
    ]), const EngineSettings(), 10);
    expect(b.totalLengthM, 14);
    expect(b.insulatedLengthM, 10);
    expect(b.insulatedAreaM2, lessThan(b.netAreaM2));
    expect(b.grossAreaM2, closeTo(b.netAreaM2 * 1.1, 1e-9));
    expect(b.grossInsulatedAreaM2, closeTo(b.insulatedAreaM2 * 1.1, 1e-9));
  });

  test('fitting counts: explicit quantities add up, junction needs children - 1', () {
    final b = boq(const DuctNode(id: 'r', name: 'R', lengthM: 3, junction: JunctionType.tee90, fittings: [
      Elbow(count: 3),
    ], children: [
      DuctNode(id: 'a', name: 'A', flow: 0.1, lengthM: 4, sizeOverride: DuctSize.round(0.25), fittings: [Elbow(count: 2)]),
      DuctNode(id: 'b', name: 'B', flow: 0.1, lengthM: 4),
      DuctNode(id: 'c', name: 'C', flow: 0.1, lengthM: 4),
    ]));
    int count(String starts) => b.fittings.where((f) => f.description.startsWith(starts)).fold(0, (x, f) => x + f.count);
    expect(count('90° elbow'), 5);
    expect(count('90° tee'), 2);
    expect(b.fittingCount, 7);
  });

  test('auto reducer is counted with from/to sizes', () {
    final s = const EngineSettings(method: SizingMethod.velocityReduction, useStandardSizes: false);
    final b = boq(const DuctNode(id: 'r', name: 'R', lengthM: 3, children: [
      DuctNode(id: 'c', name: 'C', flow: 1.0, lengthM: 5),
    ]), s);
    final red = b.fittings.where((f) => f.description == 'Reducer').toList();
    expect(red.length, 1);
    expect(red.single.size, contains(' to '));
  });

  test('CSV quotes commas and has the totals block', () {
    final b = boq(const DuctNode(id: 'r', name: 'AHU, main', lengthM: 3, children: [
      DuctNode(id: 'a', name: 'A', flow: 0.2, lengthM: 10),
    ]));
    final csv = boqToCsv(b);
    expect(csv, contains('"AHU, main"'));
    expect(csv, contains('Total length (m),13.00'));
    expect(csv.split('\n').first, 'Duct sections');
  });

  test('insulated flag and report info survive a save round trip', () {
    final doc = ProjectDoc(
      id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
      root: const DuctNode(id: 'r', name: 'R', insulated: false),
      updatedAt: DateTime.utc(2026, 10, 14),
      info: const ReportInfo(company: 'Acme HVAC', client: 'ABC Ltd', wastePercent: 8),
    );
    final back = ProjectDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
    expect(back.root.insulated, isFalse);
    expect(back.info.company, 'Acme HVAC');
    expect(back.info.wastePercent, 8);
    final old = doc.toJson()..remove('info');
    expect(ProjectDoc.fromJson(old).info.wastePercent, 5);
  });
}
