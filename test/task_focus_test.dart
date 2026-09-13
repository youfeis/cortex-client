import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/core/task_focus.dart';
import 'package:cortex/features/time/task_focus.dart';

class FocusApi extends CortexApi {
  bool offline = false, conflict = false;
  Completer<void>? blockedGet;
  Map<String, dynamic> focus = {
    'id': 'task-focus',
    'revision': 1,
    'title': 'Laundry',
    'status': 'active',
    'expectedEnd': '2027-01-01T12:00:00Z',
  };
  final acks = <Map>[];
  @override
  Future<dynamic> call(String method, String path, [Object? body]) async {
    if (method == 'GET' && blockedGet != null) await blockedGet!.future;
    if (offline) throw Exception('offline');
    if (path.endsWith('/actions')) {
      if (conflict) throw ApiException(409, 'Task changed');
      final action = body as Map;
      focus = {
        ...focus,
        'revision': (focus['revision'] as int) + 1,
        'status': action['action'] == 'complete'
            ? 'done'
            : action['action'] == 'pause'
            ? 'paused'
            : 'active',
      };
    }
    if (path.endsWith('/ack')) acks.add(body as Map);
    return {'focus': focus};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FocusApi api;
  late TaskFocus focus;
  late Map<String, dynamic> local;
  late List<Map<String, dynamic>> pending;
  var count = 32;
  List<String>? coverage;
  Map<String, dynamic> status() => {
    'permission': 'authorized',
    'liveCoveredIDs': ?coverage,
    'liveEnabled': true,
    'liveActive': local['status'] == 'active',
    'notificationCount': local['status'] == 'active' ? count : 0,
    'scheduledThrough': '2027-01-01T20:00:00Z',
    'focus': local,
    'pending': pending,
  };
  setUp(() {
    api = FocusApi();
    local = Map.from(api.focus);
    pending = [];
    count = 32;
    coverage = null;
    focus = TaskFocus(api: api, changed: () {}, canSync: () => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
          final a = call.arguments as Map? ?? {};
          if (call.method == 'focusApply' && pending.isEmpty) {
            local = Map<String, dynamic>.from(a['focus'] as Map);
          }
          if (call.method == 'focusAction') {
            pending.add({
              'id': local['id'],
              'expectedRevision': local['revision'],
              'requestId': 'action-1',
              'action': a['action'],
            });
            local = {
              ...local,
              'revision': (local['revision'] as int) + 1,
              'status': a['action'] == 'complete'
                  ? 'done'
                  : a['action'] == 'pause'
                  ? 'paused'
                  : 'active',
            };
          }
          if (call.method == 'focusAcknowledge') {
            pending.removeWhere((p) => p['requestId'] == a['requestId']);
          }
          return status();
        });
  });
  tearDown(() {
    focus.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
  });
  test(
    'only native scheduled reminders produce a scheduled acknowledgement',
    () async {
      count = 0;
      await focus.sync();
      expect(api.acks.last['status'], 'failed');
      count = 32;
      await focus.sync();
      expect(api.acks.last['status'], 'scheduled');
      expect(focus.visible, isTrue);
    },
  );
  test(
    'Card acknowledgements use per-task coverage, including pending schedules',
    () async {
      coverage = [];
      await focus.sync();
      expect(
        api.acks.last['status'],
        'notifications_only',
        reason: 'Another task card does not cover this task.',
      );
      count = 0;
      api.focus['status'] = 'pending';
      api.focus['scheduledStart'] = DateTime.now()
          .add(const Duration(hours: 2))
          .toUtc()
          .toIso8601String();
      coverage = ['task-focus'];
      await focus.sync();
      expect(api.acks.last['status'], 'scheduled');
      expect(focus.liveActive, false);
      expect(
        focus.visible,
        false,
        reason: 'A queued card is not available work yet.',
      );
    },
  );
  test('Only due-soon work or work already started is visible', () {
    final now = DateTime.utc(2026, 9, 13, 10);
    Map<String, dynamic> planned(Duration untilStart) => {
      'status': 'pending',
      'scheduledStart': now.add(untilStart).toIso8601String(),
      'activateAt': now
          .add(untilStart - const Duration(minutes: 30))
          .toIso8601String(),
    };
    expect(
      focusTaskVisibleAt(planned(const Duration(minutes: 30, seconds: 1)), now),
      false,
    );
    expect(focusTaskVisibleAt(planned(const Duration(minutes: 30)), now), true);
    expect(focusTaskPhase(planned(const Duration(minutes: 20)), now), 'ready');
    expect(
      focusTaskVisibleAt({
        ...planned(const Duration(hours: 2)),
        'status': 'ready',
      }, now),
      false,
    );
    expect(
      focusTaskVisibleAt({
        'status': 'active',
        'expectedEnd': now.subtract(const Duration(hours: 1)).toIso8601String(),
      }, now),
      true,
    );
    for (final status in ['paused', 'postponed']) {
      expect(
        focusTaskVisibleAt({
          'status': status,
          'startedAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
        }, now),
        true,
      );
      expect(
        focusTaskVisibleAt({
          'status': status,
          'startedAt': '0001-01-01T00:00:00Z',
        }, now),
        false,
      );
    }
    for (final status in ['done', 'cancelled', 'pending']) {
      expect(focusTaskVisibleAt({'status': status}, now), false);
    }
  });
  testWidgets('Task cards hide the future queue and show due-soon controls', (
    tester,
  ) async {
    final model = CortexModel();
    final now = DateTime.now();
    model.taskFocus.tasks = [
      {
        'id': 'later',
        'title': 'Later task',
        'status': 'pending',
        'scheduledStart': now.add(const Duration(hours: 2)).toIso8601String(),
      },
      {
        'id': 'soon',
        'title': 'Soon task',
        'status': 'pending',
        'scheduledStart': now
            .add(const Duration(minutes: 20))
            .toIso8601String(),
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FocusPanel(model: model)),
      ),
    );
    expect(find.text('Soon task'), findsOneWidget);
    expect(find.text('Later task'), findsNothing);
    expect(find.text('Your current task'), findsOneWidget);
    expect(find.text('I’ve started'), findsOneWidget);
    expect(find.text('Start early'), findsNothing);
    expect(
      model.taskFocus.tasks,
      hasLength(2),
      reason: 'Keep future tasks for scheduling, not display.',
    );
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  test(
    'offline break stops local reminders and remains queued until server catches up',
    () async {
      await focus.sync();
      api.offline = true;
      await focus.act('pause');
      expect(focus.current!['status'], 'paused');
      expect(focus.notificationCount, 0);
      expect(focus.pending, isTrue);
      expect(api.focus['status'], 'active');
      api.offline = false;
      await focus.sync();
      expect(api.focus['status'], 'paused');
      expect(focus.pending, isFalse);
      expect(api.acks.last['status'], 'stopped');
    },
  );
  test('stale notification action cannot change a newer server task', () async {
    await focus.sync();
    api.conflict = true;
    api.focus = {
      ...api.focus,
      'id': 'new-task',
      'revision': 5,
      'title': 'Reading',
    };
    await focus.act('complete');
    expect(focus.current!['id'], 'new-task');
    expect(focus.current!['status'], 'active');
    expect(focus.pending, isFalse);
    expect(focus.error, contains('changed'));
  });
  test('a slow refresh cannot delay an offline pause', () async {
    await focus.sync();
    final gate = Completer<void>();
    api.blockedGet = gate;
    final refresh = focus.sync();
    await Future<void>.delayed(Duration.zero);
    await focus.act('pause').timeout(const Duration(seconds: 1));
    expect(focus.current!['status'], 'paused');
    expect(focus.pending, isTrue);
    api.blockedGet = null;
    gate.complete();
    await refresh;
    await Future<void>.delayed(Duration.zero);
    await focus.sync();
    expect(api.focus['status'], 'paused');
  });
  test(
    'restore shows the cached card without waiting for the server',
    () async {
      await focus.sync();
      final gate = Completer<void>();
      api.blockedGet = gate;
      final refresh = focus.sync();
      await Future<void>.delayed(Duration.zero);
      await focus.restore().timeout(const Duration(seconds: 1));
      expect(focus.liveActive, isTrue);
      expect(focus.current!['id'], 'task-focus');
      api.blockedGet = null;
      gate.complete();
      await refresh;
    },
  );
  testWidgets(
    'A long task sheet can be closed after scrolling without stopping work',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = CortexModel();
      model.taskFocus.tasks = [
        for (var i = 0; i < 8; i++)
          {...local, 'id': 'task-$i', 'title': 'Work in progress $i'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FocusPanel(model: model, compact: true)),
        ),
      );
      await tester.tap(find.text('Tap to review your task timers'));
      await tester.pumpAndSettle();
      final close = find.widgetWithText(TextButton, 'Close');
      final before = tester.getRect(close);
      expect(before.height, greaterThanOrEqualTo(48));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(close), before);
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Your tasks'), findsNothing);
      expect(
        find.text('Tap to review your task timers').hitTestable(),
        findsOneWidget,
      );
      expect(model.taskFocus.tasks, hasLength(8));
      expect(
        model.taskFocus.tasks.map((f) => f['status']),
        everyElement('active'),
      );
      expect(pending, isEmpty);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'current task offers done, more time, and break without an edit form',
    (tester) async {
      final model = CortexModel();
      model.taskFocus.current = local;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FocusPanel(model: model)),
        ),
      );
      expect(find.text('Laundry'), findsOneWidget);
      expect(find.text('Completed!'), findsOneWidget);
      expect(find.text('+5 min'), findsOneWidget);
      expect(find.text('Take a break'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
