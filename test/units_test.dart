import 'package:ductletor_pro/core/sample_project.dart';
import 'package:ductletor_pro/data/project_store.dart';
import 'package:ductletor_pro/state/project_controller.dart';
import 'package:ductletor_pro/state/project_library.dart';
import 'package:ductletor_pro/state/tree_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

ProjectController make() => ProjectController(root: blankProject(), name: 'P');

Set<String> allIds(ProjectController c) => {for (final u in c.units) for (final n in allNodes(u)) n.id};
int totalNodes(ProjectController c) => c.units.fold(0, (a, u) => a + allNodes(u).length);

void main() {
  test('a project starts with one unit', () {
    final c = make();
    expect(c.units.length, 1);
    expect(c.activeUnitId, c.units.first.id);
    expect(c.root.id, c.activeUnitId);
  });

  test('adding a unit names it, makes it active and keeps every id unique', () {
    final c = make();
    final id = c.addUnit()!;
    expect(c.units.length, 2);
    expect(c.activeUnitId, id);
    expect(c.root.name, 'AHU-02');
    expect(allIds(c).length, totalNodes(c));
    c.addUnit();
    expect(c.units.map((u) => u.name).toSet().length, 3);
    expect(allIds(c).length, totalNodes(c));
  });

  test('every unit is calculated; result follows the active unit', () {
    final c = make();
    c.updateNode('trunk', lengthM: 40);
    final first = c.result.requiredFanPa;
    c.addUnit();
    expect(c.unitResults.length, 2);
    expect(c.result.requiredFanPa, isNot(closeTo(first, 1e-6)));
    c.setActiveUnit(c.units.first.id);
    expect(c.result.requiredFanPa, closeTo(first, 1e-9));
  });

  test('edits reach the unit that owns the section, whichever unit is showing', () {
    final c = make();
    final u1 = c.units.first.id;
    c.addUnit();
    c.updateNode('trunk', lengthM: 77); // belongs to the first unit
    expect(findNode(c.units.firstWhere((u) => u.id == u1), 'trunk')!.lengthM, 77);
    expect(c.nodeResult('trunk'), isNotNull);
  });

  test('adding children, duplicating and deleting work inside the active unit', () {
    final c = make();
    c.addUnit();
    final u2 = c.activeUnitId;
    final trunk2 = c.root.children.single.id;
    c.addChild(trunk2);
    expect(c.root.id, u2);
    expect(allNodes(c.root).length, 3);
    expect(allNodes(c.units.first).length, 2); // untouched
    c.duplicate(trunk2);
    expect(allIds(c).length, totalNodes(c));
    c.delete(trunk2);
    expect(findNode(c.root, trunk2), isNull);
  });

  test('a unit root is removed with deleteUnit, not delete or duplicate', () {
    final c = make();
    c.addUnit();
    final n = totalNodes(c);
    c.delete(c.activeUnitId);
    c.duplicate(c.activeUnitId);
    expect(totalNodes(c), n);
    expect(c.units.length, 2);
  });

  test('duplicate unit copies the network under new ids', () {
    final c = ProjectController(root: sampleProject(), name: 'P');
    final fan = c.result.requiredFanPa;
    final copyId = c.duplicateUnit(c.activeUnitId)!;
    expect(c.units.length, 2);
    expect(c.activeUnitId, copyId);
    expect(c.root.name, endsWith('copy'));
    expect(allIds(c).length, totalNodes(c));
    expect(c.result.requiredFanPa, closeTo(fan, 1e-9));
  });

  test('delete unit: the last one stays, the active one moves on', () {
    final c = make();
    c.deleteUnit(c.activeUnitId);
    expect(c.units.length, 1);
    final first = c.units.first.id;
    c.addUnit();
    final second = c.activeUnitId;
    c.deleteUnit(second);
    expect(c.units.length, 1);
    expect(c.activeUnitId, first);
    c.select('trunk');
    c.addUnit();
    expect(c.selectedId, isNull);
  });

  test('rename unit', () {
    final c = make();
    c.renameUnit(c.activeUnitId, '  Supply 1 ');
    expect(c.root.name, 'Supply 1');
    c.renameUnit(c.activeUnitId, '   ');
    expect(c.root.name, 'Supply 1');
  });

  test('undo and redo cover units and the active unit', () {
    final c = make();
    final first = c.activeUnitId;
    c.addUnit();
    c.undo();
    expect(c.units.length, 1);
    expect(c.activeUnitId, first);
    c.redo();
    expect(c.units.length, 2);
    c.deleteUnit(c.activeUnitId);
    c.undo();
    expect(c.units.length, 2);
  });

  test('switching units is not history and does not count as a saveable change', () {
    final c = make();
    c.addUnit();
    final rev = c.revision;
    final undoable = c.canUndo;
    c.setActiveUnit(c.units.first.id);
    expect(c.revision, rev);
    expect(c.canUndo, undoable);
  });

  test('the whole project, all units, is saved and restored', () {
    final c = make();
    c.addUnit();
    c.updateNode(c.root.children.single.id, flow: 0.9);
    final back = ProjectController.fromDoc(c.toDoc());
    expect(back.units.length, 2);
    expect(back.unitResults.length, 2);
    expect(back.units.last.children.single.flow, 0.9);
  });

  test('collapsed state of a deleted unit is cleaned up', () {
    final c = make();
    c.addUnit();
    c.toggleCollapsed(c.activeUnitId);
    expect(c.collapsed, contains(c.activeUnitId));
    c.deleteUnit(c.activeUnitId);
    expect(c.collapsed, isEmpty);
  });

  test('the unit cap is respected', () {
    final c = make();
    for (var i = 1; i < maxUnits; i++) {
      c.addUnit();
    }
    expect(c.units.length, maxUnits);
    expect(c.addUnit(), isNull);
    expect(c.duplicateUnit(c.activeUnitId), isNull);
  });

  test('importing or duplicating a project keeps all of its units', () async {
    final store = MemoryProjectStore();
    final lib = ProjectLibrary(store, saveDebounce: const Duration(milliseconds: 10));
    await lib.init();
    lib.active!.addUnit();
    final doc = (await lib.docFor(lib.active!.id))!;
    expect(doc.units.length, 2);
    await lib.importShared(await parseShared(await encodeShareCode(doc)));
    expect(lib.active!.units.length, 2);
    await lib.duplicate(lib.active!.id);
    final copy = (await store.list()).firstWhere((m) => m.name.endsWith('copy'));
    expect((await store.load(copy.id))!.units.length, 2);
    await lib.rename(lib.active!.id, 'Renamed');
    expect((await store.load(lib.active!.id))!.units.length, 2);
    await lib.flush();
  });
}
