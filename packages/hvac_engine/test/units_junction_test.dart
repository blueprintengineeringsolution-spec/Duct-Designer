import 'dart:convert';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

const split = DuctNode(id: 'r', name: 'R', lengthM: 3, children: [
  DuctNode(id: 'a', name: 'A', flow: 0.1, lengthM: 4),
  DuctNode(id: 'b', name: 'B', flow: 0.3, lengthM: 4),
]);

Map<String, dynamic> viaJson(ProjectDoc d) => jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;

void main() {
  group('automatic junction at a split', () {
    test('two children get a tee without anyone adding one', () {
      final r = computeNetwork(split, const EngineSettings());
      expect(r.nodes['a']!.fittingBreakdown.single.label, '90° tee – branch');
      expect(r.nodes['b']!.fittingBreakdown.single.label, '90° tee – main');
      expect(r.nodes['r']!.fittingBreakdown, isEmpty);
    });

    test('the junction is charged once per outlet, on the outlet, never on the parent', () {
      final r = computeNetwork(split, const EngineSettings());
      expect(r.nodes['r']!.fittingLossPa, 0);
      expect(r.nodes['a']!.fittingLossPa, greaterThan(r.nodes['b']!.fittingLossPa));
    });

    test('a single child is not a split', () {
      const chain = DuctNode(id: 'r', name: 'R', children: [DuctNode(id: 'a', name: 'A', flow: 0.2)]);
      expect(effectiveJunction(chain, const EngineSettings()), JunctionType.none);
      expect(computeNetwork(chain, const EngineSettings()).nodes['a']!.fittingBreakdown, isEmpty);
    });

    test('project default can be a wye or none; a node can override the default', () {
      expect(effectiveJunction(split, const EngineSettings(defaultJunction: JunctionType.wye45)), JunctionType.wye45);
      final none = computeNetwork(split, const EngineSettings(defaultJunction: JunctionType.none));
      expect(none.nodes['a']!.fittingBreakdown, isEmpty);
      const own = DuctNode(id: 'r', name: 'R', junction: JunctionType.wye45, children: [
        DuctNode(id: 'a', name: 'A', flow: 0.1),
        DuctNode(id: 'b', name: 'B', flow: 0.3),
      ]);
      expect(effectiveJunction(own, const EngineSettings()), JunctionType.wye45);
      const off = DuctNode(id: 'r', name: 'R', junction: JunctionType.none, children: [
        DuctNode(id: 'a', name: 'A', flow: 0.1),
        DuctNode(id: 'b', name: 'B', flow: 0.3),
      ]);
      expect(computeNetwork(off, const EngineSettings()).nodes['a']!.fittingBreakdown, isEmpty);
    });

    test('BOQ counts one tee for two outlets and two for three', () {
      final b2 = computeBoq(split, computeNetwork(split, const EngineSettings()), const EngineSettings());
      expect(b2.fittings.where((f) => f.description == '90° tee').fold(0, (a, f) => a + f.count), 1);
      const three = DuctNode(id: 'r', name: 'R', children: [
        DuctNode(id: 'a', name: 'A', flow: 0.1),
        DuctNode(id: 'b', name: 'B', flow: 0.1),
        DuctNode(id: 'c', name: 'C', flow: 0.1),
      ]);
      final b3 = computeBoq(three, computeNetwork(three, const EngineSettings()), const EngineSettings());
      expect(b3.fittings.where((f) => f.description == '90° tee').fold(0, (a, f) => a + f.count), 2);
      final off = const EngineSettings(defaultJunction: JunctionType.none);
      final b0 = computeBoq(split, computeNetwork(split, off), off);
      expect(b0.fittings.where((f) => f.description.contains('tee')), isEmpty);
    });

    test('default junction is saved with the settings', () {
      final back = settingsFromJson(jsonDecode(jsonEncode(settingsToJson(const EngineSettings(defaultJunction: JunctionType.wye45)))) as Map<String, dynamic>);
      expect(back.defaultJunction, JunctionType.wye45);
      expect(settingsFromJson({}).defaultJunction, JunctionType.tee90);
    });
  });

  group('multiple units', () {
    DuctNode unit(String id, double flow) => DuctNode(id: id, name: 'Unit $id', kind: NodeKind.ahu, lengthM: 3, children: [
          DuctNode(id: '$id-t', name: 'T $id', flow: flow, lengthM: 8),
        ]);

    test('a document keeps all its units; root is the first', () {
      final doc = ProjectDoc(
        id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
        units: [unit('u1', 0.3), unit('u2', 0.6)], updatedAt: DateTime.utc(2026, 10, 16),
      );
      expect(doc.root.id, 'u1');
      final back = ProjectDoc.fromJson(viaJson(doc));
      expect(back.units.map((u) => u.id), ['u1', 'u2']);
      expect(viaJson(doc)['schema'], projectSchemaVersion);
    });

    test('files saved with a single root still open as one unit', () {
      final old = {
        'schema': 1, 'id': 'p', 'name': 'Old', 'updatedAt': '2026-10-01T00:00:00Z',
        'root': nodeToJson(unit('u1', 0.3)),
      };
      final doc = ProjectDoc.fromJson(old);
      expect(doc.units.length, 1);
      expect(doc.root.id, 'u1');
    });

    test('projects need a unit; too many units are rejected', () {
      expect(() => ProjectDoc.fromJson({'id': 'p', 'units': []}), throwsFormatException);
      expect(() => ProjectDoc.fromJson({'id': 'p'}), throwsFormatException);
      final many = {'id': 'p', 'units': [for (var i = 0; i <= maxUnits; i++) nodeToJson(unit('u$i', 0.1))]};
      expect(() => ProjectDoc.fromJson(many), throwsFormatException);
    });

    test('ids must be unique across units when a project is imported', () async {
      final doc = ProjectDoc(
        id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
        units: [unit('u1', 0.3), unit('u1', 0.3)], updatedAt: DateTime.utc(2026, 10, 16),
      );
      await expectLater(parseShared(jsonEncode(doc.toJson())), throwsFormatException);
      final ok = ProjectDoc(
        id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
        units: [unit('u1', 0.3), unit('u2', 0.3)], updatedAt: DateTime.utc(2026, 10, 16),
      );
      expect((await parseShared(await encodeShareCode(ok))).units.length, 2);
    });

    test('a library file can be read from a multi-unit project file', () {
      final doc = ProjectDoc(
        id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
        units: [unit('u1', 0.3), unit('u2', 0.3)], updatedAt: DateTime.utc(2026, 10, 16),
        library: const [CustomFitting(name: 'E', c: 0.2)],
      );
      expect(parseLibraryFile(jsonEncode(doc.toJson())).length, 1);
    });

    test('merged take-off adds sections, groups and fittings', () {
      const s = EngineSettings();
      final u1 = unit('u1', 0.3), u2 = unit('u2', 0.3);
      final b1 = computeBoq(u1, computeNetwork(u1, s), s);
      final b2 = computeBoq(u2, computeNetwork(u2, s), s);
      final m = mergeBoq([b1, b2]);
      expect(m.sections.length, b1.sections.length + b2.sections.length);
      expect(m.totalLengthM, closeTo(b1.totalLengthM + b2.totalLengthM, 1e-9));
      expect(m.netAreaM2, closeTo(b1.netAreaM2 + b2.netAreaM2, 1e-9));
      expect(m.groups.fold(0, (a, g) => a + g.sections), m.sections.length);
      expect(mergeBoq([]).sections, isEmpty);
    });
  });
}
