import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/projects/data/memory_project_data_source.dart';
import 'package:ductletor_pro/features/fittings/presentation/add_fitting_sheet.dart';
import 'support/test_project.dart';
import 'package:ductletor_pro/features/project_editor/domain/tree_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

const elbow = CustomFitting(name: 'Elbow', c: 0.22, code: 'CR3-1', source: 'My source');

Widget host(TestProject c) => c.app(const Scaffold(body: AddFittingSheet(nodeId: 'trunk')));

void main() {
  group('controller', () {
    test('save replaces an entry with the same name and code, and resets the count to 1', () {
      final c = TestProject(root: blankProject());
      c.saveToLibrary(elbow.withCount(5));
      expect((c.library.single as CustomFitting).count, 1);
      c.saveToLibrary(const CustomFitting(name: 'Elbow', c: 0.30, code: 'CR3-1', source: 'Newer'));
      expect(c.library.length, 1);
      expect((c.library.single as CustomFitting).c, 0.30);
      c.saveToLibrary(const CustomFitting(name: 'Elbow', c: 0.4, code: 'CR3-2'));
      expect(c.library.length, 2);
    });

    test('only sourced fittings can be saved', () {
      final c = TestProject(root: blankProject());
      c.saveToLibrary(const Elbow());
      c.saveToLibrary(const Reducer());
      expect(c.library, isEmpty);
    });

    test('adding from the library copies the fitting; later library edits do not change it', () {
      final c = TestProject(root: blankProject());
      c.saveToLibrary(elbow);
      c.addFromLibrary('trunk', 0, count: 3);
      final f = findNode(c.root, 'trunk')!.fittings.single as CustomFitting;
      expect((f.c, f.count), (0.22, 3));
      c.saveToLibrary(const CustomFitting(name: 'Elbow', c: 0.9, code: 'CR3-1'));
      expect((findNode(c.root, 'trunk')!.fittings.single as CustomFitting).c, 0.22);
    });

    test('remove, bad indexes and undo/redo', () {
      final c = TestProject(root: blankProject());
      c.saveToLibrary(elbow);
      c.addFromLibrary('trunk', 9);
      c.removeFromLibrary(9);
      expect(c.library.length, 1);
      c.removeFromLibrary(0);
      expect(c.library, isEmpty);
      c.undo();
      expect(c.library.length, 1);
      c.redo();
      expect(c.library, isEmpty);
    });

    test('library is saved with the project and counts as a saveable change', () {
      final c = TestProject(root: blankProject());
      final r = c.revision;
      c.saveToLibrary(elbow);
      expect(c.revision, greaterThan(r));
      expect(TestProject.fromDoc(c.toDoc()).library.length, 1);
    });
  });

  group('project library', () {
    test('import and duplicate carry the fitting library', () async {
      final store = MemoryProjectDataSource();
      final lib = TestLibrary(source: store, debounce: const Duration(milliseconds: 10));
      await lib.init();
      final src = lib.active!;
      src.saveToLibrary(elbow);
      final doc = (await lib.docFor(src.id))!;
      await lib.importShared(await parseShared(await encodeShareCode(doc)));
      expect(lib.active!.library.length, 1);
      await lib.duplicate(lib.active!.id);
      final copies = (await store.list()).where((m) => m.name.endsWith('copy')).toList();
      expect((await store.load(copies.single.id))!.library.length, 1);
      await lib.flush();
    });
  });

  group('add fitting sheet', () {
    testWidgets('Library tab adds the chosen fitting with the chosen quantity', (t) async {
      final c = TestProject(root: blankProject());
      c.saveToLibrary(elbow);
      await t.pumpWidget(host(c));
      await t.tap(find.text('Library'));
      await t.pumpAndSettle();
      await t.tap(find.text('Elbow (CR3-1)'));
      await t.pump();
      await t.tap(find.byTooltip('Increase Quantity'));
      await t.pump();
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Add fitting'));
      await t.tap(find.widgetWithText(FilledButton, 'Add fitting'));
      await t.pumpAndSettle();
      final f = findNode(c.root, 'trunk')!.fittings.single as CustomFitting;
      expect((f.code, f.count), ('CR3-1', 2));
    });

    testWidgets('nothing is added until a library entry is chosen', (t) async {
      final c = TestProject(root: blankProject());
      c.saveToLibrary(elbow);
      await t.pumpWidget(host(c));
      await t.tap(find.text('Library'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Add fitting'));
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add fitting')).onPressed, isNull);
    });

    testWidgets('Save to project library keeps a Sourced C fitting for reuse', (t) async {
      final c = TestProject(root: blankProject());
      await t.pumpWidget(host(c));
      await t.tap(find.text('Sourced C'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Name'), 'Damper');
      await t.enterText(find.widgetWithText(TextField, 'Loss coefficient C'), '0.6');
      await t.tap(find.text('Save to project library'));
      await t.pump();
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Add fitting'));
      await t.tap(find.widgetWithText(FilledButton, 'Add fitting'));
      await t.pumpAndSettle();
      expect(c.library.single.label, 'Damper');
      expect(findNode(c.root, 'trunk')!.fittings.length, 1);
    });

    testWidgets('empty library explains how to fill it', (t) async {
      final c = TestProject(root: blankProject());
      await t.pumpWidget(host(c));
      await t.tap(find.text('Library'));
      await t.pumpAndSettle();
      expect(find.textContaining('Nothing saved yet'), findsOneWidget);
    });
  });
}
