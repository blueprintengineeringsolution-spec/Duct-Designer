import 'dart:io';
import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/projects/data/memory_project_data_source.dart';
import 'package:ductletor_pro/features/projects/domain/auto_saver.dart';
import 'package:ductletor_pro/features/project_editor/presentation/providers/project_editor_provider.dart';
import 'package:ductletor_pro/features/projects/data/file_project_data_source.dart';
import 'package:ductletor_pro/features/projects/data/project_data_source.dart';
import 'package:ductletor_pro/features/projects/data/project_repository_impl.dart';
import 'support/test_project.dart';
import 'package:ductletor_pro/features/project_editor/domain/tree_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

ProjectDoc doc(String id, {String name = 'P'}) => ProjectDoc(
      id: id, name: name, imperial: false, settings: const EngineSettings(),
      root: blankProject(), updatedAt: DateTime.utc(2026, 10, 14),
    );

class CountingStore extends MemoryProjectDataSource {
  int saves = 0;
  bool failing = false;
  @override
  Future<void> save(ProjectDoc d) {
    if (failing) return Future.error(StateError('disk full'));
    saves++;
    return super.save(d);
  }
}

AutoSaver makeSaver(TestProject c, ProjectDataSource store, Duration debounce) {
  final saver = AutoSaver(
    repository: ProjectRepositoryImpl(store),
    readDoc: c.toDoc,
    readRevision: () => c.revision,
    debounce: debounce,
  );
  c.container.listen(projectEditorProvider, (_, __) => saver.notifyChanged());
  return saver;
}

Future<void> settle([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('FileProjectStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ductletor_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('save, list, load, delete; no temp files left', () async {
      final s = FileProjectDataSource(dir);
      await s.save(doc('a', name: 'Alpha'));
      await s.save(doc('b', name: 'Beta'));
      expect((await s.list()).map((m) => m.name).toSet(), {'Alpha', 'Beta'});
      expect((await s.load('a'))!.root.children.length, 1);
      expect(dir.listSync().any((f) => f.path.endsWith('.tmp')), isFalse);
      await s.delete('a');
      expect(await s.load('a'), isNull);
    });

    test('corrupt files are skipped in the list and throw on load', () async {
      final s = FileProjectDataSource(dir);
      await s.save(doc('ok'));
      File('${dir.path}/bad.json').writeAsStringSync('not json');
      expect((await s.list()).length, 1);
      expect(() => s.load('bad'), throwsA(anything));
    });

    test('ids cannot escape the folder', () async {
      final s = FileProjectDataSource(dir);
      await s.save(doc('../evil'));
      expect(dir.listSync().length, 1);
    });
  });

  test('controller survives a save/load round trip', () async {
    final store = MemoryProjectDataSource();
    final c = TestProject(root: blankProject(), name: 'X');
    c.addFitting('trunk', const Elbow(count: 2));
    c.setImperial(true);
    await store.save(c.toDoc());
    final back = TestProject.fromDoc((await store.load(c.id))!);
    expect(back.name, 'X');
    expect(back.imperial, isTrue);
    expect(back.result.requiredFanPa, closeTo(c.result.requiredFanPa, 1e-9));
    expect(findNode(back.root, 'trunk')!.fittings.length, 1);
  });

  group('AutoSaver', () {
    test('saves after a change; selection does not trigger a save', () async {
      final store = CountingStore();
      final c = TestProject(root: blankProject());
      final saver = makeSaver(c, store, const Duration(milliseconds: 20));
      c.select('trunk');
      c.toggleCollapsed('ahu');
      await settle();
      expect(store.saves, 0);
      c.updateNode('trunk', lengthM: 20);
      expect(saver.status, SaveStatus.pending);
      await settle();
      expect(saver.status, SaveStatus.saved);
      expect(findNode((await store.load(c.id))!.root, 'trunk')!.lengthM, 20);
      await saver.close();
    });

    test('rapid edits coalesce into one write', () async {
      final store = CountingStore();
      final c = TestProject(root: blankProject());
      final saver = makeSaver(c, store, const Duration(milliseconds: 40));
      for (var i = 1; i <= 5; i++) {
        c.updateNode('trunk', lengthM: 10.0 + i);
      }
      await settle(200);
      expect(store.saves, 1);
      await saver.close();
    });

    test('close flushes pending changes', () async {
      final store = CountingStore();
      final c = TestProject(root: blankProject());
      final saver = makeSaver(c, store, const Duration(seconds: 5));
      c.rename('Renamed');
      await saver.close();
      expect((await store.load(c.id))!.name, 'Renamed');
    });

    test('a failed save reports an error and the next change retries', () async {
      final store = CountingStore()..failing = true;
      final c = TestProject(root: blankProject());
      final saver = makeSaver(c, store, const Duration(milliseconds: 20));
      c.updateNode('trunk', lengthM: 12);
      await settle();
      expect(saver.status, SaveStatus.error);
      store.failing = false;
      c.updateNode('trunk', lengthM: 14);
      await settle();
      expect(saver.status, SaveStatus.saved);
      expect(findNode((await store.load(c.id))!.root, 'trunk')!.lengthM, 14);
      await saver.close();
    });
  });

  group('ProjectLibrary', () {
    test('first run creates a sample project and opens it', () async {
      final lib = TestLibrary(debounce: const Duration(milliseconds: 10));
      await lib.init();
      expect(lib.active, isNotNull);
      expect(lib.projects.length, 1);
      await lib.flush();
    });

    test('create, open, rename, duplicate and delete', () async {
      final store = MemoryProjectDataSource();
      final lib = TestLibrary(source: store, debounce: const Duration(milliseconds: 10));
      await lib.init();
      final first = lib.active!.id;
      await lib.create('Second');
      expect(lib.projects.length, 2);
      expect(lib.active!.name, 'Second');
      await lib.rename(lib.active!.id, 'Renamed');
      expect((await store.load(lib.active!.id))!.name, 'Renamed');
      await lib.duplicate(first);
      expect(lib.projects.length, 3);
      expect(await lib.open(first), isTrue);
      expect(lib.active!.id, first);
      await lib.delete(first);
      expect(lib.projects.length, 2);
      expect(lib.active, isNotNull);
      expect(lib.active!.id, isNot(first));
      await lib.flush();
    });

    test('edits made in the open project are saved without extra calls', () async {
      final store = MemoryProjectDataSource();
      final lib = TestLibrary(source: store, debounce: const Duration(milliseconds: 10));
      await lib.init();
      final c = lib.active!;
      c.updateNode('trunk', lengthM: 33);
      await settle();
      expect(findNode((await store.load(c.id))!.root, 'trunk')!.lengthM, 33);
      await lib.flush();
    });

    test('deleting the last project leaves a fresh one open', () async {
      final lib = TestLibrary(debounce: const Duration(milliseconds: 10));
      await lib.init();
      await lib.delete(lib.active!.id);
      expect(lib.projects.length, 1);
      expect(lib.active, isNotNull);
      await lib.flush();
    });
  });
}
