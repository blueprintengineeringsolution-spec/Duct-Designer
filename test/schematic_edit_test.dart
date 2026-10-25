import 'package:ductletor_pro/features/projects/domain/sample_projects.dart';
import 'package:ductletor_pro/features/network/presentation/network_page.dart';
import 'package:ductletor_pro/features/schematic/presentation/schematic_layout.dart';
import 'package:ductletor_pro/features/schematic/presentation/schematic_painter.dart';
import 'support/test_project.dart';
import 'package:ductletor_pro/features/project_editor/domain/tree_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

Future<TestProject> openNetwork(WidgetTester t, {DuctNode? root}) async {
  final c = TestProject(root: root ?? sampleProject(), name: 'P');
  await t.pumpWidget(c.app(const NetworkPage()));
  await t.pumpAndSettle();
  return c;
}

Finder get _canvas => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is SchematicPainter);

/// Where a point of the diagram ends up on screen (after fit-to-screen scaling).
Offset onScreen(WidgetTester t, Offset scenePoint) =>
    t.renderObject<RenderBox>(_canvas).localToGlobal(scenePoint);

Offset nodeCentre(WidgetTester t, TestProject c, String id) => onScreen(
    t, layoutNetwork(c.root, collapsed: c.collapsed).byId(id)!.rect.center);

int count(TestProject c) => allNodes(c.root).length;

/// The diagram also listens for double-taps (fit to screen), so a single tap is reported
/// only after the double-tap window has passed.
Future<void> tapScreen(WidgetTester t, Offset p) async {
  await t.tapAt(p);
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpAndSettle();
}

Finder nameField(String text) =>
    find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text);

/// Two quick taps on the same spot.
Future<void> doubleTapScreen(WidgetTester t, Offset p) async {
  await t.tapAt(p);
  await t.pump(const Duration(milliseconds: 50));
  await t.tapAt(p);
  await t.pumpAndSettle();
}

/// Double-tap a section to edit it.
Future<void> openInspector(WidgetTester t, TestProject c, String id) =>
    doubleTapScreen(t, nodeCentre(t, c, id));

Future<void> scrollInspectorTo(WidgetTester t, Finder f) =>
    t.scrollUntilVisible(
      f,
      300,
      scrollable: find
          .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable))
          .first,
    );

void main() {
  testWidgets('there is no tree view, only the diagram', (t) async {
    await openNetwork(t);
    expect(find.text('Tree'), findsNothing);
    expect(find.text('Schematic'), findsNothing);
    expect(_canvas, findsOneWidget);
  });

  group('select with a tap, edit with a double-tap', () {
    testWidgets('a single tap only selects: the editor stays closed',
        (t) async {
      final c = await openNetwork(t);
      await tapScreen(t, nodeCentre(t, c, 't1'));
      expect(c.selectedId, 't1');
      expect(find.text('Round'), findsNothing);
      expect(find.text('Edit section'), findsOneWidget);
    });

    testWidgets(
        'the Edit section button opens the editor for the selected section',
        (t) async {
      final c = await openNetwork(t);
      c.select('t2');
      await t.pumpAndSettle();
      await t.tap(find.text('Edit section'));
      await t.pumpAndSettle();
      expect(nameField('Diffuser 2'), findsOneWidget);
    });

    testWidgets('no Edit section button while nothing is selected', (t) async {
      await openNetwork(t);
      expect(find.text('Edit section'), findsNothing);
    });

    testWidgets('double-tapping empty space does not open an editor',
        (t) async {
      final c = await openNetwork(t);
      c.select('t1');
      await t.pumpAndSettle();
      await doubleTapScreen(t, onScreen(t, const Offset(6, 6)));
      expect(find.text('Round'), findsNothing);
    });
  });

  group('double-tap a section to edit it', () {
    testWidgets('opens the editor for that section and selects it', (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, 't1');
      expect(c.selectedId, 't1');
      expect(nameField('Diffuser 1'), findsOneWidget);
      expect(find.text('Round'), findsOneWidget);
    });

    testWidgets('the name can be changed', (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, 't1');
      await t.enterText(nameField('Diffuser 1'), 'Kitchen diffuser');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(findNode(c.root, 't1')!.name, 'Kitchen diffuser');
      expect(c.canUndo, isTrue);
    });

    testWidgets('an empty name is ignored and the old one comes back',
        (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, 't1');
      await t.enterText(nameField('Diffuser 1'), '   ');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(findNode(c.root, 't1')!.name, 'Diffuser 1');
      expect(nameField('Diffuser 1'), findsOneWidget);
    });

    testWidgets(
        'a typed name is kept when the sheet is closed without pressing done',
        (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, 't2');
      await t.enterText(nameField('Diffuser 2'), 'Office 2');
      await t.tapAt(const Offset(400, 20)); // the dimmed area above the sheet
      await t.pumpAndSettle();
      expect(find.text('Round'), findsNothing); // sheet closed
      expect(findNode(c.root, 't2')!.name, 'Office 2');
    });

    testWidgets('renaming the unit root renames the unit', (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, c.root.id);
      await t.enterText(nameField(c.root.name), 'Main supply');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(c.root.name, 'Main supply');
    });

    testWidgets('Add child closes the editor, adds a section and selects it',
        (t) async {
      final c = await openNetwork(t);
      final before = count(c);
      await openInspector(t, c, 't1');
      await t.tap(find.text('Add child'));
      await t.pumpAndSettle();
      expect(find.text('Round'), findsNothing);
      expect(count(c), before + 1);
      expect(findNode(c.root, 't1')!.children.length, 1);
      expect(c.selectedId, isNot('t1'));
    });

    testWidgets('Duplicate adds a copy', (t) async {
      final c = await openNetwork(t);
      final before = count(c);
      await openInspector(t, c, 't1');
      await t.tap(find.text('Duplicate'));
      await t.pumpAndSettle();
      expect(count(c), before + 1);
    });

    testWidgets('Delete removes the section and can be undone from the message',
        (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, 't2');
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(findNode(c.root, 't2'), isNull);
      expect(find.text('Deleted Diffuser 2'), findsOneWidget);
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(findNode(c.root, 't2'), isNotNull);
    });

    testWidgets("the unit's top section has no Delete or Duplicate", (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, c.root.id);
      expect(find.text('Add child'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Duplicate'), findsNothing);
    });

    testWidgets('Collapse and Expand work from the editor', (t) async {
      final c = await openNetwork(t);
      await openInspector(t, c, 'trunk');
      await t.tap(find.text('Collapse'));
      await t.pumpAndSettle();
      expect(c.collapsed, contains('trunk'));
      expect(find.text('Expand'), findsOneWidget);
      await t.tap(find.text('Expand'));
      await t.pumpAndSettle();
      expect(c.collapsed, isEmpty);
    });
  });

  group('on the diagram', () {
    testWidgets('the + handle beside the selected section adds a child',
        (t) async {
      final c = await openNetwork(t);
      c.select('t3');
      await t.pumpAndSettle();
      final before = count(c);
      final layout = layoutNetwork(c.root);
      await tapScreen(
          t, onScreen(t, layout.plusRect(layout.byId('t3')!).center));
      expect(count(c), before + 1);
      expect(
          find.text('Round'), findsNothing); // no editor opened by the handle
    });

    testWidgets('tapping empty space clears the selection', (t) async {
      final c = await openNetwork(t);
      c.select('t1');
      await t.pumpAndSettle();
      await tapScreen(t, onScreen(t, const Offset(6, 6)));
      expect(c.selectedId, isNull);
    });

    testWidgets('long-press collapses a section that has children', (t) async {
      final c = await openNetwork(t);
      await t.longPressAt(nodeCentre(t, c, 'a'));
      await t.pumpAndSettle();
      expect(c.collapsed, contains('a'));
    });

    testWidgets('the Add Node button adds under the selected section',
        (t) async {
      final c = await openNetwork(t);
      c.select('t1');
      await t.pumpAndSettle();
      await t.tap(find.text('Add Node'));
      await t.pumpAndSettle();
      expect(findNode(c.root, 't1')!.children.length, 1);
    });
  });

  group('units', () {
    testWidgets('Add unit creates and shows a second unit', (t) async {
      final c = await openNetwork(t);
      await t.tap(find.byTooltip('Add unit'));
      await t.pumpAndSettle();
      expect(c.units.length, 2);
      expect(find.byKey(ValueKey('unit-${c.units.last.id}')), findsOneWidget);
      expect(c.root.id, c.units.last.id);
    });

    testWidgets('tapping a unit chip switches the diagram to that unit',
        (t) async {
      final c = await openNetwork(t);
      final first = c.units.first.id;
      c.addUnit();
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('unit-$first')));
      await t.pumpAndSettle();
      expect(c.activeUnitId, first);
      await openInspector(t, c, 't1'); // a section of the first unit again
      expect(c.selectedId, 't1');
    });

    testWidgets('rename and delete from the unit menu', (t) async {
      final c = await openNetwork(t);
      c.addUnit();
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Unit actions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rename unit'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Kitchen supply');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(c.root.name, 'Kitchen supply');
      expect(find.text('Kitchen supply'), findsOneWidget);

      await t.tap(find.byTooltip('Unit actions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete unit'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(c.units.length, 1);
    });
  });

  group('tee at a split', () {
    testWidgets('the editor of a split section shows the automatic tee choice',
        (t) async {
      t.view.physicalSize = const Size(800, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = await openNetwork(t, root: blankProject());
      c.addChild('trunk');
      c.addChild('trunk');
      await t.pumpAndSettle();
      await openInspector(t, c, 'trunk');
      await scrollInspectorTo(t, find.text('Split type'));
      expect(find.text('Automatic (90° tee)'), findsOneWidget);
      c.setSettings(c.settings.copyWith(defaultJunction: JunctionType.none));
      await t.pumpAndSettle();
      expect(find.text('Automatic (none)'), findsOneWidget);
    });

    test('a second child makes the loss appear without anyone adding a tee',
        () {
      final c = TestProject(root: blankProject(), name: 'P');
      c.addChild('trunk');
      expect(
          c
              .nodeResult(c.root.children.single.children.single.id)!
              .fittingBreakdown,
          isEmpty);
      c.addChild('trunk');
      final kids = c.root.children.single.children;
      expect(kids.length, 2);
      for (final k in kids) {
        expect(
            c
                .nodeResult(k.id)!
                .fittingBreakdown
                .any((f) => f.label.contains('tee')),
            isTrue);
      }
    });
  });
}
