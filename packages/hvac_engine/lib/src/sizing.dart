import 'dart:math' as math;
import 'duct_math.dart';

enum DuctShape { round, rectangular }

/// A concrete duct size (metres). Round uses [diameterM]; rectangular uses width x height.
class DuctSize {
  final DuctShape shape;
  final double? diameterM, widthM, heightM;
  const DuctSize.round(double d)
      : shape = DuctShape.round,
        diameterM = d,
        widthM = null,
        heightM = null;
  const DuctSize.rect(double w, double h)
      : shape = DuctShape.rectangular,
        diameterM = null,
        widthM = w,
        heightM = h;

  double get area => shape == DuctShape.round ? roundArea(diameterM!) : widthM! * heightM!;
  double get equivalentDiameterM =>
      shape == DuctShape.round ? diameterM! : equivalentDiameter(widthM!, heightM!);
  double? get aspect => shape == DuctShape.round ? null : aspectRatio(widthM!, heightM!);

  /// mm label, e.g. "Ø400" or "600×150".
  String get label => shape == DuctShape.round
      ? 'Ø${(diameterM! * 1000).round()}'
      : '${(widthM! * 1000).round()}×${(heightM! * 1000).round()}';
}

/// Preferred/stock sizes. Rectangular sizes snap to a step (e.g. 50 mm or 2 in).
class SizeCatalog {
  final List<double> roundM;
  final double rectStepM, rectMinM, rectMaxM;
  const SizeCatalog({
    required this.roundM,
    required this.rectStepM,
    required this.rectMinM,
    required this.rectMaxM,
  });

  /// EN 1506 / ISO preferred round sizes; rectangular in 50 mm steps.
  static const metric = SizeCatalog(
    roundM: [0.063, 0.08, 0.1, 0.125, 0.16, 0.2, 0.25, 0.315, 0.4, 0.5, 0.63, 0.8, 1.0, 1.25],
    rectStepM: 0.05,
    rectMinM: 0.1,
    rectMaxM: 2.0,
  );

  /// Typical US sizes: round in common inch steps; rectangular in 2 in steps.
  static final imperial = SizeCatalog(
    roundM: [
      for (final i in [4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40, 42, 48, 54, 60])
        i * 0.0254
    ],
    rectStepM: 2 * 0.0254,
    rectMinM: 6 * 0.0254,
    rectMaxM: 80 * 0.0254,
  );

  double snapUp(double x) => ((x / rectStepM - 1e-6).ceil() * rectStepM * 1e4).round() / 1e4;
}

class SizeLimits {
  final double maxVelocity, maxAspect;
  final double? maxHeightM; // ceiling-void constraint for rectangular
  const SizeLimits({this.maxVelocity = 10, this.maxAspect = 4, this.maxHeightM});
}

class SizeOption {
  final DuctSize size;
  final double velocity, frictionPaPerM;
  final bool recommended, undersized, overVelocity, overAspect;
  const SizeOption({
    required this.size,
    required this.velocity,
    required this.frictionPaPerM,
    required this.recommended,
    required this.undersized,
    required this.overVelocity,
    required this.overAspect,
  });
  bool get withinLimits => !undersized && !overVelocity && !overAspect;
}

SizeOption _evaluate(DuctSize size, double flow, double requiredDe, DuctMaterial m, Air air,
    double flexSlack, SizeLimits lim, bool recommended) {
  final de = size.equivalentDiameterM;
  final v = flow / size.area;
  final asp = size.aspect;
  return SizeOption(
    size: size,
    velocity: v,
    frictionPaPerM: frictionRate(flow: flow, diameter: de, material: m, air: air, flexSlack: flexSlack),
    recommended: recommended,
    undersized: de < requiredDe - 1e-9,
    overVelocity: v > lim.maxVelocity,
    overAspect: asp != null && asp > lim.maxAspect + 1e-9,
  );
}

/// Round options around [requiredDe]: the next standard size up is recommended;
/// one size down (flagged undersized) and one up are offered for comparison.
List<SizeOption> recommendRound({
  required double requiredDe,
  required double flow,
  SizeCatalog catalog = SizeCatalog.metric,
  DuctMaterial material = DuctMaterial.galvanized,
  Air air = const Air(),
  double flexSlack = 0,
  SizeLimits limits = const SizeLimits(),
}) {
  final s = catalog.roundM;
  var i = s.indexWhere((d) => d >= requiredDe - 1e-9);
  if (i < 0) i = s.length - 1;
  return [
    for (final k in [i - 1, i, i + 1])
      if (k >= 0 && k < s.length)
        _evaluate(DuctSize.round(s[k]), flow, requiredDe, material, air, flexSlack, limits, k == i),
  ];
}

/// Rectangular options. With [fixedHeightM], widths snap up to the catalog step.
/// Without it, heights are scanned (up to limits.maxHeightM) and the lowest-perimeter
/// sizes within the aspect limit are offered; the first is recommended.
List<SizeOption> recommendRect({
  required double requiredDe,
  required double flow,
  SizeCatalog catalog = SizeCatalog.metric,
  DuctMaterial material = DuctMaterial.galvanized,
  Air air = const Air(),
  double flexSlack = 0,
  SizeLimits limits = const SizeLimits(),
  double? fixedHeightM,
}) {
  SizeOption ev(DuctSize z, bool rec) =>
      _evaluate(z, flow, requiredDe, material, air, flexSlack, limits, rec);

  if (fixedHeightM != null) {
    final h = fixedHeightM;
    final w = math.max(catalog.snapUp(rectWidthFor(requiredDe, h)), catalog.rectMinM);
    final step = catalog.rectStepM;
    final ws = <double>[
      if (w - step >= catalog.rectMinM) ((w - step) * 1e4).round() / 1e4,
      w,
      ((w + step) * 1e4).round() / 1e4,
    ];
    return [for (final x in ws) ev(DuctSize.rect(x, h), x == w)];
  }

  final hMax = math.min(limits.maxHeightM ?? catalog.rectMaxM, catalog.rectMaxM);
  final cands = <DuctSize>[];
  for (var k = 0;; k++) {
    final h = ((catalog.rectMinM + k * catalog.rectStepM) * 1e4).round() / 1e4;
    if (h > hMax + 1e-9) break;
    final w = catalog.snapUp(rectWidthFor(requiredDe, h));
    if (w < h || w > catalog.rectMaxM) continue;
    if (w / h > limits.maxAspect + 1e-9) continue;
    cands.add(DuctSize.rect(w, h));
  }
  if (cands.isEmpty) {
    final h = hMax;
    return [ev(DuctSize.rect(catalog.snapUp(rectWidthFor(requiredDe, h)), h), true)];
  }
  cands.sort((a, b) => (a.widthM! + a.heightM!).compareTo(b.widthM! + b.heightM!));
  return [for (var i = 0; i < math.min(3, cands.length); i++) ev(cands[i], i == 0)];
}
