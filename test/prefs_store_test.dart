import 'package:ductletor_pro/core/sample_project.dart';
import 'package:ductletor_pro/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProjectDoc doc(String id, String name) => ProjectDoc(
      id: id, name: name, imperial: false, settings: const EngineSettings(),
      root: blankProject(), updatedAt: DateTime.utc(2026, 10, 16),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save, list, load and delete in browser storage', () async {
    final s = PrefsProjectStore();
    expect(await s.list(), isEmpty);
    await s.save(doc('a', 'Alpha'));
    await s.save(doc('b', 'Beta'));
    expect((await s.list()).map((m) => m.name).toSet(), {'Alpha', 'Beta'});
    expect((await s.load('a'))!.name, 'Alpha');
    await s.delete('a');
    expect(await s.load('a'), isNull);
    expect((await s.list()).length, 1);
  });

  test('unreadable entries are skipped; other keys are ignored', () async {
    SharedPreferences.setMockInitialValues({
      'ductletor.project.bad': 'not json',
      'something.else': 'x',
    });
    final s = PrefsProjectStore();
    await s.save(doc('ok', 'Fine'));
    expect((await s.list()).map((m) => m.name), ['Fine']);
    expect(() => s.load('bad'), throwsA(anything));
  });

  test('a saved project keeps its content', () async {
    final s = PrefsProjectStore();
    await s.save(doc('p', 'P'));
    expect((await s.load('p'))!.root.children.single.id, 'trunk');
  });
}
