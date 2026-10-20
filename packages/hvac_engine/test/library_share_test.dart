import 'dart:convert';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

final table = CoefficientTable.fromPoints([(0.1, 0.5), (0.9, 1.5)]);
final lib = <Fitting>[
  const CustomFitting(name: 'Elbow', c: 0.22, code: 'CR3-1', source: 'S', count: 4),
  TableFitting(name: 'Tee', table: table, input: TableInput.flowRatio, source: 'S2', count: 2),
];

void main() {
  test('library file round trip keeps sourced fittings and resets counts', () {
    final back = parseLibraryFile(encodeLibraryFile(lib, name: 'Job 1'));
    expect(back.length, 2);
    expect((back[0] as CustomFitting).code, 'CR3-1');
    expect(back.every((f) => f.count == 1), isTrue);
    expect((back[1] as TableFitting).table.lookup(0.5).$1, closeTo(1.0, 1e-9));
  });

  test('built-in fittings are not exported or imported', () {
    final text = encodeLibraryFile([const Elbow(), const CustomFitting(name: 'K', c: 0.3)]);
    expect(parseLibraryFile(text).length, 1);
    final raw = jsonEncode({'format': libraryFormat, 'schema': 1, 'fittings': [{'type': 'elbow'}]});
    expect(() => parseLibraryFile(raw), throwsFormatException);
  });

  test('a project file works as a source: its library is used', () {
    final doc = ProjectDoc(
      id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
      root: const DuctNode(id: 'r', name: 'R'), updatedAt: DateTime.utc(2026, 10, 15), library: lib,
    );
    expect(parseLibraryFile(jsonEncode(doc.toJson())).length, 2);
    final empty = ProjectDoc(
      id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
      root: const DuctNode(id: 'r', name: 'R'), updatedAt: DateTime.utc(2026, 10, 15),
    );
    expect(() => parseLibraryFile(jsonEncode(empty.toJson())), throwsFormatException);
  });

  test('garbage, wrong files and newer schemas are rejected', () {
    expect(() => parseLibraryFile('hello'), throwsFormatException);
    expect(() => parseLibraryFile('[1,2]'), throwsFormatException);
    expect(() => parseLibraryFile('{"a":1}'), throwsFormatException);
    expect(() => parseLibraryFile(jsonEncode({'format': libraryFormat, 'schema': 2, 'fittings': []})), throwsFormatException);
    expect(() => parseLibraryFile(jsonEncode({'format': libraryFormat, 'fittings': 'x'})), throwsFormatException);
  });

  test('too many entries, long text and bad tables are rejected', () {
    final many = encodeLibraryFile([for (var i = 0; i < maxLibraryEntries + 1; i++) CustomFitting(name: 'F$i', c: 0.1)]);
    expect(() => parseLibraryFile(many), throwsFormatException);
    expect(() => parseLibraryFile(encodeLibraryFile([CustomFitting(name: 'x' * 300, c: 0.1)])), throwsFormatException);
    final bad = jsonEncode({
      'format': libraryFormat, 'schema': 1,
      'fittings': [{'type': 'table', 'name': 'T', 'points': [[1, -3]]}],
    });
    expect(() => parseLibraryFile(bad), throwsFormatException);
  });

  test('validateLibrary matches the project check', () {
    expect(validateLibrary(lib), isEmpty);
    expect(validateLibrary([CustomFitting(name: 'y' * 200, c: 0.1)]), isNotEmpty);
  });
}
