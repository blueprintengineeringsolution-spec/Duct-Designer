import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/inspector/presentation/critical_path_card.dart';
import 'package:ductletor_pro/features/inspector/presentation/nc_gauge.dart';
import 'package:ductletor_pro/features/network/presentation/network_page.dart';
import 'support/test_project.dart';
import 'package:ductletor_pro/features/project_editor/domain/tree_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NC bands', () {
    expect(ncBand(30, 35), NcBand.within);
    expect(ncBand(32, 35), NcBand.near);
    expect(ncBand(35, 35), NcBand.near);
    expect(ncBand(36, 35), NcBand.over);
    expect(ncBandLabel(NcBand.over), 'Over limit');
  });

  testWidgets('gauge shows the value and band, with a spoken label', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: NcGauge(nc: 41, limit: 35)))));
    expect(find.text('41'), findsOneWidget);
    expect(find.text('Over limit'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Estimated NC 41, limit 35')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('gauge handles values outside the scale', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [NcGauge(nc: 5, limit: 35), NcGauge(nc: 90, limit: 35)]))));
    expect(find.text('5'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
  });

  testWidgets('critical path card lists the path and the total', (t) async {
    final c = TestProject(root: sampleProject(), name: 'P');
    await t.pumpWidget(c.app(Scaffold(body: SingleChildScrollView(child: CriticalPathCard()))));
    for (final id in c.result.criticalPath) {
      expect(find.text(findNode(c.root, id)!.name), findsOneWidget);
    }
    expect(find.text('Total system'), findsOneWidget);
    expect(find.text(c.fmt.pressure(c.result.requiredFanPa)), findsWidgets);
  });

  testWidgets('tapping a path row reports its id', (t) async {
    final c = TestProject(root: sampleProject(), name: 'P');
    String? opened;
    await t.pumpWidget(c.app(Scaffold(body: SingleChildScrollView(child: CriticalPathCard(onOpen: (id) => opened = id)))));
    final last = c.result.criticalPath.last;
    await t.tap(find.text(findNode(c.root, last)!.name));
    expect(opened, last);
  });

  testWidgets('undo button on the network page reverses Add Node', (t) async {
    final c = TestProject(root: sampleProject(), name: 'P');
    await t.pumpWidget(c.app(const NetworkPage()));
    final before = allNodes(c.root).length;
    await t.tap(find.text('Add Node'));
    await t.pump();
    expect(allNodes(c.root).length, before + 1);
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
    expect(allNodes(c.root).length, before);
    await t.tap(find.byTooltip('Redo'));
    await t.pump();
    expect(allNodes(c.root).length, before + 1);
  });
}
