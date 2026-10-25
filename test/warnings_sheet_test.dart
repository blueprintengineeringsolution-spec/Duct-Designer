import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/network/presentation/network_page.dart';
import 'support/test_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

Finder nameField(String text) => find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text);

void main() {
  testWidgets('the warnings button counts every warning and says so when there are none', (t) async {
    final c = TestProject(root: blankProject(), name: 'P');
    await t.pumpWidget(c.app(const NetworkPage()));
    await t.pumpAndSettle();
    expect(find.byTooltip('Warnings (0)'), findsOneWidget);
    await t.tap(find.byTooltip('Warnings (0)'));
    await t.pumpAndSettle();
    expect(find.text('No warnings'), findsOneWidget);
    expect(find.textContaining('within the limits'), findsOneWidget);
  });

  testWidgets('a low velocity limit fills the list; the count matches', (t) async {
    final c = TestProject(root: blankProject(), name: 'P');
    c.setSettings(c.settings.copyWith(maxVelocity: 1.5));
    await t.pumpWidget(c.app(const NetworkPage()));
    await t.pumpAndSettle();
    final n = collectWarnings(c.units, c.unitResults).length;
    expect(n, greaterThan(0));
    await t.tap(find.byTooltip('Warnings ($n)'));
    await t.pumpAndSettle();
    expect(find.text('Warnings ($n)'), findsOneWidget);
    expect(find.textContaining('exceeds 1.5 m/s'), findsWidgets);
  });

  testWidgets('tapping a warning in another unit switches to it and opens that section', (t) async {
    final c = TestProject(root: blankProject(), name: 'P');
    c.addUnit();
    final second = c.activeUnitId;
    final trunk2 = c.units.last.children.single.id;
    c.updateNode(trunk2, shape: DuctShape.rectangular, fixedHeightM: 0.1); // aspect warning in unit 2 only
    c.setActiveUnit(c.units.first.id);
    await t.pumpWidget(c.app(const NetworkPage()));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Warnings (1)'));
    await t.pumpAndSettle();
    expect(find.text('AHU-02'), findsWidgets); // the unit heading in the list
    await t.tap(find.textContaining('Aspect ratio'));
    await t.pumpAndSettle();
    expect(c.activeUnitId, second);
    expect(c.selectedId, trunk2);
    expect(nameField('Trunk'), findsOneWidget); // the editor for that section is open
  });

  testWidgets('the list updates when a warning is fixed while it is open', (t) async {
    final c = TestProject(root: blankProject(), name: 'P');
    c.updateNode('trunk', shape: DuctShape.rectangular, fixedHeightM: 0.1);
    await t.pumpWidget(c.app(const NetworkPage()));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Warnings (1)'));
    await t.pumpAndSettle();
    expect(find.textContaining('Aspect ratio'), findsOneWidget);
    c.updateNode('trunk', shape: DuctShape.round, clearFixedHeight: true);
    await t.pumpAndSettle();
    expect(find.text('No warnings'), findsOneWidget);
  });
}
