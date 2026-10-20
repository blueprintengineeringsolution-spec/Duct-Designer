import 'dart:math' as math;

double log10(num x) => math.log(x) / math.ln10;

enum DuctMaterial { galvanized, flexible, aluminum, pirPanel }

class MaterialSpec {
  final String label;
  final double roughnessM;
  final double frictionMultiplier;
  const MaterialSpec(this.label, this.roughnessM, [this.frictionMultiplier = 1.0]);
}

/// Absolute roughness (m), typical ASHRAE-range values.
const Map<DuctMaterial, MaterialSpec> materialLibrary = {
  DuctMaterial.galvanized: MaterialSpec('Galvanized steel', 0.00009),
  DuctMaterial.aluminum: MaterialSpec('Aluminum', 0.00004),
  DuctMaterial.pirPanel: MaterialSpec('PIR/PUR panel', 0.00006),
  DuctMaterial.flexible: MaterialSpec('Flexible duct', 0.0030),
};

class Air {
  final double density; // kg/m3
  final double dynamicViscosity; // Pa.s
  const Air({this.density = 1.204, this.dynamicViscosity = 1.825e-5});
  double get kinematicViscosity => dynamicViscosity / density;
}

/// SI-internal unit helpers (UI converts at the edges).
class Units {
  static const cfmToM3s = 0.00047194745;
  static const ftToM = 0.3048;
  static const inWgToPa = 249.0889;
  static const fpmToMs = 0.00508;
  static double cfm(double v) => v * cfmToM3s;
  static double toCfm(double m3s) => m3s / cfmToM3s;
  static double inWgPer100ftToPaPerM(double v) => v * inWgToPa / (100 * ftToM);
}

double roundArea(double d) => math.pi * d * d / 4;
double velocityPressure(double v, double rho) => 0.5 * rho * v * v;
double reynolds(double v, double d, double nu) => v * d / nu;

/// Darcy friction factor: laminar 64/Re, else Colebrook (Swamee-Jain seeded).
double frictionFactor(double re, double relRough) {
  if (re < 2300) return 64 / math.max(re, 1.0);
  double f = 0.25 /
      math.pow(log10(relRough / 3.7 + 5.74 / math.pow(re, 0.9)), 2).toDouble();
  for (var i = 0; i < 30; i++) {
    final rhs = -2 * log10(relRough / 3.7 + 2.51 / (re * math.sqrt(f)));
    final next = 1 / (rhs * rhs);
    if ((next - f).abs() < 1e-10) {
      f = next;
      break;
    }
    f = next;
  }
  return f;
}

/// Friction loss rate (Pa/m) in a round duct of diameter [diameter] (m).
/// [flexSlack] (0..0.3) approximates convolution/compression penalty for flex duct.
double frictionRate({
  required double flow,
  required double diameter,
  required DuctMaterial material,
  Air air = const Air(),
  double flexSlack = 0,
}) {
  final spec = materialLibrary[material]!;
  final v = flow / roundArea(diameter);
  final re = reynolds(v, diameter, air.kinematicViscosity);
  final f = frictionFactor(re, spec.roughnessM / diameter);
  var mult = spec.frictionMultiplier;
  if (material == DuctMaterial.flexible) mult *= 1 + 6 * flexSlack;
  return mult * f * (air.density / 2) * v * v / diameter;
}

/// Bisection for a function decreasing in x with g(lo) > 0 > g(hi).
double _bisect(double Function(double) g, double lo, double hi, {int iters = 80}) {
  for (var i = 0; i < iters; i++) {
    final mid = (lo + hi) / 2;
    if (g(mid) > 0) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Equal friction: round diameter (m) giving [targetPaPerM] at [flow] (m3/s).
double sizeRoundForFriction({
  required double flow,
  required double targetPaPerM,
  DuctMaterial material = DuctMaterial.galvanized,
  Air air = const Air(),
  double flexSlack = 0,
}) {
  return _bisect(
    (d) =>
        frictionRate(flow: flow, diameter: d, material: material, air: air, flexSlack: flexSlack) -
        targetPaPerM,
    0.03,
    3.0,
  );
}

/// Velocity reduction: round diameter (m) for a target velocity (m/s).
double sizeRoundForVelocity(double flow, double velocity) =>
    math.sqrt(4 * flow / (math.pi * velocity));

/// Static regain: downstream round diameter where regain offsets section friction.
/// [v1] upstream velocity, [lengthM] section length, [r] regain factor (~0.75).
double sizeRoundStaticRegain({
  required double flow,
  required double v1,
  required double lengthM,
  double r = 0.75,
  DuctMaterial material = DuctMaterial.galvanized,
  Air air = const Air(),
}) {
  double g(double v2) {
    final d = sizeRoundForVelocity(flow, v2);
    final fric = lengthM * frictionRate(flow: flow, diameter: d, material: material, air: air);
    return r * (velocityPressure(v1, air.density) - velocityPressure(v2, air.density)) - fric;
  }

  const lo = 0.5;
  if (g(lo) <= 0) return sizeRoundForVelocity(flow, lo);
  if (g(v1) >= 0) return sizeRoundForVelocity(flow, v1);
  return sizeRoundForVelocity(flow, _bisect(g, lo, v1));
}

/// Huebscher equivalent round diameter for friction (m).
double equivalentDiameter(double a, double b) =>
    1.30 * math.pow(a * b, 0.625) / math.pow(a + b, 0.25);

/// Width (m) giving equivalent diameter [de] at fixed [height] (m).
double rectWidthFor(double de, double height) =>
    _bisect((b) => de - equivalentDiameter(height, b), 0.02, 10.0);

double aspectRatio(double a, double b) => math.max(a, b) / math.min(a, b);

/// Fitting dynamic loss: C * Pv.
double dynamicLoss(double c, double v, double rho) => c * velocityPressure(v, rho);
