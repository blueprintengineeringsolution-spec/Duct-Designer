import 'package:hvac_engine/hvac_engine.dart';

/// Display formatting and step sizes for SI / Imperial. Values are always stored in SI.
class Fmt {
  final bool imperial;
  const Fmt(this.imperial);

  static const _cfm = 0.00047194745;
  static const _ft = 0.3048;
  static const _in = 0.0254;
  static const _inWg = 249.0889;
  static const _fpm = 0.00508;

  String _n(double v) => (v - v.roundToDouble()).abs() < 0.05 ? '${v.round()}' : v.toStringAsFixed(1);

  String flow(double m3s) => imperial ? '${(m3s / _cfm).round()} cfm' : '${(m3s * 1000).round()} L/s';
  String velocity(double v) => imperial ? '${(v / _fpm).round()} fpm' : '${v.toStringAsFixed(1)} m/s';
  String area(double m2) => imperial ? '${(m2 * 10.7639).toStringAsFixed(1)} ft²' : '${m2.toStringAsFixed(1)} m²';
  String length(double m) => imperial ? '${(m / _ft).toStringAsFixed(1)} ft' : '${m.toStringAsFixed(1)} m';
  String dim(double m) => imperial ? '${_n(m / _in)} in' : '${(m * 1000).round()} mm';
  String pressure(double pa) => imperial ? '${(pa / _inWg).toStringAsFixed(3)} in.wg' : '${pa.toStringAsFixed(1)} Pa';
  String friction(double paPerM) => imperial
      ? '${(paPerM / _inWg * 100 * _ft).toStringAsFixed(3)} in.wg/100ft'
      : '${paPerM.toStringAsFixed(2)} Pa/m';

  String size(DuctSize s) {
    if (s.shape == DuctShape.round) return 'Ø${imperial ? _n(s.diameterM! / _in) : (s.diameterM! * 1000).round()} ${imperial ? 'in' : 'mm'}';
    final w = imperial ? _n(s.widthM! / _in) : '${(s.widthM! * 1000).round()}';
    final h = imperial ? _n(s.heightM! / _in) : '${(s.heightM! * 1000).round()}';
    return '$w×$h ${imperial ? 'in' : 'mm'}';
  }

  double get flowStep => imperial ? 25 * _cfm : 0.01;
  double get lengthStep => imperial ? _ft : 0.5;
  double get dimStep => imperial ? 2 * _in : 0.05;
  double get frictionStep => imperial ? 0.01 * _inWg / (100 * _ft) : 0.05;
  double get velocityStep => imperial ? 100 * _fpm : 0.5;

  @override
  bool operator ==(Object other) => other is Fmt && other.imperial == imperial;
  @override
  int get hashCode => imperial.hashCode;
}
