import 'package:ductletor_pro/features/schematic/presentation/schematic_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

const _root = DuctNode(id: 'r', name: 'R', children: [
  DuctNode(id: 'a', name: 'A', children: [
    DuctNode(id: 'a1', name: 'A1', flow: 0.1),
    DuctNode(id: 'a2', name: 'A2', flow: 0.1),
  ]),
  DuctNode(id: 'b', name: 'B', flow: 0.1),
]);

void main() {
  test('children sit right of parents; leaves do not overlap', () {
    final l = layoutNetwork(_root);
    expect(l.nodes.length, 5);
    for (final n in l.nodes) {
      final pid = n.parentId;
      if (pid != null)
        expect(n.rect.left, greaterThan(l.byId(pid)!.rect.right));
    }
    final leaves = l.nodes.where((n) => n.node.children.isEmpty).toList();
    for (var i = 0; i < leaves.length; i++) {
      for (var j = i + 1; j < leaves.length; j++) {
        expect(leaves[i].rect.overlaps(leaves[j].rect), isFalse);
      }
    }
  });

  test('parent is vertically centred on its children', () {
    final l = layoutNetwork(_root);
    final mid =
        (l.byId('a1')!.rect.center.dy + l.byId('a2')!.rect.center.dy) / 2;
    expect(l.byId('a')!.rect.center.dy, closeTo(mid, 1e-9));
  });

  test('collapse hides descendants and flags the node', () {
    final l = layoutNetwork(_root, collapsed: {'a'});
    expect(l.nodes.length, 3);
    expect(l.byId('a')!.collapsedWithChildren, isTrue);
    expect(l.byId('a1'), isNull);
  });

  test('hitTest returns node under point, null elsewhere', () {
    final l = layoutNetwork(_root);
    expect(l.hitTest(l.byId('b')!.rect.center)?.node.id, 'b');
    expect(l.hitTest(const Offset(-50, -50)), isNull);
  });

  test('the plus handle sits just right of its node, clear of the tee marker',
      () {
    final l = layoutNetwork(_root);
    final a = l.byId('a')!;
    final plus = l.plusRect(a);
    expect(plus.center.dx, greaterThan(a.rect.right));
    expect(plus.contains(a.rect.center), isFalse);
    final gapMid = a.rect.right + const LayoutConfig().colGap / 2;
    expect((plus.center.dx - gapMid).abs(),
        greaterThan(8)); // the tee dot is drawn at the gap middle
    expect(l.hitTest(plus.center), isNull);
  });
}
