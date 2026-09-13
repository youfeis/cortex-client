import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cortex/core/cortex.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'One card, overlapping timers, offline actions and foreground restoration',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Cortex task board verification')),
          ),
        ),
      );
      var state = await native.invokeMethod<Map>('focusStatus') ?? {};
      expect(
        (state['pending'] as List).isEmpty,
        isTrue,
        reason: 'Use an idle simulator.',
      );
      final previous = state['focuses'] ?? [];
      state = await native.invokeMethod<Map>('focusPermission') ?? {};
      expect(state['permission'], 'authorized');
      final base = DateTime.now().millisecondsSinceEpoch;
      String iso(DateTime d) => d.toUtc().toIso8601String();
      final now = DateTime.now();
      final a = <String, dynamic>{
        'id': 'board-test-a-$base',
        'revision': base,
        'title': 'Preview · Read for 25 minutes',
        'status': 'ready',
        'preview': true,
        'durationMinutes': 25,
        'scheduledStart': iso(now),
        'startedAt': iso(now),
        'expectedEnd': iso(now.add(const Duration(minutes: 25))),
        'intervalMinutes': 15,
      };
      final b = <String, dynamic>{
        'id': 'board-test-b-$base',
        'revision': base,
        'title': 'Preview · Laundry timer',
        'status': 'active',
        'preview': true,
        'durationMinutes': 40,
        'startedAt': iso(now.subtract(const Duration(minutes: 10))),
        'expectedEnd': iso(now.add(const Duration(seconds: 12))),
        'intervalMinutes': 15,
      };
      Map item(String id) => (state['focuses'] as List).cast<Map>().firstWhere(
        (f) => f['id'] == id,
      );
      Future<void> act(
        String id,
        String action, {
        int minutes = 15,
        String? reason,
      }) async {
        state =
            await native.invokeMethod<Map>('focusAction', {
              'id': id,
              'expectedRevision': item(id)['revision'],
              'action': action,
              'minutes': minutes,
              'reason': ?reason,
            }) ??
            {};
      }

      try {
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [a, b],
            }) ??
            {};
        for (var i = 0; i < 5 && state['liveActive'] != true; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          state = await native.invokeMethod<Map>('focusRestore') ?? {};
        }
        expect(state['liveCount'], 1);
        expect(state['notificationCount'], 40);
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [b, a],
            }) ??
            {};
        expect(
          (state['focuses'] as List).map((f) => f['id']).toList(),
          [a['id'], b['id']],
          reason: 'Server edit order must not move the Lock Screen buttons.',
        );
        for (var i = 0; i < 25; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          state = await native.invokeMethod<Map>('focusStatus') ?? {};
          if ((state['deliveredCount'] as int) > 0) break;
        }
        expect(state['deliveredCount'], greaterThan(0));
        await act(a['id'], 'begin');
        expect(item(a['id'])['status'], 'active');
        expect(item(b['id'])['revision'], base);
        final before = DateTime.parse(item(a['id'])['expectedEnd']);
        await act(a['id'], 'extend', minutes: 5);
        expect(
          DateTime.parse(item(a['id'])['expectedEnd']).difference(before),
          const Duration(minutes: 5),
        );
        expect(item(b['id'])['expectedEnd'], b['expectedEnd']);
        // Reopening restores one card, without resetting either timer or duplicating alerts.
        final endA = item(a['id'])['expectedEnd'];
        state = await native.invokeMethod<Map>('focusRestore') ?? {};
        expect(state['liveCount'], 1);
        expect(item(a['id'])['expectedEnd'], endA);
        await act(a['id'], 'postpone', reason: 'Tired, after 4 pm please.');
        expect(item(a['id'])['status'], 'postponed');
        expect(item(b['id'])['status'], 'active');
        expect((state['taskNotifications'] as Map)[a['id']]['count'], 0);
        expect(state['liveCount'], 1);
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [a, b],
            }) ??
            {};
        expect(
          item(a['id'])['status'],
          'postponed',
          reason: 'Offline action survives stale server response.',
        );
        await expectLater(
          native.invokeMethod<Map>('focusAction', {
            'id': a['id'],
            'expectedRevision': base,
            'action': 'complete',
          }),
          throwsA(isA<PlatformException>()),
        );
        await act(b['id'], 'complete');
        expect(
          state['liveCount'],
          1,
          reason: 'Postponed work remains reachable on the card.',
        );
        expect(state['notificationCount'], 0);
        state = await native.invokeMethod<Map>('focusRestore') ?? {};
        expect(state['liveCount'], 1);
        expect(item(a['id'])['status'], 'postponed');
        await act(a['id'], 'begin');
        expect(state['liveCount'], 1);
        expect(item(a['id'])['status'], 'active');
        await act(a['id'], 'pause');
        expect(
          state['liveCount'],
          1,
          reason: 'Pausing stops reminders, not access to the task.',
        );
        expect(state['notificationCount'], 0);
        await act(a['id'], 'cancel');
        expect(
          state['liveCount'],
          0,
          reason: 'Only completed or cancelled tasks remove the last card.',
        );
        expect(
          (state['pending'] as List)
              .where((e) => (e as Map)['action'] == 'postpone')
              .single['reason'],
          'Tired, after 4 pm please.',
        );
        await binding.takeScreenshot('task-board-verification');
        // Future-ready tasks must be visible now, not counted as visible while
        // ActivityKit has only scheduled a pending activity for their start time.
        final future = {
          ...a,
          'id': 'board-test-future-$base',
          'scheduledStart': iso(now.add(const Duration(hours: 2))),
          'expectedEnd': iso(now.add(const Duration(hours: 3))),
        };
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [future],
            }) ??
            {};
        expect(state['liveCount'], 1);
        expect(state['liveState'], 'active');
      } finally {
        state = await native.invokeMethod<Map>('focusStatus') ?? {};
        for (final request in List<Map>.from(state['pending'] as List)) {
          await native.invokeMethod<Map>('focusAcknowledge', {
            'requestId': request['requestId'],
            'discarded': true,
          });
        }
        await native.invokeMethod<Map>('focusApply', {'focuses': previous});
      }
    },
  );
}
