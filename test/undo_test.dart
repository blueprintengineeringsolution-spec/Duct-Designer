import 'package:ductletor_pro/core/sample_project.dart';
import 'package:ductletor_pro/state/project_controller.dart';
import 'package:ductletor_pro/state/tree_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

ProjectController make() => ProjectController(root: blankProject(), name: 'P');
double len(ProjectController c) => findNode(c.root, 'trunk')!.lengthM;

void main() {
  test('undo and redo restore a field edit', () {
    final c = make();
    c.updateNode('trunk', lengthM: 25);
    expect(len(c), 25);
    c.undo();
    expect(len(c), 10);
    expect(c.canRedo, isTrue);
    c.redo();
    expect(len(c), 25);
    expect(c.canRedo, isFalse);
  });

  test('structure edits are undoable: add, duplicate, delete', () {
    final c = make();
    c.addChild('trunk');
    expect(allNodes(c.root).length, 3);
    c.undo();
    expect(allNodes(c.root).length, 2);
    c.duplicate('trunk');
    expect(allNodes(c.root).length, 3);
    c.undo();
    c.delete('trunk');
    expect(findNode(c.root, 'trunk'), isNull);
    c.undo();
    expect(findNode(c.root, 'trunk'), isNotNull);
  });

  test('settings, units, details and name are undoable', () {
    final c = make();
    c.setSettings(c.settings.copyWith(method: SizingMethod.constantVelocity));
    c.undo();
    expect(c.settings.method, SizingMethod.equalFriction);
    c.setImperial(true);
    c.undo();
    expect(c.imperial, isFalse);
    expect(identical(c.settings.catalog, SizeCatalog.metric), isTrue);
    c.setInfo(const ReportInfo(company: 'X'));
    c.undo();
    expect(c.info.company, '');
    c.rename('New name');
    c.undo();
    expect(c.name, 'P');
  });

  test('a new edit clears the redo stack; selection and collapse are not history', () {
    final c = make();
    c.updateNode('trunk', lengthM: 20);
    c.undo();
    c.select('trunk');
    c.toggleCollapsed('ahu');
    expect(c.canRedo, isTrue);
    c.updateNode('trunk', lengthM: 30);
    expect(c.canRedo, isFalse);
    c.undo();
    expect(len(c), 10);
    expect(c.canUndo, isFalse);
  });

  test('history is capped at 100 steps', () {
    final c = make();
    for (var i = 1; i <= 120; i++) {
      c.updateNode('trunk', lengthM: 10.0 + i);
    }
    var n = 0;
    while (c.canUndo) {
      c.undo();
      n++;
    }
    expect(n, 100);
    expect(len(c), 30); // state after edit 20
  });

  test('undo and redo count as saveable changes', () {
    final c = make();
    c.updateNode('trunk', lengthM: 20);
    final r = c.revision;
    c.undo();
    expect(c.revision, greaterThan(r));
    final r2 = c.revision;
    c.redo();
    expect(c.revision, greaterThan(r2));
  });

  test('results follow undo', () {
    final c = make();
    final base = c.result.requiredFanPa;
    c.addFitting('trunk', const Elbow(count: 4));
    expect(c.result.requiredFanPa, greaterThan(base));
    c.undo();
    expect(c.result.requiredFanPa, closeTo(base, 1e-9));
  });
}
