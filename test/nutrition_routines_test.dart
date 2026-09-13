import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/fitness/nutrition.dart';
import 'package:cortex/features/time/daily_routines.dart';
import 'package:cortex/features/time/todos.dart';

class RoutineApi extends CortexApi {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    calls.add({'method': method, 'path': path, 'data': data});
    return {'saved': true};
  }
}

class RoutineModel extends CortexModel {
  RoutineModel(CortexApi api) : super(api: api);
  @override
  Future<void> refresh() async {
    routineStates['weight'] = {
      'date': day(),
      'due': true,
      'done': true,
      'source': 'checkbox',
    };
    notifyListeners();
  }
}

void main() {
  test('Daily nutrients distinguish estimates, unknowns and added sugar', () {
    final meals = [
      Entry('old', 'meal', {'kcal': 100, 'sugar_g': 9}),
      Entry('new', 'meal', {
        'nutrients': {'kcal': 200, 'protein_g': 12, 'added_sugar_g': 0},
        'estimated': ['protein_g'],
      }),
    ];
    final sum = totalNutrition(meals);
    expect(sum['kcal']!.value, 300);
    expect(sum['kcal']!.partial, isFalse);
    expect(sum['protein_g']!.value, 12);
    expect(sum['protein_g']!.partial, isTrue);
    expect(sum['protein_g']!.estimated, isTrue);
    expect(sum['added_sugar_g']!.value, 0);
    expect(sum['added_sugar_g']!.known, 1);
    expect(sum['fiber_g']!.known, 0);
    expect(
      nutritionFlags({'sodium_mg': 460, 'added_sugar_g': 10, 'fiber_g': 5.6}),
      ['High sodium', 'High added sugar', 'High fibre'],
    );
    expect(nutritionFlags({'sugar_g': 30}), isEmpty);
  });
  test(
    'Today includes elapsed deadlines today, but not yesterday or tomorrow',
    () {
      final now = DateTime(2026, 9, 13, 23, 59);
      for (final value in ['2026-09-13', '2026-09-13T08:00']) {
        expect(
          todoIsDueToday(Entry('id', 'task', {'deadline': value}), now),
          isTrue,
        );
      }
      for (final value in ['2026-09-12', '2026-09-14', 'invalid']) {
        expect(
          todoIsDueToday(Entry('id', 'task', {'deadline': value}), now),
          isFalse,
        );
      }
      final instant = DateTime(2026, 9, 13, 1).toUtc().toIso8601String();
      expect(
        todoIsDueToday(Entry('id', 'task', {'deadline': instant}), now),
        isTrue,
      );
    },
  );
  testWidgets('Due today groups do not duplicate other deadlines', (
    tester,
  ) async {
    final now = DateTime.now();
    final model = CortexModel()
      ..entries = [
        Entry('a', 'task', {'title': 'Today item', 'deadline': day(now)}),
        Entry('b', 'task', {
          'title': 'Later item',
          'deadline': day(DateTime(now.year, now.month, now.day + 1)),
        }),
        Entry('c', 'task', {
          'title': 'Overdue item',
          'deadline': day(DateTime(now.year, now.month, now.day - 1)),
        }),
      ];
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodoList(model: model, onChat: (_, {photo = false}) {}),
          ),
        ),
      ),
    );
    expect(find.text('Today item'), findsOneWidget);
    expect(find.text('Later item'), findsOneWidget);
    expect(find.text('Overdue item'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Due today')).dy,
      lessThan(tester.getTopLeft(find.text('Today item')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Today item')).dy,
      lessThan(tester.getTopLeft(find.text('Other deadlines')).dy),
    );
  });
  testWidgets('Routine checkbox saves local date and keeps off-day disabled', (
    tester,
  ) async {
    final api = RoutineApi();
    final model = RoutineModel(api)
      ..entries = [
        Entry('weight', 'routine', {'title': 'Weigh in', 'medical': true}),
        Entry('next', 'routine', {'title': 'Next dose', 'medical': true}),
      ]
      ..routineStates = {
        'weight': {'date': day(), 'due': true, 'done': false},
        'next': {'date': day(), 'due': false, 'done': false},
      };
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: model,
              builder: (_, _) => DailyRoutines(model: model),
            ),
          ),
        ),
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          native,
          (_) async => {'permission': 'authorized'},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, null),
    );
    await tester.tap(find.text('Weigh in'));
    await tester.pumpAndSettle();
    expect(api.calls.single['path'], '/v1/routines/complete');
    expect(api.calls.single['data'], {
      'routineId': 'weight',
      'date': day(),
      'done': true,
    });
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('weight')))
          .value,
      isTrue,
    );
    await tester.tap(find.text('Other days'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('next')))
          .onChanged,
      isNull,
    );
  });
  testWidgets(
    'Food facts fit an iPhone and expose nutrient details without a photo',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FoodFactsTile(
                  library: true,
                  entry: Entry('food', 'food', {
                    'name': 'Oats with milk and berries',
                    'category': 'grain',
                    'portion': {'amount': 100, 'unit': 'g'},
                    'nutrients': {
                      'kcal': 150,
                      'protein_g': 8,
                      'added_sugar_g': 0,
                      'fiber_g': 6,
                    },
                    'estimated': ['kcal'],
                  }),
                  onChat: (_, {photo = false}) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Oats with milk and berries'));
      await tester.pumpAndSettle();
      expect(find.text('Added sugar'), findsOneWidget);
      expect(find.text('Per 100 g'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
