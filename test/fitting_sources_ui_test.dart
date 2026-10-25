import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/fittings/presentation/add_fitting_sheet.dart';
import 'support/test_project.dart';
import 'package:ductletor_pro/features/project_editor/domain/tree_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

Widget host(TestProject c) => c.app(const Scaffold(body: AddFittingSheet(nodeId: 'trunk')));

void main() {
  testWidgets('Sourced C stores the code and source on the fitting', (t) async {
    final c = TestProject(root: blankProject());
    await t.pumpWidget(host(c));
    await t.tap(find.text('Sourced C'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Elbow');
    await t.enterText(find.widgetWithText(TextField, 'Code (optional)'), 'CR3-1');
    await t.enterText(find.widgetWithText(TextField, 'Source'), 'My licensed source');
    await t.enterText(find.widgetWithText(TextField, 'Loss coefficient C'), '0.22');
    await t.pump();
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Add fitting'));
    await t.tap(find.widgetWithText(FilledButton, 'Add fitting'));
    await t.pumpAndSettle();
    final f = findNode(c.root, 'trunk')!.fittings.single as CustomFitting;
    expect((f.name, f.code, f.source, f.c), ('Elbow', 'CR3-1', 'My licensed source', 0.22));
    expect(c.result.nodes['trunk']!.fittingBreakdown.single.screening, isFalse);
  });

  testWidgets('Table: a bad row shows the line number and blocks Add', (t) async {
    final c = TestProject(root: blankProject());
    await t.pumpWidget(host(c));
    await t.tap(find.text('Table'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Rows: input, coefficient'), '0.2, 0.9\n0.5, abc');
    await t.pump();
    expect(find.textContaining('Line 2'), findsOneWidget);
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Add fitting'));
    final add = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add fitting'));
    expect(add.onPressed, isNull);
  });

  testWidgets('Table: valid rows add a table fitting', (t) async {
    final c = TestProject(root: blankProject());
    await t.pumpWidget(host(c));
    await t.tap(find.text('Table'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Rows: input, coefficient'), '0.2, 0.9\n0.8, 0.6');
    await t.pump();
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Add fitting'));
    await t.tap(find.widgetWithText(FilledButton, 'Add fitting'));
    await t.pumpAndSettle();
    expect(findNode(c.root, 'trunk')!.fittings.single, isA<TableFitting>());
  });

  test('settings flag shows up as a warning on built-in fittings through the controller', () {
    final c = TestProject(root: sampleProject());
    expect(c.result.nodes['trunk']!.warnings.any((w) => w.contains('screening')), isFalse);
    c.setSettings(c.settings.copyWith(requireSourcedFittings: true));
    expect(c.result.nodes['trunk']!.warnings.any((w) => w.contains('screening')), isTrue);
    c.undo();
    expect(c.settings.requireSourcedFittings, isFalse);
  });
}
