import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/cortex.dart';
import 'package:cortex/quota.dart';
import 'package:cortex/todos.dart';
import 'package:cortex/ui.dart';

void main() {
  test('Quota uses all buckets, remaining percentages and Unix seconds', () {
    final rows = quotaWindows({
      'rateLimits': {
        'primary': {'usedPercent': 99},
      },
      'rateLimitsByLimitId': {
        'codex': {
          'primary': {
            'usedPercent': 25,
            'windowDurationMins': 300,
            'resetsAt': 1905000000,
          },
          'secondary': {'usedPercent': 101, 'windowDurationMins': 10080},
        },
        'other': {
          'limitName': 'Other models',
          'primary': {'usedPercent': -1},
        },
      },
    });
    expect(rows.length, 3);
    expect(rows.first.remaining, 75);
    expect(rows.first.name, '5-hour');
    expect(rows.first.reset!.millisecondsSinceEpoch, 1905000000000);
    expect(rows[1].remaining, 0);
    expect(rows[1].name, 'Weekly');
    expect(rows[2].remaining, 100);
    expect(rows[2].bucket, 'Other models');
    expect(rows[1].reset, isNull);
    expect(
      rows.first.resetPassed(
        DateTime.fromMillisecondsSinceEpoch(1905000001000),
      ),
      isTrue,
    );
    expect(
      quotaWindows({
        'rateLimits': {
          'primary': {'usedPercent': null},
        },
      }).single.remaining,
      isNull,
    );
    expect(
      quotaWindows({
        'rateLimits': {'primary': null, 'secondary': null},
      }),
      isEmpty,
    );
  });
  test('A date-only to-do stays due today until the day ends', () {
    final task = Entry('a', 'task', {
      'title': 'Do laundry',
      'deadline': '2026-09-13',
    });
    expect(
      todoDueLabel(task, DateTime(2026, 9, 13, 23, 59)),
      startsWith('Due today'),
    );
    expect(todoDueLabel(task, DateTime(2026, 9, 14)), startsWith('Overdue'));
    expect(todoDueLabel(task, DateTime(2026, 9, 12)), 'Due · 13 Sep 2026');
  });
  testWidgets('To-dos sort by deadline and changes open chat without saving', (
    tester,
  ) async {
    final m = CortexModel()
      ..entries = [
        Entry('later', 'task', {'title': 'Later', 'deadline': '2026-10-01'}),
        Entry('first', 'task', {
          'title': 'First',
          'deadline': '2026-09-13T12:00',
        }),
        Entry('done', 'task', {
          'title': 'Finished',
          'deadline': '2026-09-12',
          'done': true,
        }),
      ];
    String? prompt;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodoList(
              model: m,
              onChat: (text, {photo = false}) => prompt = text,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('First')).dy,
      lessThan(tester.getTopLeft(find.text('Later')).dy),
    );
    expect(find.text('2 open'), findsOneWidget);
    await tester.tap(find.byTooltip('Discuss this to-do').first);
    expect(prompt, contains('First'));
    expect(m.entries.first.data['done'], isNull);
    m.dispose();
  });
  testWidgets('Keyboard accessory dismisses focus and preserves the draft', (
    tester,
  ) async {
    final focus = FocusNode();
    final draft = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissBar(child: child!),
        home: Scaffold(
          body: TextField(focusNode: focus, controller: draft),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(find.text('Hide keyboard'), findsOneWidget);
    await tester.tap(find.text('Hide keyboard'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(draft.text, 'Keep my draft');
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    draft.dispose();
  });
}
