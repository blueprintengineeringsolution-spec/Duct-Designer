import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/settings/presentation/project_settings_page.dart';
import 'package:ductletor_pro/features/share/presentation/share_actions.dart';
import 'support/test_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

const mine = CustomFitting(name: 'Elbow', c: 0.22, code: 'CR3-1', source: 'Mine');

TestProject make() {
  final c = TestProject(root: blankProject());
  c.saveToLibrary(mine);
  return c;
}

Widget host(TestProject c, String text) => c.app(
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(onPressed: () => importLibraryText(context, ref, text), child: const Text('go')),
          ),
        ),
      ),
    );

void main() {
  group('controller merge', () {
    test('adds new entries, keeps clashing ones by default, and is one undo step', () {
      final c = make();
      final incoming = [
        const CustomFitting(name: 'Elbow', c: 0.5, code: 'CR3-1', source: 'Theirs'),
        const CustomFitting(name: 'Damper', c: 0.6),
        const CustomFitting(name: 'Filter', c: 0.9),
      ];
      expect(c.countLibraryConflicts(incoming), 1);
      final r = c.importLibrary(incoming, overwrite: false);
      expect((r.added, r.replaced, r.skipped), (2, 0, 1));
      expect((c.library.first as CustomFitting).c, 0.22);
      expect(c.library.length, 3);
      c.undo();
      expect(c.library.length, 1);
    });

    test('overwrite replaces clashing entries', () {
      final c = make();
      final r = c.importLibrary([const CustomFitting(name: 'Elbow', c: 0.5, code: 'CR3-1', source: 'Theirs')], overwrite: true);
      expect((r.added, r.replaced, r.skipped), (0, 1, 0));
      expect((c.library.single as CustomFitting).source, 'Theirs');
    });

    test('nothing changes (and no undo step) when everything is skipped', () {
      final c = make();
      final before = c.revision;
      c.importLibrary([mine], overwrite: false);
      expect(c.revision, before);
    });

    test('built-in fittings are skipped and the library cap is respected', () {
      final c = TestProject(root: blankProject());
      final many = [for (var i = 0; i < maxLibraryEntries + 5; i++) CustomFitting(name: 'F$i', c: 0.1)];
      final r = c.importLibrary([const Elbow(), ...many], overwrite: false);
      expect(r.added, maxLibraryEntries);
      expect(r.skipped, 6);
      expect(c.library.length, maxLibraryEntries);
    });
  });

  group('import flow', () {
    final theirs = encodeLibraryFile([
      const CustomFitting(name: 'Elbow', c: 0.5, code: 'CR3-1', source: 'Theirs'),
      const CustomFitting(name: 'Damper', c: 0.6),
    ]);

    testWidgets('clashes ask first; Replace overwrites and reports', (t) async {
      final c = make();
      await t.pumpWidget(host(c, theirs));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Some fittings already exist'), findsOneWidget);
      await t.tap(find.text('Replace with imported'));
      await t.pumpAndSettle();
      expect(c.library.length, 2);
      expect((c.library.first as CustomFitting).c, 0.5);
      expect(find.textContaining('added 1, replaced 1, skipped 0'), findsOneWidget);
    });

    testWidgets('Keep mine adds only the new ones', (t) async {
      final c = make();
      await t.pumpWidget(host(c, theirs));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keep mine'));
      await t.pumpAndSettle();
      expect((c.library.first as CustomFitting).c, 0.22);
      expect(c.library.length, 2);
    });

    testWidgets('Cancel changes nothing', (t) async {
      final c = make();
      await t.pumpWidget(host(c, theirs));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.library.length, 1);
    });

    testWidgets('no clashes imports straight away', (t) async {
      final c = TestProject(root: blankProject());
      await t.pumpWidget(host(c, theirs));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Some fittings already exist'), findsNothing);
      expect(c.library.length, 2);
    });

    testWidgets('a bad file shows a plain message', (t) async {
      final c = make();
      await t.pumpWidget(host(c, 'not a library'));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Could not import'), findsOneWidget);
      expect(c.library.length, 1);
    });
  });

  testWidgets('Settings: Export is disabled while the library is empty', (t) async {
    final c = TestProject(root: blankProject());
    await t.pumpWidget(c.app(const ProjectSettingsPage()));
    await t.scrollUntilVisible(find.text('Export'), 400, scrollable: find.byType(Scrollable).first);
    Finder export() => find.ancestor(of: find.text('Export'), matching: find.byWidgetPredicate((w) => w is OutlinedButton));
    expect(t.widget<OutlinedButton>(export()).onPressed, isNull);
    expect(find.text('Import'), findsOneWidget);
    c.saveToLibrary(mine);
    await t.pump();
    expect(t.widget<OutlinedButton>(export()).onPressed, isNotNull);
  });
}
