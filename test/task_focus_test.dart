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
  Map<String, dynamic> status() => {
    'permission': 'authorized',
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
