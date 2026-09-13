import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/pets/pets_screen.dart';
import 'package:cortex/features/space/space_screen.dart';
import 'package:cortex/features/fitness/trends.dart';

Entry reading(
  String id,
  String pet,
  String date,
  double kg, {
  String? at,
  String? note,
}) => Entry(id, 'pet_weight', {
  'petId': pet,
  'date': date,
  'kg': kg,
  'recordedAt': ?at,
  'notes': ?note,
});

void main() {
  test(
    'Pets stay separate, preserve same-day readings and reject malformed dates',
    () {
      final entries = [
        Entry('owner', 'weight', {'date': '2026-09-13', 'kg': 95.3}),
        reading(
          'cookie-pm',
          'cookie',
          '2026-09-13',
          4.3,
          at: '2026-09-13T20:00:00+08:00',
        ),
        reading(
          'cookie-am',
          'cookie',
          '2026-09-13',
          4.25,
          at: '2026-09-13T08:00:00+08:00',
        ),
        reading('wanwan', 'wanwan', '2026-09-13', 6.85),
        reading('bad-date', 'cookie', '2026-02-30', 4),
        reading('zero', 'cookie', '2026-09-13', 0),
      ];
      expect(petWeightPoints(entries, 'cookie').map((p) => p.id), [
        'cookie-am',
        'cookie-pm',
      ]);
      expect(petWeightPoints(entries, 'wanwan').single.value, 6.85);
      expect(healthPoints(entries, TrendMetric.weight).single.id, 'owner');
    },
  );

  testWidgets(
    'My space opens Pets, empty states and chat recording on a narrow iPhone',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = CortexModel();
      String? prompt;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpaceScreen(
              model: model,
              onChat: (value, {bool photo = false}) => prompt = value,
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Pets'));
      await tester.tap(find.text('Pets'));
      await tester.pumpAndSettle();
      expect(find.text('Cookie & Wanwan'), findsOneWidget);
      expect(find.text('No readings for Cookie yet.'), findsOneWidget);
      await tester.ensureVisible(find.text('No readings for Wanwan yet.'));
      expect(find.text('No readings for Wanwan yet.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Record Wanwan’s weight'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Wanwan’s weight'));
      await tester.pumpAndSettle();
      expect(prompt, 'Wanwan’s weight is ');
      expect(find.byType(PetsScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'Pet charts show small changes precisely and update from new records',
    (tester) async {
      final model = CortexModel();
      final today = day();
      model.entries = [
        reading('c1', 'cookie', today, 4.25),
        reading('c2', 'cookie', today, 4.285, note: '医院；婴儿秤'),
        reading('w1', 'wanwan', today, 6.85),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: PetsScreen(model: model, onChat: (_, {bool photo = false}) {}),
        ),
      );
      expect(find.text('4.285'), findsOneWidget);
      expect(find.text('医院；婴儿秤'), findsOneWidget);
      expect(find.text('+0.035 kg in this period'), findsOneWidget);
      expect(find.text('2 of 2 readings'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous cookie reading'));
      await tester.pump();
      expect(find.text('4.250'), findsOneWidget);
      expect(find.text('医院；婴儿秤'), findsNothing);
      model.entries.add(reading('c3', 'cookie', today, 4.29));
      model.notifyListeners();
      await tester.pump();
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      expect(find.text('4.290'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Wanwan'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('6.850'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
