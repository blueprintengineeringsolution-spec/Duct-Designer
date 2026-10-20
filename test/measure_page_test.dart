import 'package:ductletor_pro/core/fmt.dart';
import 'package:ductletor_pro/features/measure/measure_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hvac_engine/hvac_engine.dart';

void main() {
  late void Function(Point3) tap;
  late void Function(String) unavailable;
  double? result;
  var returned = false;

  Widget app({Fmt fmt = const Fmt(false)}) => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                child: const Text('open'),
                onPressed: () async {
                  result = await Navigator.of(context).push<double>(MaterialPageRoute(
                    builder: (_) => MeasurePage(
                      title: 'Trunk',
                      currentLengthM: 10,
                      fmt: fmt,
                      arBuilder: (c, onPoint, onUnavailable) {
                        tap = onPoint;
                        unavailable = onUnavailable;
                        return const SizedBox.expand();
                      },
                    ),
                  ));
                  returned = true;
                },
              ),
            ),
          ),
        ),
      );

  setUp(() {
    result = null;
    returned = false;
  });

  testWidgets('AR taps make segments; confirming returns the rounded total', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    tap(const Point3(0, 0, 0)); // start
    tap(const Point3(3.02, 0, 0));
    await t.pump();
    expect(find.text('Segment 1'), findsOneWidget);
    expect(find.text('Use 3.0 m'), findsOneWidget);
    await t.tap(find.text('Use 3.0 m'));
    await t.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, 3.0);
  });

  testWidgets('tapping the same spot twice adds no segment; undo removes the last one', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    tap(const Point3(0, 0, 0));
    tap(const Point3(0, 0, 0));
    await t.pump();
    expect(find.text('No segments yet.'), findsOneWidget);
    tap(const Point3(2, 0, 0));
    tap(const Point3(2, 1, 0));
    await t.pump();
    expect(find.text('Segment 2'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pump();
    expect(find.text('Segment 2'), findsNothing);
    expect(find.text('Total 2.0 m'), findsOneWidget);
  });

  testWidgets('typed readings are summed in tape mode', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tape'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '2.5');
    await t.tap(find.text('Add'));
    await t.pump();
    await t.enterText(find.byType(TextField), '1,5');
    await t.tap(find.text('Add'));
    await t.pump();
    expect(find.text('Total 4.0 m'), findsOneWidget);
  });

  testWidgets('imperial readings are entered in feet and returned in metres', (t) async {
    await t.pumpWidget(app(fmt: const Fmt(true)));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tape'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '10');
    await t.tap(find.text('Add'));
    await t.pump();
    await t.tap(find.textContaining('Use '));
    await t.pumpAndSettle();
    expect(result, closeTo(3.048, 0.05)); // 10 ft rounded to 3 in steps
  });

  testWidgets('AR unavailable falls back to tape mode with a message', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    unavailable('AR did not start');
    await t.pump();
    expect(find.text('AR did not start'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('cancelling returns nothing', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
  });
}
