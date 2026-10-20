import 'dart:convert';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

FittingContext ctx({double a1 = 0.1, double a2 = 0.1, double v1 = 5, double v2 = 5, double q = 1}) =>
    FittingContext(upstreamArea: a1, downstreamArea: a2, upstreamV: v1, downstreamV: v2, rectangular: false, flowRatio: q);

void main() {
  group('CoefficientTable', () {
    final t = CoefficientTable.fromPoints([(0.1, 0.5), (0.9, 1.5)]);

    test('interpolates between points and flags values outside the range', () {
      expect(t.lookup(0.5).$1, closeTo(1.0, 1e-9));
      expect(t.lookup(0.5).$2, isFalse);
      expect(t.lookup(0.05), (0.5, true));
      expect(t.lookup(2), (1.5, true));
      expect(t.lookup(double.nan).$2, isTrue);
    });

    test('points are sorted; bad tables are rejected', () {
      expect(CoefficientTable.fromPoints([(2, 1), (1, 3)]).xs, [1, 2]);
      expect(() => CoefficientTable.fromPoints([]), throwsFormatException);
      expect(() => CoefficientTable.fromPoints([(1, 1), (1, 2)]), throwsFormatException);
      expect(() => CoefficientTable.fromPoints([(1, -1)]), throwsFormatException);
      expect(() => CoefficientTable.fromPoints([(1, 500)]), throwsFormatException);
      expect(() => CoefficientTable.fromPoints([for (var i = 0; i < 501; i++) (i.toDouble(), 1.0)]), throwsFormatException);
    });
  });

  group('parseCoefficientCsv', () {
    test('accepts commas, semicolons, spaces, a header and comments', () {
      final t = parseCoefficientCsv('Qb/Qc, C\n# note\n0.2, 0.9\n0.5;0.7\n0.8\t0.6\n');
      expect(t.xs, [0.2, 0.5, 0.8]);
      expect(t.cs, [0.9, 0.7, 0.6]);
    });

    test('reports the line of a bad row', () {
      expect(() => parseCoefficientCsv('0.2, 0.9\n0.5, abc\n'), throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('Line 2'))));
      expect(() => parseCoefficientCsv('0.2, 0.9, 1\n'), throwsFormatException);
      expect(() => parseCoefficientCsv('just text\n'), throwsFormatException);
    });
  });

  group('TableFitting', () {
    final table = CoefficientTable.fromPoints([(0.1, 0.5), (0.9, 1.5)]);

    test('driven by flow ratio, area ratio, velocity ratio or a fixed value', () {
      TableFitting f(TableInput i, {double x = 0}) => TableFitting(name: 'T', table: table, input: i, x: x);
      expect(f(TableInput.flowRatio).evaluate(ctx(q: 0.5)).$1, closeTo(1.0, 1e-9));
      expect(f(TableInput.areaRatio).evaluate(ctx(a1: 0.1, a2: 0.05)).$1, closeTo(1.0, 1e-9));
      expect(f(TableInput.velocityRatio).evaluate(ctx(v1: 10, v2: 5)).$1, closeTo(1.0, 1e-9));
      expect(f(TableInput.value, x: 0.9).evaluate(ctx()).$1, closeTo(1.5, 1e-9));
    });

    test('loss carries the source, label with code, and an out-of-range note', () {
      final f = TableFitting(name: 'Tee branch', code: 'SD5-9', source: 'Licensed database', table: table, input: TableInput.flowRatio);
      final l = f.loss(ctx(q: 0.5), 1.2);
      expect(l.label, 'Tee branch (SD5-9)');
      expect(l.source, 'Licensed database');
      expect(l.screening, isFalse);
      expect(l.note, isEmpty);
      expect(f.loss(ctx(q: 0.01), 1.2).note, contains('outside the table range'));
    });

    test('in the network: flow ratio comes from the branch share of the parent flow', () {
      final f = TableFitting(name: 'Branch', table: table, input: TableInput.flowRatio);
      final root = DuctNode(id: 'r', name: 'R', lengthM: 3, junction: JunctionType.none, children: [
        DuctNode(id: 'a', name: 'A', flow: 0.1, lengthM: 4, fittings: [f]),
        const DuctNode(id: 'b', name: 'B', flow: 0.3, lengthM: 4),
      ]);
      final r = computeNetwork(root, const EngineSettings());
      final entry = r.nodes['a']!.fittingBreakdown.single;
      expect(entry.c, closeTo(0.6875, 1e-9)); // 0.1 / 0.4 = 0.25
      expect(r.nodes['a']!.warnings, isEmpty);
    });

    test('out-of-range input raises a warning and a caution status on the section', () {
      final f = TableFitting(name: 'Branch', table: table, input: TableInput.flowRatio);
      final root = DuctNode(id: 'r', name: 'R', lengthM: 3, junction: JunctionType.none, children: [
        DuctNode(id: 'a', name: 'A', flow: 0.01, lengthM: 4, fittings: [f]),
        const DuctNode(id: 'b', name: 'B', flow: 0.5, lengthM: 4),
      ]);
      final a = computeNetwork(root, const EngineSettings()).nodes['a']!;
      expect(a.warnings.any((w) => w.contains('outside the table range')), isTrue);
      expect(a.status, isNot(NodeStatus.optimal));
    });
  });

  group('data sources', () {
    test('built-ins are flagged as screening; custom fittings are not', () {
      expect(const Elbow().isScreening, isTrue);
      expect(const Reducer().isScreening, isTrue);
      const c = CustomFitting(name: 'Elbow', c: 0.2, code: 'CR3-1', source: 'My licensed source');
      expect(c.isScreening, isFalse);
      expect(c.loss(ctx(), 1.2).source, 'My licensed source');
      expect(c.label, 'Elbow (CR3-1)');
      expect(const CustomFitting(name: 'X', c: 1).dataSource, 'User entered');
    });

    test('flagging setting warns on screening fittings only', () {
      const withBuiltin = DuctNode(id: 'x', name: 'X', flow: 0.3, lengthM: 5, fittings: [Elbow()]);
      const withCustom = DuctNode(id: 'x', name: 'X', flow: 0.3, lengthM: 5, fittings: [CustomFitting(name: 'E', c: 0.2)]);
      const on = EngineSettings(requireSourcedFittings: true);
      final a = computeNetwork(withBuiltin, on).nodes['x']!;
      expect(a.warnings.any((w) => w.contains('screening')), isTrue);
      expect(a.status, NodeStatus.caution);
      expect(computeNetwork(withCustom, on).nodes['x']!.warnings, isEmpty);
      expect(computeNetwork(withBuiltin, const EngineSettings()).nodes['x']!.warnings, isEmpty);
    });

    test('junction losses are screening too', () {
      const root = DuctNode(id: 'r', name: 'R', junction: JunctionType.tee90, children: [
        DuctNode(id: 'a', name: 'A', flow: 0.1),
        DuctNode(id: 'b', name: 'B', flow: 0.3),
      ]);
      final r = computeNetwork(root, const EngineSettings(requireSourcedFittings: true));
      expect(r.nodes['a']!.fittingBreakdown.single.screening, isTrue);
      expect(r.nodes['a']!.warnings.any((w) => w.contains('screening')), isTrue);
    });
  });

  group('saving', () {
    test('custom and table fittings round trip with code and source', () {
      final root = DuctNode(id: 'r', name: 'R', fittings: [
        const CustomFitting(name: 'E', c: 0.22, code: 'CR3-1', source: 'Src', count: 2),
        TableFitting(
          name: 'T', code: 'SD5-9', source: 'Src2', input: TableInput.flowRatio, x: 0.3,
          table: CoefficientTable.fromPoints([(0.1, 0.5), (0.9, 1.5)]), count: 3,
        ),
      ]);
      final back = nodeFromJson(jsonDecode(jsonEncode(nodeToJson(root))) as Map<String, dynamic>);
      final c = back.fittings[0] as CustomFitting;
      final t = back.fittings[1] as TableFitting;
      expect((c.code, c.source, c.count), ('CR3-1', 'Src', 2));
      expect((t.code, t.source, t.count, t.input), ('SD5-9', 'Src2', 3, TableInput.flowRatio));
      expect(t.table.lookup(0.5).$1, closeTo(1.0, 1e-9));
    });

    test('older files without code or source still load', () {
      final n = nodeFromJson({'id': 'x', 'fittings': [{'type': 'custom', 'name': 'D', 'c': 0.5}]});
      final c = n.fittings.single as CustomFitting;
      expect((c.code, c.source), ('', ''));
    });

    test('a bad table makes the whole project fail to load', () {
      expect(
        () => nodeFromJson({'id': 'x', 'fittings': [{'type': 'table', 'name': 'T', 'points': [[1, -5]]}]}),
        throwsFormatException,
      );
    });

    test('shared projects with oversized fitting text are rejected', () async {
      final doc = ProjectDoc(
        id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
        root: DuctNode(id: 'r', name: 'R', fittings: [CustomFitting(name: 'x' * 200, c: 0.2)]),
        updatedAt: DateTime.utc(2026, 10, 15),
      );
      await expectLater(parseShared(jsonEncode(doc.toJson())), throwsFormatException);
    });

    test('flag setting round trips', () {
      final s = settingsFromJson(jsonDecode(jsonEncode(settingsToJson(const EngineSettings(requireSourcedFittings: true)))) as Map<String, dynamic>);
      expect(s.requireSourcedFittings, isTrue);
    });
  });
}
