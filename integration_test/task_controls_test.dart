import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/time/time_screen.dart';

// Run on a disposable simulator. This fixture never connects to production,
// registers notifications or changes the owner's calendar/routine records.
class TaskControlsApi extends CortexApi {
  final writes = <Map<String, dynamic>>[];
  final rows = <Map<String, dynamic>>[];
  bool routineDone = false;
  final records = [
    {
      'id': 'walk',
      'kind': 'routine',
      'data': {
        'title': 'Daily walk',
        'minutes': 30,
        'kind': 'movement',
        'enabled': true,
      },
    },
    {
      'id': 'dose',
      'kind': 'routine',
      'data': {
        'title': 'Morning medication',
        'minutes': 2,
        'medical': true,
        'enabled': true,
      },
    },
    {
      'id': 'sweep',
      'kind': 'routine',
      'data': {'title': 'Sweep the floor', 'minutes': 15, 'enabled': true},
    },
  ];
  Map<String, dynamic> get routineStates => {
    for (final r in records)
      r['id'] as String: {
        'date': day(),
        'due': true,
        'done': r['id'] == 'walk' && routineDone,
      },
  };
  @override
  Future<dynamic> call(String method, String path, [Object? body]) async {
    if (method != 'GET') writes.add({'path': path, 'body': body});
    if (path == '/v1/focus/actions') {
      final input = body as Map;
      final row = rows.firstWhere(
        (f) =>
            f['calendarKey'] == input['calendarKey'] || f['id'] == input['id'],
      );
      row['status'] = input['action'] == 'begin' ? 'active' : 'done';
      if (row['routineId'] == 'walk' && row['status'] == 'done') {
        routineDone = true;
      }
      return {'focus': row};
    }
    if (path.startsWith('/v1/focus/planned')) return {'tasks': rows};
    if (path.startsWith('/v1/snapshot')) {
      return {
        'records': records,
        'routineStates': routineStates,
        'messages': [],
        'sessions': [],
        'chat': {},
      };
    }
    throw StateError('Unexpected API request: $method $path');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Early actions and one shared routine checklist on iPhone', (
    tester,
  ) async {
    final api = TaskControlsApi();
    final now = DateTime.now();
    for (final (id, title) in [
      ('work', 'Prepare the presentation'),
      ('walk', 'Daily walk'),
    ]) {
      final start = now.add(const Duration(hours: 4));
      api.rows.add({
        'id': id,
        'calendarKey': 'google:fixture\n$id',
        'revision': 0,
        'title': title,
        'routineId': id == 'walk' ? id : '',
        'status': 'pending',
        'scheduledStart': start.toUtc().toIso8601String(),
        'activateAt': start
            .subtract(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'plannedEnd': start
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
      });
    }
    final model = CortexModel(api: api);
    await model.refresh();
    await model.taskFocus.refreshPlanned();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F4339)),
          scaffoldBackgroundColor: const Color(0xFFF7F9F2),
        ),
        home: TimeScreen(
          model: model,
          onChat: (_, {photo = false}) => fail('Task action opened chat'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Prepare the presentation'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('planned-for-today');
    await tester.tap(find.text('Start early').first);
    await tester.pumpAndSettle();
    expect(api.writes.single['path'], '/v1/focus/actions');
    expect((api.writes.single['body'] as Map)['action'], 'begin');
    await tester.ensureVisible(find.text('Completed!').first);
    await tester.tap(find.text('Completed!').first);
    await tester.pumpAndSettle();
    expect(find.text('Prepare the presentation'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    // The second occurrence can be completed without starting first.
    await tester.ensureVisible(find.text('Completed!').first);
    await tester.tap(find.text('Completed!').first);
    await tester.pumpAndSettle();
    expect(api.routineDone, true);
    await tester.ensureVisible(find.text('Daily routines'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('daily-routines');
    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('walk')),
    );
    expect(checkbox.value, true);
    expect(find.text('Fitness routines'), findsNothing);
    expect(find.text('Sweep the floor'), findsOneWidget);
    expect(find.text('Morning medication'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
