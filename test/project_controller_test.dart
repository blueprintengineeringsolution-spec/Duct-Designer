import 'package:ductletor_pro/state/project_controller.dart';
import 'package:ductletor_pro/state/tree_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

ProjectController make() => ProjectController(
      root: const DuctNode(id: 'r', name: 'R', lengthM: 5, children: [
        DuctNode(id: 'a', name: 'A', kind: NodeKind.terminal, flow: 0.2, lengthM: 4),
        DuctNode(id: 'b', name: 'B', kind: NodeKind.terminal, flow: 0.3, lengthM: 6),
      ]),
    );

void main() {
  test('addChild to a leaf: first child inherits its flow', () {
    final c = make();
    c.addChild('a');
    final a = findNode(c.root, 'a')!;
    expect(a.children.single.flow, 0.2);
    expect(c.result.nodes['r']!.flow, closeTo(0.5, 1e-9));
  });

  test('delete removes the subtree but never the root', () {
    final c = make();
    c.delete('a');
    expect(findNode(c.root, 'a'), isNull);
    c.delete('r');
    expect(c.root.id, 'r');
  });

  test('duplicate creates unique ids and a copy name', () {
    final c = make();
    c.duplicate('a');
    final ids = allNodes(c.root).map((n) => n.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(c.root.children.last.name, 'A copy');
  });

  test('editing length recalculates fan pressure', () {
    final c = make();
    final before = c.result.requiredFanPa;
    c.updateNode('b', lengthM: 30);
    expect(c.result.requiredFanPa, greaterThan(before));
  });

  test('chooseSize overrides; editing flow clears the override', () {
    final c = make();
    c.chooseSize('a', const DuctSize.round(0.315));
    expect(c.result.nodes['a']!.size.label, 'Ø315');
    c.updateNode('a', flow: 0.25);
    expect(findNode(c.root, 'a')!.sizeOverride, isNull);
  });

  test('add and remove fitting changes pressure and restores it', () {
    final c = make();
    final base = c.result.requiredFanPa;
    c.addFitting('b', const Elbow(count: 3));
    expect(c.result.requiredFanPa, greaterThan(base));
    c.removeFitting('b', 0);
    expect(c.result.requiredFanPa, closeTo(base, 1e-9));
  });

  test('stepRoundSize walks the catalog and imperial switches it', () {
    final c = make();
    c.stepRoundSize('a', 1);
    final d1 = c.result.nodes['a']!.size.diameterM!;
    c.stepRoundSize('a', 1);
    expect(c.result.nodes['a']!.size.diameterM!, greaterThan(d1));
    c.setImperial(true);
    expect(c.settings.catalog.roundM, SizeCatalog.imperial.roundM);
  });

  test('setSettings changes the method result', () {
    final c = make();
    final before = c.result.nodes['a']!.velocity;
    c.setSettings(c.settings.copyWith(method: SizingMethod.constantVelocity, constantVelocity: 3, useStandardSizes: false));
    expect(c.result.nodes['a']!.velocity, closeTo(3, 0.01));
    expect(before, isNot(closeTo(3, 0.01)));
  });
}
