import 'dart:math' as math;

/// A point in metres (AR world space).
class Point3 {
  final double x, y, z;
  const Point3(this.x, this.y, this.z);
  double distanceTo(Point3 o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

/// Segment lengths (m) of one measured run. Segments can come from AR taps or typed
/// tape / laser readings; the total becomes a section length.
class LengthRun {
  final List<double> segmentsM;
  const LengthRun([this.segmentsM = const []]);

  static const double minSegmentM = 0.01;
  static const double maxSegmentM = 100;

  static bool isValidSegment(double m) => m.isFinite && m >= minSegmentM && m <= maxSegmentM;

  /// Returns the same run if [m] is not a usable length.
  LengthRun add(double m) => isValidSegment(m) ? LengthRun([...segmentsM, m]) : this;

  LengthRun undo() => segmentsM.isEmpty ? this : LengthRun(segmentsM.sublist(0, segmentsM.length - 1));

  double get totalM => segmentsM.fold(0.0, (a, b) => a + b);

  /// Rule-of-thumb error: phone AR is roughly 2% of the distance plus 1 cm per tap;
  /// a tape or laser reading is taken as 0.2%. Not a guarantee.
  double estimatedErrorM({required bool fromAr}) =>
      fromAr ? 0.02 * totalM + 0.01 * (segmentsM.length + 1) : 0.002 * totalM;

  List<String> warnings({required bool fromAr}) {
    final w = <String>[];
    if (segmentsM.isEmpty) return w;
    if (fromAr && segmentsM.any((s) => s < 0.05)) {
      w.add('A segment is under 5 cm. It may be tap jitter; undo it if so.');
    }
    if (fromAr && segmentsM.any((s) => s > 10)) {
      w.add('AR accuracy drops over long distances. Confirm long runs with a tape.');
    }
    if (totalM > 30) w.add('Total is over 30 m. Consider splitting this into sections.');
    return w;
  }
}

/// Rounds a length for use in a design: nearest 5 cm, or 3 in (0.25 ft) in imperial.
double roundLength(double m, {bool imperial = false}) {
  if (!m.isFinite || m <= 0) return 0;
  final step = imperial ? 0.0762 : 0.05;
  final n = (m / step).round();
  return ((n < 1 ? 1 : n) * step * 1e4).round() / 1e4;
}
