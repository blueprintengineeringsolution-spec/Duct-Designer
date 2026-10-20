import 'package:ductletor_pro/core/sample_project.dart';
import 'package:ductletor_pro/features/network/network_page.dart';
import 'package:ductletor_pro/features/report/report_page.dart';
import 'package:ductletor_pro/state/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

ChoiceChip chip(WidgetTester t, String unitId) => t.widget<ChoiceChip>(find.byKey(ValueKey('unit-$unitId')));

void main() {
  testWidgets('unit chips say how the unit is doing', (t) async {
    final c = ProjectController(root: blankProject(), name: 'P');
    await t.pumpWidget(MaterialApp(home: NetworkPage(c: c)));
    await t.pumpAndSettle();
    final id = c.activeUnitId;
    expect(chip(t, id).tooltip, 'AHU-01: OK');
    c.setSettings(c.settings.copyWith(maxVelocity: 1.5));
    await t.pumpAndSettle();
    final tip = chip(t, id).tooltip!;
    expect(tip, contains('Over limit'));
    expect(tip, contains('warning'));
  });

  testWidgets('each unit gets its own status', (t) async {
    final c = ProjectController(root: blankProject(), name: 'P');
    c.addUnit();
    final second = c.activeUnitId;
    // a rectangular, very flat duct on the first unit only
    final first = c.units.first;
    c.updateNode(first.children.single.id, shape: DuctShape.rectangular, fixedHeightM: 0.1);
    await t.pumpWidget(MaterialApp(home: NetworkPage(c: c)));
    await t.pumpAndSettle();
    expect(chip(t, first.id).tooltip, contains('Caution'));
    expect(chip(t, second).tooltip, 'AHU-02: OK');
  });

  testWidgets('the report lists every unit with its status; tapping one opens it', (t) async {
    final c = ProjectController(root: sampleProject(), name: 'P');
    c.addUnit();
    final second = c.activeUnitId;
    final first = c.units.first.id;
    await t.pumpWidget(MaterialApp(home: ReportPage(c: c)));
    await t.pumpAndSettle();
    expect(find.text('Units'), findsOneWidget);
    expect(find.byKey(ValueKey('overview-$first')), findsOneWidget);
    expect(find.byKey(ValueKey('overview-$second')), findsOneWidget);
    expect(find.text('Showing'), findsOneWidget);
    await t.tap(find.byKey(ValueKey('overview-$first')));
    await t.pumpAndSettle();
    expect(c.activeUnitId, first);
  });

  testWidgets('a single-unit report has no units list', (t) async {
    final c = ProjectController(root: sampleProject(), name: 'P');
    await t.pumpWidget(MaterialApp(home: ReportPage(c: c)));
    await t.pumpAndSettle();
    expect(find.text('Units'), findsNothing);
  });
}
