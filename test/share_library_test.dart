import 'package:ductletor_pro/core/sample_project.dart';
import 'package:ductletor_pro/data/project_store.dart';
import 'package:ductletor_pro/state/project_library.dart';
import 'package:ductletor_pro/state/tree_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

void main() {
  test('docFor returns the latest edits even before autosave fires', () async {
    final lib = ProjectLibrary(MemoryProjectStore(), saveDebounce: const Duration(seconds: 5));
    await lib.init();
    final c = lib.active!;
    c.updateNode('trunk', lengthM: 42);
    final doc = await lib.docFor(c.id);
    expect(findNode(doc!.root, 'trunk')!.lengthM, 42);
    await lib.flush();
  });

  test('share then import makes a separate, equal copy and opens it', () async {
    final lib = ProjectLibrary(MemoryProjectStore(), saveDebounce: const Duration(milliseconds: 10));
    await lib.init();
    final src = lib.active!;
    src.addFitting('trunk', const Elbow(count: 2));
    final code = await encodeShareCode((await lib.docFor(src.id))!);
    final incoming = await parseShared(code);
    await lib.importShared(incoming);
    expect(lib.projects.length, 2);
    expect(lib.active!.id, isNot(src.id));
    expect(lib.active!.name, endsWith('(imported)'));
    expect(lib.active!.result.requiredFanPa, closeTo(src.result.requiredFanPa, 1e-9));
    await lib.flush();
  });

  test('importing twice does not stack the suffix', () async {
    final lib = ProjectLibrary(MemoryProjectStore(), saveDebounce: const Duration(milliseconds: 10));
    await lib.init();
    final doc = ProjectDoc(
      id: 'x', name: 'Plant (imported)', imperial: false, settings: const EngineSettings(),
      root: blankProject(), updatedAt: DateTime.utc(2026, 10, 14),
    );
    await lib.importShared(doc);
    expect(lib.active!.name, 'Plant (imported)');
    await lib.flush();
  });
}
