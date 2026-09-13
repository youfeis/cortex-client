import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/time/time_screen.dart';

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
    'Done keeps the canonical to-do and never writes a separate plan',
    (tester) async {
      final api = DayApi();
      final model = CortexModel(api: api)
        ..entries = [
          Entry('laundry', 'task', {
            'title': 'Laundry',
            'deadline': day(),
            'done': false,
            'minutes': 90,
          }),
        ];
      final screen = TimeScreen(model: model, onChat: (_, {photo = false}) {});
      final plan = Entry('plan-${day()}', 'plan', {
        'date': day(),
        'calendarStatus': 'ready',
      });
      final block = <String, dynamic>{
        'id': 'event',
        'taskId': 'laundry',
        'title': 'Laundry',
        'start': 600,
        'end': 625,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => screen.complete(context, plan, [block], block),
                child: const Text('Done'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(1));
      expect(api.writes.single['method'], 'PUT');
      expect(api.writes.single['path'], '/v1/records/laundry');
      final record = api.writes.single['data'] as Map;
      expect(record['data']['done'], true);
      expect(record['data']['deadline'], day());
      model.dispose();
    },
  );

  test('Two calendar blocks for one to-do resolve to their own timer', () {
    final model = CortexModel();
    model.taskFocus.tasks = [
      {
        'id': 'first',
        'taskId': 'task',
        'calendarKey': 'google:personal\nevent1',
      },
      {
        'id': 'second',
        'taskId': 'task',
        'calendarKey': 'google:personal\nevent2',
      },
    ];
    final screen = TimeScreen(model: model, onChat: (_, {photo = false}) {});
    expect(
      screen.timerFor({
        'calendarId': 'personal',
        'eventId': 'event2',
        'taskId': 'task',
      })?['id'],
      'second',
    );
    expect(planClock(1470), '00:30 +1 day');
    model.dispose();
  });
}
