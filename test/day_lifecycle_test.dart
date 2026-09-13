import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/time/time_screen.dart';
import 'package:cortex/features/time/task_focus.dart';

class DayApi extends CortexApi {
  final writes = <Map<String, dynamic>>[];
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    if (method != 'GET') {
      writes.add({'method': method, 'path': path, 'data': data});
    }
    return {'records': [], 'messages': [], 'sessions': [], 'chat': {}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Wake check-in sends reported energy and local offset to chat planning',
    (tester) async {
      final api = DayApi();
      final model = CortexModel(api: api);
      bool? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  sent = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => CheckIn(model: model),
                  );
                },
                child: const Text('Wake up'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Wake up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Low'));
      await tester.tap(find.text('Arrange my day'));
      await tester.pumpAndSettle();
      expect(sent, true);
      expect(api.writes, hasLength(1));
      expect(api.writes.single['path'], '/v1/plan');
      final data = api.writes.single['data'] as Map;
      expect(data['energy'], 'low');
      expect(data['timezoneOffset'], DateTime.now().timeZoneOffset.inMinutes);
      expect(data['date'], day());
      model.dispose();
    },
  );

  testWidgets(
    'Future calendar task has early Start and Done using APIs without chat',
    (tester) async {
      final api = DayApi();
      final model = CortexModel(api: api);
      final now = DateTime.now();
      final future = now.add(const Duration(hours: 6));
      final item = <String, dynamic>{
        'id': 'future-calendar',
        'calendarKey': 'google:personal\nevent-2',
        'revision': 0,
        'title': 'Later task',
        'status': 'pending',
        'scheduledStart': future.toUtc().toIso8601String(),
        'activateAt': future
            .subtract(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'plannedEnd': future
            .add(const Duration(minutes: 25))
            .toUtc()
            .toIso8601String(),
      };
      model.taskFocus.plannedTasks = [item];
      model.taskFocus.plannedDate = day(now);
      expect(model.taskFocus.visibleTasks, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FocusPanel(
                model: model,
                items: [item],
                planned: true,
                showHeading: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Start early'), findsOneWidget);
      expect(find.text('Completed!'), findsOneWidget);
      await tester.tap(find.text('Start early'));
      await tester.pumpAndSettle();
      expect(api.writes.single['path'], '/v1/focus/actions');
      expect((api.writes.single['data'] as Map)['action'], 'begin');
      expect(
        (api.writes.single['data'] as Map)['calendarKey'],
        'google:personal\nevent-2',
      );
      api.writes.clear();
      await tester.tap(find.text('Completed!'));
      await tester.pumpAndSettle();
      expect(api.writes.single['path'], '/v1/focus/actions');
      expect((api.writes.single['data'] as Map)['action'], 'complete');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  test(
    'Day list keeps completed tasks, uses local day and merges only exact occurrence IDs',
    () {
      final model = CortexModel();
      final now = DateTime.now();
      Map<String, dynamic> row(String id, String status) => {
        'id': id,
        'status': status,
        'revision': 1,
        'taskId': 'same-todo',
        'scheduledStart': now.toUtc().toIso8601String(),
      };
      model.taskFocus.plannedDate = day(now);
      model.taskFocus.plannedTasks = [
        row('first', 'done'),
        row('second', 'pending'),
      ];
      model.taskFocus.tasks = [
        {...row('second', 'active'), 'revision': 2},
        {
          ...row('tomorrow', 'pending'),
          'scheduledStart': now
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        },
      ];
      final rows = model.taskFocus.plannedForToday(now);
      expect(rows, hasLength(2));
      expect(rows.firstWhere((f) => f['id'] == 'first')['status'], 'done');
      expect(rows.firstWhere((f) => f['id'] == 'second')['status'], 'active');
      expect(planClock(1470), '00:30 +1 day');
      model.dispose();
    },
  );
}
