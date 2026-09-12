import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/cortex.dart';
import 'package:cortex/fitness_trends.dart';
import 'package:cortex/space.dart';

Entry weight(String id, String date, double kg) =>
    Entry(id, 'weight', {'date': date, 'kg': kg});

void main() {
  test(
    'Latest same-day weight follows record time rather than identifier order',
    () {
      final points = healthPoints([
        Entry.fromJson({
          'id': 'z-old',
          'kind': 'weight',
          'data': {'date': '2026-05-20', 'kg': 93},
          'updated': '2026-05-20T08:00:00Z',
        }),
        Entry.fromJson({
          'id': 'a-new',
          'kind': 'weight',
          'data': {'date': '2026-05-20', 'kg': 92},
          'updated': '2026-05-20T10:00:00Z',
        }),
      ], TrendMetric.weight);
      expect(points.single.id, 'a-new');
    },
  );

  test(
    'Date ranges use calendar days, exclude future readings, and keep sparse averages honest',
    () {
      final points = healthPoints([
        weight('old', '2026-05-01', 100),
        weight('recent', '2026-05-20', 90),
        weight('latest', '2026-05-22', 92),
        weight('future', '2026-05-30', 80),
      ], TrendMetric.weight);
      final selected = pointsInRange(points, 7, DateTime(2026, 5, 22));
      expect(selected.map((p) => p.id), ['recent', 'latest']);
      expect(recentWeightAverage(selected), 91);
      expect(pointsInRange(points, null, DateTime(2026, 5, 22)).length, 3);
    },
  );
  test(
    'Same-day blood pressure pairs remain separate and malformed readings are ignored',
    () {
      final points = healthPoints([
        Entry('first', 'bp', {
          'date': '2026-05-20',
          'systolic': 123,
          'diastolic': 78,
        }),
        Entry('second', 'bp', {
          'date': '2026-05-20',
          'systolic': 117,
          'diastolic': 75,
        }),
        Entry('invalid', 'bp', {
          'date': '2026-05-20',
          'systolic': 70,
          'diastolic': 100,
        }),
      ], TrendMetric.bp);
      expect(points.length, 2);
      expect(points[0].second, 78);
      expect(points[1].second, 75);
    },
  );
  test('Glucose retains meal context and converts the explicit mg/dL unit', () {
    final points = healthPoints([
      Entry('fasting', 'glucose', {
        'date': '2026-05-20',
        'mgdl': 90.091,
        'context': 'fasting',
      }),
      Entry('before', 'glucose', {
        'date': '2026-05-20',
        'mgdl': 108.1092,
        'context': 'beforeMeal',
      }),
    ], TrendMetric.glucose);
    expect(
      points.firstWhere((p) => p.id == 'fasting').value / glucoseFactor,
      closeTo(5, 0.00001),
    );
    expect(points.firstWhere((p) => p.id == 'before').context, 'beforeMeal');
  });
  testWidgets(
    'Trends render empty, single and paired readings on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = CortexModel();
      final date = day();
      model.entries = [
        weight('w', date, 90),
        Entry('g', 'glucose', {
          'date': date,
          'mgdl': 90.091,
          'context': 'fasting',
        }),
        Entry('b1', 'bp', {'date': date, 'systolic': 123, 'diastolic': 78}),
        Entry('b2', 'bp', {'date': date, 'systolic': 117, 'diastolic': 75}),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: FitnessScreen(
            model: model,
            onChat: (String prompt, {bool photo = false}) {},
          ),
        ),
      );
      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();
      expect(find.text('See the bigger picture.'), findsOneWidget);
      expect(find.text('90.0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Blood glucose'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('5.0'), findsOneWidget);
      await tester.ensureVisible(find.text('mg/dL'));
      await tester.tap(find.text('mg/dL'));
      await tester.pumpAndSettle();
      expect(find.text('90'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Blood pressure'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('117/75'), findsOneWidget);
      await tester.ensureVisible(
        find.byTooltip('Previous blood pressure reading'),
      );
      await tester.tap(find.byTooltip('Previous blood pressure reading'));
      await tester.pumpAndSettle();
      expect(find.text('123/78'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(body: FitnessTrends(model: CortexModel())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No weight readings in this period.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
