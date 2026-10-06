import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/time/todos.dart';

class ChecklistApi extends CortexApi {
  final writes = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    writes.add({'method': method, 'path': path, 'data': data});
    if (fail) throw Exception('Connection unavailable');
    return {'saved': true};
  }
}

class ChecklistModel extends CortexModel {
  ChecklistModel(ChecklistApi api) : super(api: api);
  @override
  Future<void> refresh() async {
    final request = (api as ChecklistApi).writes.last;
    final done = (request['data'] as Map)['done'] as bool;
    entries = [
      Entry('task-one', 'task', {
        'title': 'Laundry',
        'deadline': day(),
        'done': done,
        if (done) 'completedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    ];
    notifyListeners();
  }
}

void main() {
  testWidgets('Checkbox completes and reopens a to-do without chat or timers', (
    tester,
  ) async {
    final api = ChecklistApi();
    final model = ChecklistModel(api);
    model.entries = [
      Entry('task-one', 'task', {
        'title': 'Laundry',
        'deadline': day(),
        'done': false,
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: model,
              builder: (_, _) => TodoList(
                model: model,
                onChat: (_, {photo = false}) {
                  fail('Unexpected chat');
                },
              ),
            ),
          ),
        ),
      ),
    );
    final checkbox = find.byKey(const ValueKey('todo-check-task-one'));
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(api.writes.single['path'], '/v1/tasks/task-one/complete');
    expect(api.writes.single['data'], {'done': true});
    expect(model.entries.single.data['done'], true);
    expect(
      tester.widget<Text>(find.text('Laundry')).style?.decoration,
      TextDecoration.lineThrough,
    );
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(api.writes.last['data'], {'done': false});
    expect(model.entries.single.data['done'], false);
    expect(find.byTooltip('Start this task'), findsNothing);
    api.fail = true;
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(model.entries.single.data['done'], false);
    expect(find.textContaining('Connection unavailable'), findsOneWidget);
    model.dispose();
  });
}
