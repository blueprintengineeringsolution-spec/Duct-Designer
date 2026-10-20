import 'dart:convert';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

ProjectDoc doc(List<Fitting> lib) => ProjectDoc(
      id: 'p', name: 'P', imperial: false, settings: const EngineSettings(),
      root: const DuctNode(id: 'r', name: 'R'), updatedAt: DateTime.utc(2026, 10, 15), library: lib,
    );

Map<String, dynamic> viaJson(ProjectDoc d) => jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;

void main() {
  final table = CoefficientTable.fromPoints([(0.1, 0.5), (0.9, 1.5)]);

  test('withCount keeps everything else', () {
    final c = const CustomFitting(name: 'E', c: 0.2, code: 'X', source: 'S').withCount(3) as CustomFitting;
    expect((c.name, c.c, c.code, c.source, c.count), ('E', 0.2, 'X', 'S', 3));
    final t = TableFitting(name: 'T', table: table, code: 'Y', source: 'S2', input: TableInput.flowRatio).withCount(2) as TableFitting;
    expect((t.name, t.code, t.source, t.input, t.count), ('T', 'Y', 'S2', TableInput.flowRatio, 2));
    expect((const Elbow(angleDeg: 45).withCount(4) as Elbow).count, 4);
    expect((const Reducer(angleDeg: 60).withCount(2) as Reducer).angleDeg, 60);
  });

  test('library round trips with the project', () {
    final back = ProjectDoc.fromJson(viaJson(doc([
      const CustomFitting(name: 'E', c: 0.2, code: 'CR3-1', source: 'S'),
      TableFitting(name: 'T', table: table, source: 'S2'),
    ])));
    expect(back.library.length, 2);
    expect((back.library[0] as CustomFitting).code, 'CR3-1');
    expect(back.library[1], isA<TableFitting>());
  });

  test('older files have an empty library; built-in fittings in a library are dropped', () {
    final json = viaJson(doc([const CustomFitting(name: 'E', c: 0.2)]));
    expect(ProjectDoc.fromJson(json..remove('library')).library, isEmpty);
    json['library'] = [
      {'type': 'elbow'},
      {'type': 'custom', 'name': 'Keep', 'c': 0.3},
    ];
    final back = ProjectDoc.fromJson(json);
    expect(back.library.length, 1);
    expect((back.library.single as CustomFitting).name, 'Keep');
  });

  test('shared projects with an oversized library or long text are rejected', () async {
    final many = doc([for (var i = 0; i < maxLibraryEntries + 1; i++) CustomFitting(name: 'F$i', c: 0.1)]);
    await expectLater(parseShared(jsonEncode(many.toJson())), throwsFormatException);
    final long = doc([CustomFitting(name: 'x' * 300, c: 0.1)]);
    await expectLater(parseShared(jsonEncode(long.toJson())), throwsFormatException);
    final ok = await parseShared(jsonEncode(doc([const CustomFitting(name: 'Fine', c: 0.1)]).toJson()));
    expect(ok.library.length, 1);
  });

  test('share code keeps the library', () async {
    final back = await parseShared(await encodeShareCode(doc([const CustomFitting(name: 'E', c: 0.2, source: 'S')])));
    expect((back.library.single as CustomFitting).source, 'S');
  });
}
