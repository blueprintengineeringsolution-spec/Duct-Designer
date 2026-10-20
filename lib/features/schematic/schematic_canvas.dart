import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../core/fmt.dart';
import 'schematic_layout.dart';
import 'schematic_painter.dart';

/// Pinch-zoom / pan schematic. Tap = inspect, long-press = collapse/expand,
/// double-tap = fit to screen.
class SchematicCanvas extends StatefulWidget {
  final DuctNode root;
  final NetworkResult result;
  final Set<String> collapsed;
  final String? selectedId;
  final ValueChanged<String> onNodeTap;
  final ValueChanged<String>? onNodeLongPress;
  final ValueChanged<String>? onNodeDoubleTap; // double-tap a node (empty space fits the diagram)
  final ValueChanged<String>? onAddChild; // the + handle beside the selected node
  final VoidCallback? onBackgroundTap;
  final Fmt fmt;
  final JunctionType defaultJunction;

  const SchematicCanvas({
    super.key,
    required this.root,
    required this.result,
    required this.onNodeTap,
    this.onNodeLongPress,
    this.collapsed = const {},
    this.selectedId,
    this.fmt = const Fmt(false),
    this.onNodeDoubleTap,
    this.onAddChild,
    this.onBackgroundTap,
    this.defaultJunction = JunctionType.tee90,
  });

  @override
  State<SchematicCanvas> createState() => _SchematicCanvasState();
}

class _SchematicCanvasState extends State<SchematicCanvas> {
  final _tc = TransformationController();
  late SchematicLayout _layout;
  Size? _viewport;
  bool _fitted = false;
  Offset? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    _layout = layoutNetwork(widget.root, collapsed: widget.collapsed);
  }

  @override
  void didUpdateWidget(SchematicCanvas old) {
    super.didUpdateWidget(old);
    if (!identical(old.root, widget.root) || !setEquals(old.collapsed, widget.collapsed)) {
      _layout = layoutNetwork(widget.root, collapsed: widget.collapsed);
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _fit() {
    final vp = _viewport;
    if (vp == null) return;
    final s = math
        .min(vp.width / _layout.size.width, vp.height / _layout.size.height)
        .clamp(0.2, 1.0)
        .toDouble();
    final dx = (vp.width - _layout.size.width * s) / 2;
    final dy = (vp.height - _layout.size.height * s) / 2;
    _tc.value = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(dx, dy, 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      _viewport = Size(c.maxWidth, c.maxHeight);
      if (!_fitted) {
        _fitted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
      }
      return Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _tc,
            constrained: false,
            minScale: 0.2,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(400),
            child: GestureDetector(
              onTapUp: (d) {
                final sel = widget.selectedId;
                if (sel != null && widget.onAddChild != null) {
                  final n = _layout.byId(sel);
                  if (n != null && _layout.plusRect(n).contains(d.localPosition)) {
                    widget.onAddChild!(sel);
                    return;
                  }
                }
                final hit = _layout.hitTest(d.localPosition);
                if (hit != null) {
                  widget.onNodeTap(hit.node.id);
                } else {
                  widget.onBackgroundTap?.call();
                }
              },
              onLongPressStart: (d) {
                final hit = _layout.hitTest(d.localPosition);
                if (hit != null && hit.node.children.isNotEmpty) {
                  widget.onNodeLongPress?.call(hit.node.id);
                }
              },
              onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: () {
                final p = _doubleTapAt;
                final hit = p == null ? null : _layout.hitTest(p);
                if (hit != null && widget.onNodeDoubleTap != null) {
                  widget.onNodeDoubleTap!(hit.node.id);
                } else {
                  _fit(); // double-tap on empty space fits the diagram to the screen
                }
              },
              child: CustomPaint(
                size: _layout.size,
                painter: SchematicPainter(
                  layout: _layout,
                  result: widget.result,
                  selectedId: widget.selectedId,
                  scheme: scheme,
                  fmt: widget.fmt,
                  defaultJunction: widget.defaultJunction,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'fit',
            tooltip: 'Fit to screen',
            onPressed: _fit,
            child: const Icon(Icons.fit_screen),
          ),
        ),
      ]);
    });
  }
}
