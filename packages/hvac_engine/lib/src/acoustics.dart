import 'duct_math.dart';

enum FittingKind { none, elbow, transition, tee, damper, terminal }

/// Turbulence penalty (dB) per fitting. Screening values, not manufacturer data.
const Map<FittingKind, double> fittingNoisePenaltyDb = {
  FittingKind.none: 0,
  FittingKind.transition: 3,
  FittingKind.elbow: 4,
  FittingKind.terminal: 5,
  FittingKind.tee: 6,
  FittingKind.damper: 8,
};

/// Screening estimate of flow-generated sound power (dB): velocity-driven.
/// Replace with manufacturer/ASHRAE octave-band data for final design.
double flowNoiseLw({required double velocity, required double areaM2, FittingKind fitting = FittingKind.none}) {
  final v = velocity < 0.5 ? 0.5 : velocity;
  return 10 + 50 * log10(v) + 10 * log10(areaM2) + (fittingNoisePenaltyDb[fitting] ?? 0);
}

/// NC estimate = Lw minus a configurable room/end attenuation.
double estimateNc(double lw, {double attenuationDb = 15}) => lw - attenuationDb;
