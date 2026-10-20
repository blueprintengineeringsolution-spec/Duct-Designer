import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../core/fmt.dart';
import 'schematic_layout.dart';
import 'status_colors.dart';

class SchematicPainter extends CustomPainter {
  final SchematicLayout layout;
  final NetworkResult result;
  final String? selectedId;
  final ColorScheme scheme;
  final Fmt fmt;
  final JunctionType defaultJunction;

  SchematicPainter({
    required this.layout,
    required this.result,
    required this.scheme,
    this.fmt = const Fmt(false),
    this.defaultJunction = JunctionType.tee90,
    this.selectedId,
  });

  late final Set<String> _critical = result.criticalPath.toSet();

  @override
  void paint(Canvas canvas, Size size) {
    _paintEdges(canvas);
    _paintJunctions(canvas);
    for (final n in layout.nodes) {
      _paintNode(canvas, n);
    }
    final sel = selectedId == null ? null : layout.byId(selectedId!);
    if (sel != null) _paintPlus(canvas, sel);
  }

  void _paintEdges(Canvas canvas) {
    for (final child in layout.nodes) {
      final pid = child.parentId;
      if (pid == null) continue;
      final parent = layout.byId(pid)!;
      final res = result.nodes[child.node.id];
      final onCritical = _critical.contains(child.node.id) && _critical.contains(pid);
      final flow = res?.flow ?? 0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (math.sqrt(flow) * 8).clamp(2.0, 9.0)
        ..color = onCritical ? scheme.primary : scheme.outlineVariant;
      final a = parent.rect.centerRight;
      final b = child.rect.centerLeft;
      final midX = (a.dx + b.dx) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(midX, a.dy)
        ..lineTo(midX, b.dy)
        ..lineTo(b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }

  /// One dot at every split (T for a tee, Y for a wye), where the edges branch.
  void _paintJunctions(Canvas canvas) {
    for (final n in layout.nodes) {
      if (n.collapsedWithChildren || n.node.children.length < 2) continue;
      final j = n.node.junction ?? defaultJunction;
      if (j == JunctionType.none) continue;
      final kids = layout.nodes.where((k) => k.parentId == n.node.id).toList();
      if (kids.length < 2) continue;
      final x = (n.rect.right + kids.first.rect.left) / 2;
      final c = Offset(x, n.rect.center.dy);
      canvas.drawCircle(c, 8, Paint()..color = scheme.primary);
      _text(canvas, j == JunctionType.tee90 ? 'T' : 'Y', c.translate(-3.5, -6.5), 12,
          TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: scheme.onPrimary));
    }
  }

  void _paintPlus(Canvas canvas, LaidOutNode n) {
    final c = n.rect.centerRight + const Offset(16, 0);
    canvas.drawCircle(c, 13, Paint()..color = scheme.primary);
    final p = Paint()
      ..color = scheme.onPrimary
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c.translate(-6, 0), c.translate(6, 0), p);
    canvas.drawLine(c.translate(0, -6), c.translate(0, 6), p);
  }

  void _paintNode(Canvas canvas, LaidOutNode n) {
    final r = n.rect;
    final rrect = RRect.fromRectAndRadius(r, const Radius.circular(12));
    final res = result.nodes[n.node.id];
    final status = res?.status ?? NodeStatus.optimal;
    final selected = n.node.id == selectedId;

    canvas.drawShadow(Path()..addRRect(rrect), Colors.black, 3, false);
    canvas.drawRRect(rrect, Paint()..color = scheme.surfaceContainerHigh);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, 6, r.height),
      Paint()..color = statusColor(status),
    );
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.5 : 1
        ..color = selected ? scheme.primary : scheme.outlineVariant,
    );

    final maxW = r.width - 24;
    final onSurface = scheme.onSurface;
    _text(canvas, n.node.name, Offset(r.left + 16, r.top + 8), maxW,
        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: onSurface));
    if (res != null) {
      final size = fmt.size(res.size);
      _text(canvas, '$size · ${fmt.velocity(res.velocity)}',
          Offset(r.left + 16, r.top + 26), maxW,
          TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.85)));
      _text(canvas, '${fmt.flow(res.flow)} · ${fmt.pressure(res.cumulativePa)}',
          Offset(r.left + 16, r.top + 43), maxW,
          TextStyle(fontSize: 10.5, color: onSurface.withValues(alpha: 0.6)));
    }

    if (n.collapsedWithChildren) {
      final c = Offset(r.right, r.center.dy);
      canvas.drawCircle(c, 10, Paint()..color = scheme.primary);
      _text(canvas, '+${n.node.children.length}', c.translate(-8, -6), 20,
          TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: scheme.onPrimary));
    }
  }

  void _text(Canvas canvas, String s, Offset o, double maxW, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(SchematicPainter old) =>
      old.layout != layout ||
      old.result != result ||
      old.selectedId != selectedId ||
      old.scheme != scheme ||
      old.fmt != fmt ||
      old.defaultJunction != defaultJunction;
}
