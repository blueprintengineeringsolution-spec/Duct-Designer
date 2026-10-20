import 'dart:convert';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

Map<String, dynamic> roundTrip(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  const root = DuctNode(
    id: 'r',
    name: 'R',
    lengthM: 3,
    junction: JunctionType.tee90,
    fittings: [
      Elbow(angleDeg: 45, style: ElbowStyle.mitered, count: 2),
      Reducer(angleDeg: 60),
      CustomFitting(name: 'Damper', c: 0.7, reference: ReferenceVelocity.upstream, kind: FittingKind.damper),
    ],
    children: [
      DuctNode(
        id: 'a', name: 'A', flow: 0.2, lengthM: 4,
        shape: DuctShape.rectangular, fixedHeightM: 0.2,
        sizeOverride: DuctSize.rect(0.5, 0.2),
        material: DuctMaterial.flexible, flexSlack: 0.1,
      ),
      DuctNode(id: 'b', name: 'B', flow: 0.3, lengthM: 5, sizeOverride: DuctSize.round(0.315), fittingC: 0.3),
    ],
  );

  test('node round trip preserves structure and results', () {
    final back = nodeFromJson(roundTrip(nodeToJson(root)));
    expect(back.fittings.length, 3);
    expect(back.fittings.first, isA<Elbow>());
    expect((back.fittings.first as Elbow).count, 2);
    expect(back.children.first.sizeOverride!.label, '500×200');
    expect(back.children.first.shape, DuctShape.rectangular);
    expect(back.junction, JunctionType.tee90);
    const s = EngineSettings();
    expect(computeNetwork(back, s).requiredFanPa, closeTo(computeNetwork(root, s).requiredFanPa, 1e-9));
  });

  test('settings round trip incl. imperial catalog and height limit', () {
    final s = const EngineSettings().copyWith(
      method: SizingMethod.constantVelocity,
      constantVelocity: 5.5,
      defaultShape: DuctShape.rectangular,
      catalog: SizeCatalog.imperial,
      maxRectHeightM: 0.25,
      autoReducers: false,
    );
    final back = settingsFromJson(roundTrip(settingsToJson(s)));
    expect(back.method, SizingMethod.constantVelocity);
    expect(back.constantVelocity, 5.5);
    expect(back.defaultShape, DuctShape.rectangular);
    expect(identical(back.catalog, SizeCatalog.imperial), isTrue);
    expect(back.maxRectHeightM, 0.25);
    expect(back.autoReducers, isFalse);
  });

  test('unknown enum names fall back and missing keys default', () {
    final n = nodeFromJson({'id': 'x', 'kind': 'martian', 'material': 'unobtainium'});
    expect(n.kind, NodeKind.branch);
    expect(n.material, DuctMaterial.galvanized);
    expect(n.name, 'x');
    final s = settingsFromJson({'method': 'nope'});
    expect(s.method, SizingMethod.equalFriction);
    expect(s.frictionPaPerM, 0.8);
  });

  test('unknown fitting types are dropped, bad node ids rejected', () {
    final n = nodeFromJson({'id': 'x', 'fittings': [{'type': 'mystery'}, {'type': 'elbow'}]});
    expect(n.fittings.length, 1);
    expect(() => nodeFromJson({'name': 'no id'}), throwsFormatException);
  });

  test('ProjectDoc round trip and newer schema rejected', () {
    final doc = ProjectDoc(
      id: 'p1', name: 'Office', imperial: true,
      settings: const EngineSettings(), root: root,
      updatedAt: DateTime.utc(2026, 10, 14, 12),
    );
    final back = ProjectDoc.fromJson(roundTrip(doc.toJson()));
    expect(back.name, 'Office');
    expect(back.imperial, isTrue);
    expect(back.updatedAt, DateTime.utc(2026, 10, 14, 12));
    final future = doc.toJson()..['schema'] = projectSchemaVersion + 1;
    expect(() => ProjectDoc.fromJson(future), throwsFormatException);
  });
}
