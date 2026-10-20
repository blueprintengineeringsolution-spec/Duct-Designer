import 'dart:convert';
import 'dart:io';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

ProjectDoc doc(DuctNode root, {EngineSettings s = const EngineSettings()}) => ProjectDoc(
      id: 'p1', name: 'Shared', imperial: false, settings: s, root: root,
      updatedAt: DateTime.utc(2026, 10, 14),
      info: const ReportInfo(company: 'Acme', wastePercent: 6),
    );

const tree = DuctNode(id: 'r', name: 'R', lengthM: 3, junction: JunctionType.tee90, fittings: [Elbow(count: 2)], children: [
  DuctNode(id: 'a', name: 'A', flow: 0.2, lengthM: 4, shape: DuctShape.rectangular, sizeOverride: DuctSize.rect(0.5, 0.2)),
  DuctNode(id: 'b', name: 'B', flow: 0.3, lengthM: 6, material: DuctMaterial.flexible, flexSlack: 0.1),
]);

void main() {
  test('share code round trip gives identical results', () async {
    final code = await encodeShareCode(doc(tree));
    expect(code, startsWith('DUCT1:'));
    final back = await parseShared(code);
    const s = EngineSettings();
    expect(computeNetwork(back.root, s).requiredFanPa, closeTo(computeNetwork(tree, s).requiredFanPa, 1e-9));
    expect(back.info.company, 'Acme');
    expect(back.name, 'Shared');
  });

  test('project file text (JSON) is accepted too, with surrounding whitespace', () async {
    final back = await parseShared('  ${jsonEncode(doc(tree).toJson())}\n');
    expect(back.root.children.length, 2);
  });

  test('a small project fits in a QR code; a huge one does not', () async {
    final big = DuctNode(id: 'r', name: 'R', children: [
      for (var i = 0; i < 400; i++) DuctNode(id: 'n$i', name: 'Section number $i', flow: 0.01 * (i % 7 + 1), lengthM: i + 1.5),
    ]);
    expect(fitsInQr(await encodeShareCode(doc(big))), isFalse);
    expect(fitsInQr('DUCT1:abc'), isTrue);
  });

  test('garbage is rejected with FormatException', () async {
    expect(parseShared('hello'), throwsFormatException);
    expect(parseShared('DUCT1:!!!'), throwsFormatException);
    final code = await encodeShareCode(doc(tree));
    expect(parseShared(code.substring(0, code.length ~/ 2)), throwsFormatException);
    expect(parseShared('[1,2,3]'), throwsFormatException);
  });

  test('a decompression bomb is stopped at the size cap', () async {
    final bomb = 'DUCT1:${base64Url.encode(gzip.encode(List.filled(maxSharedBytes + 1000, 32)))}';
    await expectLater(parseShared(bomb), throwsFormatException);
  });

  test('absurd values and duplicate ids are rejected', () async {
    final neg = doc(const DuctNode(id: 'r', name: 'R', children: [DuctNode(id: 'a', name: 'A', flow: -1)]));
    await expectLater(parseShared(jsonEncode(neg.toJson())), throwsFormatException);
    final dup = doc(const DuctNode(id: 'r', name: 'R', children: [DuctNode(id: 'a', name: 'A'), DuctNode(id: 'a', name: 'B')]));
    await expectLater(parseShared(jsonEncode(dup.toJson())), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Duplicate'))));
    final badAir = doc(tree, s: const EngineSettings(air: Air(density: 50)));
    await expectLater(parseShared(jsonEncode(badAir.toJson())), throwsFormatException);
  });

  test('deeply nested networks are rejected without a crash', () async {
    Map<String, dynamic> nest(int d) => {'id': 'n$d', 'children': d == 0 ? [] : [nest(d - 1)]};
    final text = jsonEncode({'schema': 1, 'id': 'p', 'root': nest(maxNodeDepth + 6)});
    await expectLater(parseShared(text), throwsFormatException);
  });

  test('validateProject accepts a normal project', () {
    expect(validateProject(doc(tree)), isEmpty);
  });
}
