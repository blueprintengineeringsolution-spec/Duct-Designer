import 'dart:math' as math;
import 'package:flutter/material.dart';

enum NcBand { within, near, over }

/// Within the limit, within 3 of it, or over it.
NcBand ncBand(double nc, double limit) {
  if (nc > limit) return NcBand.over;
  if (nc >= limit - 3) return NcBand.near;
  return NcBand.within;
}

String ncBandLabel(NcBand b) {
  switch (b) {
    case NcBand.within:
      return 'Within limit';
    case NcBand.near:
      return 'Near limit';
    case NcBand.over:
      return 'Over limit';
  }
}

Color ncBandColor(NcBand b) {
  switch (b) {
    case NcBand.within:
      return const Color(0xFF2E9E5B);
    case NcBand.near:
      return const Color(0xFFE0A100);
    case NcBand.over:
      return const Color(0xFFD64545);
  }
}

/// 240-degree arc gauge for the estimated NC, with a tick at the project limit.
class NcGauge extends StatelessWidget {
  final double nc, limit, size;
  const NcGauge({super.key, required this.nc, required this.limit, this.size = 150});

  static const double minNc = 15, maxNc = 65;

  @override
  Widget build(BuildContext context) {
    final band = ncBand(nc, limit);
    final scheme = Theme.of(context).colorScheme;
    final label = ncBandLabel(band);
    return Semantics(
      label: 'Estimated NC ${nc.round()}, limit ${limit.round()}. $label.',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: Size(size, size),
              painter: _GaugePainter(
                nc: nc,
                limit: limit,
                fill: ncBandColor(band),
                track: scheme.surfaceContainerHighest,
                tick: scheme.onSurface,
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('NC', style: Theme.of(context).textTheme.labelMedium),
              Text('${nc.round()}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ncBandColor(band))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double nc, limit;
  final Color fill, track, tick;
  const _GaugePainter({required this.nc, required this.limit, required this.fill, required this.track, required this.tick});

  static const double _start = 150 * math.pi / 180;
  static const double _sweep = 240 * math.pi / 180;

  double _t(double v) => ((v - NcGauge.minNc) / (NcGauge.maxNc - NcGauge.minNc)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 11.0;
    final r = math.min(size.width, size.height) / 2 - w;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, base..color = track);
    final t = _t(nc);
    if (t > 0) canvas.drawArc(rect, _start, _sweep * t, false, base..color = fill);

    final a = _start + _sweep * _t(limit);
    final p1 = c + Offset(math.cos(a), math.sin(a)) * (r - w / 2 - 3);
    final p2 = c + Offset(math.cos(a), math.sin(a)) * (r + w / 2 + 3);
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = tick
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.nc != nc || o.limit != limit || o.fill != fill || o.track != track || o.tick != tick;
}
