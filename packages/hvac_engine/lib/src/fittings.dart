import 'dart:convert' show LineSplitter;
import 'dart:math' as math;
import 'acoustics.dart';
import 'duct_math.dart';

/// NOTE: the built-in elbow, reducer and junction coefficients are representative
/// screening values. They are NOT data from the ASHRAE Duct Fitting Database (which
/// is licensed). For design values use [CustomFitting] or [TableFitting] with
/// coefficients from your own licensed source, and record the code and source.

double _interp(List<List<double>> t, double x) {
  if (x <= t.first[0]) return t.first[1];
  if (x >= t.last[0]) return t.last[1];
  for (var i = 1; i < t.length; i++) {
    if (x <= t[i][0]) {
      final a = t[i - 1], b = t[i];
      return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]);
    }
  }
  return t.last[1];
}

const _roundRadius = [[0.5, 0.71], [0.75, 0.33], [1.0, 0.22], [1.5, 0.15], [2.0, 0.13]];
const _rectRadius = [[0.5, 0.45], [0.75, 0.30], [1.0, 0.21], [1.5, 0.17]];
const _angleFactor = [[0.0, 0.0], [20.0, 0.31], [30.0, 0.45], [45.0, 0.60], [60.0, 0.78], [75.0, 0.90], [90.0, 1.0], [180.0, 1.0]];

/// Geometry/velocities at the fitting (upstream = parent section, downstream = this section).
class FittingContext {
  final double upstreamArea, downstreamArea, upstreamV, downstreamV;
  final bool rectangular;
  final double flowRatio; // this section's flow / parent flow (1 for an inline section)
  const FittingContext({
    required this.upstreamArea,
    required this.downstreamArea,
    required this.upstreamV,
    required this.downstreamV,
    required this.rectangular,
    this.flowRatio = 1.0,
  });
}

class FittingLoss {
  final String label;
  final double c, pa;
  final String source; // where the coefficient came from (empty for built-ins)
  final bool screening; // true for built-in approximations
  final String note; // e.g. input outside the table range
  const FittingLoss({
    required this.label,
    required this.c,
    required this.pa,
    this.source = '',
    this.screening = false,
    this.note = '',
  });
}

enum ReferenceVelocity { upstream, downstream }

abstract class Fitting {
  final int count;
  const Fitting({this.count = 1});
  String get label;
  FittingKind get noiseKind;

  /// Returns (loss coefficient C, velocity the coefficient is referenced to).
  (double, double) evaluate(FittingContext ctx);

  /// Same fitting with a different quantity.
  Fitting withCount(int n);

  /// True for built-in approximations (not from a database or manufacturer).
  bool get isScreening => false;
  String get dataSource => '';
  String note(FittingContext ctx) => '';

  FittingLoss loss(FittingContext ctx, double rho) {
    final (c, v) = evaluate(ctx);
    return FittingLoss(
      label: count > 1 ? '$count× $label' : label,
      c: c,
      pa: count * c * velocityPressure(v, rho),
      source: dataSource,
      screening: isScreening,
      note: note(ctx),
    );
  }
}

enum ElbowStyle { smoothRadius, mitered, miteredVanes }

/// Elbow. [radiusRatio] is r/D (round) or r/W (rectangular); ignored for mitered styles.
class Elbow extends Fitting {
  final double angleDeg, radiusRatio;
  final ElbowStyle style;
  const Elbow({
    this.angleDeg = 90,
    this.radiusRatio = 1.0,
    this.style = ElbowStyle.smoothRadius,
    super.count,
  });

  @override
  String get label => '${angleDeg.round()}° elbow';
  @override
  FittingKind get noiseKind => FittingKind.elbow;
  @override
  Fitting withCount(int n) => Elbow(angleDeg: angleDeg, radiusRatio: radiusRatio, style: style, count: n);
  @override
  bool get isScreening => true;
  @override
  String get dataSource => 'Built-in screening value';

  @override
  (double, double) evaluate(FittingContext ctx) {
    final double c90;
    switch (style) {
      case ElbowStyle.smoothRadius:
        c90 = _interp(ctx.rectangular ? _rectRadius : _roundRadius, radiusRatio);
        break;
      case ElbowStyle.mitered:
        c90 = 1.2;
        break;
      case ElbowStyle.miteredVanes:
        c90 = 0.35;
        break;
    }
    return (c90 * _interp(_angleFactor, angleDeg), ctx.downstreamV);
  }
}

/// Reducer / transition. Contraction or expansion is picked from the area change
/// between the parent section and this one. [angleDeg] is the included angle.
class Reducer extends Fitting {
  final double angleDeg;
  const Reducer({this.angleDeg = 30, super.count});

  @override
  String get label => 'Reducer';
  @override
  FittingKind get noiseKind => FittingKind.transition;
  @override
  Fitting withCount(int n) => Reducer(angleDeg: angleDeg, count: n);
  @override
  bool get isScreening => true;
  @override
  String get dataSource => 'Built-in screening value';

  @override
  (double, double) evaluate(FittingContext ctx) {
    final a1 = ctx.upstreamArea, a2 = ctx.downstreamArea;
    if ((a1 - a2).abs() / a1 < 0.01) return (0, ctx.downstreamV);
    if (a2 < a1) {
      // Contraction, referenced to downstream velocity.
      final abrupt = 0.5 * math.pow(1 - a2 / a1, 0.75);
      final t = ((angleDeg - 45) / 135).clamp(0.0, 1.0);
      final c = 0.05 + (math.max(abrupt, 0.05) - 0.05) * t;
      return (c, ctx.downstreamV);
    }
    // Expansion (Gibson): referenced to upstream velocity.
    final ke = angleDeg >= 45 ? 1.0 : math.min(1.0, 2.6 * math.sin(angleDeg * math.pi / 360));
    final c = ke * math.pow(1 - a1 / a2, 2);
    return (c, ctx.upstreamV);
  }
}

/// A fitting with a coefficient from a source you have the right to use (ASHRAE Duct
/// Fitting Database, manufacturer data, a test report...). [code] and [source] are
/// recorded and printed on reports.
class CustomFitting extends Fitting {
  final String name, code, source;
  final double c;
  final ReferenceVelocity reference;
  final FittingKind kind;
  const CustomFitting({
    required this.name,
    required this.c,
    this.code = '',
    this.source = '',
    this.reference = ReferenceVelocity.downstream,
    this.kind = FittingKind.none,
    super.count,
  });

  @override
  String get label => code.isEmpty ? name : '$name ($code)';
  @override
  FittingKind get noiseKind => kind;
  @override
  String get dataSource => source.isEmpty ? 'User entered' : source;
  @override
  Fitting withCount(int n) => CustomFitting(name: name, c: c, code: code, source: source, reference: reference, kind: kind, count: n);
  @override
  (double, double) evaluate(FittingContext ctx) =>
      (c, reference == ReferenceVelocity.upstream ? ctx.upstreamV : ctx.downstreamV);
}

/// What drives a [TableFitting] lookup.
enum TableInput { value, flowRatio, areaRatio, velocityRatio }

/// Coefficient versus one input, entered by the user from their own source.
/// Linear between points; outside the range the nearest value is used and flagged.
class CoefficientTable {
  final List<double> xs, cs;
  CoefficientTable._(this.xs, this.cs);

  factory CoefficientTable.fromPoints(List<(double, double)> points) {
    if (points.isEmpty) throw const FormatException('The table has no points');
    if (points.length > 500) throw const FormatException('The table has too many points (max 500)');
    final sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 0; i < sorted.length; i++) {
      final (x, c) = sorted[i];
      if (!x.isFinite || !c.isFinite || c < 0 || c > 100) {
        throw FormatException('Point ${i + 1} is out of range (coefficients must be 0 to 100)');
      }
      if (i > 0 && x == sorted[i - 1].$1) throw FormatException('Input value $x appears twice');
    }
    return CoefficientTable._([for (final p in sorted) p.$1], [for (final p in sorted) p.$2]);
  }

  factory CoefficientTable.fromJson(Object? j) {
    if (j is! List) throw const FormatException('Table points are missing');
    final pts = <(double, double)>[];
    for (final p in j) {
      if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) {
        throw const FormatException('A table point is not a pair of numbers');
      }
      pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
    }
    return CoefficientTable.fromPoints(pts);
  }

  List<List<double>> toJson() => [
        for (var i = 0; i < xs.length; i++) [xs[i], cs[i]],
      ];

  /// (coefficient, true if [x] was outside the table and the nearest value was used).
  (double, bool) lookup(double x) {
    if (!x.isFinite || x < xs.first) return (cs.first, true);
    if (x > xs.last) return (cs.last, true);
    for (var i = 1; i < xs.length; i++) {
      if (x <= xs[i]) {
        final t = (x - xs[i - 1]) / (xs[i] - xs[i - 1]);
        return (cs[i - 1] + (cs[i] - cs[i - 1]) * t, false);
      }
    }
    return (cs.last, false);
  }
}

/// Lines of "input, coefficient" (comma, semicolon, tab or space separated).
/// A text header line and lines starting with # are ignored.
CoefficientTable parseCoefficientCsv(String text) {
  final pts = <(double, double)>[];
  var lineNo = 0;
  for (final raw in const LineSplitter().convert(text)) {
    lineNo++;
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'[,;\t ]+')).where((s) => s.isNotEmpty).toList();
    final x = parts.length == 2 ? double.tryParse(parts[0]) : null;
    final c = parts.length == 2 ? double.tryParse(parts[1]) : null;
    if (x == null || c == null) {
      if (pts.isEmpty && parts.isNotEmpty && double.tryParse(parts[0]) == null) continue; // header
      throw FormatException('Line $lineNo: expected "input, coefficient"');
    }
    pts.add((x, c));
  }
  return CoefficientTable.fromPoints(pts);
}

class TableFitting extends Fitting {
  final String name, code, source;
  final CoefficientTable table;
  final TableInput input;
  final double x; // used when input == TableInput.value
  final ReferenceVelocity reference;
  final FittingKind kind;
  TableFitting({
    required this.name,
    required this.table,
    this.code = '',
    this.source = '',
    this.input = TableInput.value,
    this.x = 0,
    this.reference = ReferenceVelocity.downstream,
    this.kind = FittingKind.none,
    super.count,
  });

  double _in(FittingContext ctx) {
    switch (input) {
      case TableInput.value:
        return x;
      case TableInput.flowRatio:
        return ctx.flowRatio;
      case TableInput.areaRatio:
        return ctx.upstreamArea > 0 ? ctx.downstreamArea / ctx.upstreamArea : 1;
      case TableInput.velocityRatio:
        return ctx.upstreamV > 0 ? ctx.downstreamV / ctx.upstreamV : 1;
    }
  }

  @override
  String get label => code.isEmpty ? name : '$name ($code)';
  @override
  FittingKind get noiseKind => kind;
  @override
  String get dataSource => source.isEmpty ? 'User entered table' : source;
  @override
  Fitting withCount(int n) => TableFitting(name: name, table: table, code: code, source: source, input: input, x: x, reference: reference, kind: kind, count: n);
  @override
  String note(FittingContext ctx) => table.lookup(_in(ctx)).$2
      ? 'Input ${_in(ctx).toStringAsFixed(2)} is outside the table range; the nearest value was used'
      : '';
  @override
  (double, double) evaluate(FittingContext ctx) => (
        table.lookup(_in(ctx)).$1,
        reference == ReferenceVelocity.upstream ? ctx.upstreamV : ctx.downstreamV,
      );
}

/// Junction at a split. Set on the splitting (parent) node; the child carrying the
/// largest flow takes the "main" loss and the others take the "branch" loss.
enum JunctionType { tee90, wye45, none }

FittingLoss junctionLoss(
  JunctionType t, {
  required bool isMain,
  required double velocityRatio, // branch / common velocity
  required double velocity, // velocity in the section receiving the loss
  required double rho,
}) {
  if (t == JunctionType.none) return const FittingLoss(label: 'No junction', c: 0, pa: 0);
  final tee = t == JunctionType.tee90;
  final name = tee ? '90° tee' : '45° wye';
  if (isMain) {
    final c = tee ? 0.05 : 0.03;
    return FittingLoss(label: '$name – main', c: c, pa: c * velocityPressure(velocity, rho), source: 'Built-in screening value', screening: true);
  }
  final m = (0.7 + 0.3 * velocityRatio).clamp(0.7, 1.3).toDouble();
  final c = (tee ? 1.0 : 0.5) * m;
  return FittingLoss(label: '$name – branch', c: c, pa: c * velocityPressure(velocity, rho), source: 'Built-in screening value', screening: true);
}
