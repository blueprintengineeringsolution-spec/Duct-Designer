import 'package:hvac_engine/hvac_engine.dart';
import 'package:test/test.dart';

void main() {
  test('distance between points', () {
    expect(const Point3(0, 0, 0).distanceTo(const Point3(3, 4, 0)), 5);
    expect(const Point3(1, 1, 1).distanceTo(const Point3(1, 1, 1)), 0);
  });

  test('chain total adds segments; undo removes the last', () {
    var r = const LengthRun().add(2.5).add(1.5);
    expect(r.totalM, 4);
    r = r.undo();
    expect(r.totalM, 2.5);
    expect(const LengthRun().undo().totalM, 0);
  });

  test('unusable segments are ignored', () {
    final r = const LengthRun().add(0.001).add(-2).add(double.nan).add(double.infinity).add(500).add(1.2);
    expect(r.segmentsM, [1.2]);
  });

  test('error estimate: AR is looser than a tape', () {
    final r = const LengthRun().add(10);
    expect(r.estimatedErrorM(fromAr: true), greaterThan(r.estimatedErrorM(fromAr: false)));
    expect(r.estimatedErrorM(fromAr: false), closeTo(0.02, 1e-9));
  });

  test('warnings', () {
    expect(const LengthRun().warnings(fromAr: true), isEmpty);
    expect(const LengthRun().add(0.03).warnings(fromAr: true), isNotEmpty);
    expect(const LengthRun().add(0.03).warnings(fromAr: false), isEmpty);
    expect(const LengthRun().add(12).warnings(fromAr: true).length, 1);
    expect(const LengthRun().add(12).warnings(fromAr: false), isEmpty);
    expect(const LengthRun().add(20).add(20).warnings(fromAr: false).length, 1);
  });

  test('rounding to 5 cm or 3 in', () {
    expect(roundLength(3.02), 3.0);
    expect(roundLength(3.03), 3.05);
    expect(roundLength(0.001), 0.05);
    expect(roundLength(-1), 0);
    expect(roundLength(1.0, imperial: true), closeTo(0.9906, 1e-9)); // 13 x 3 in
  });
}
