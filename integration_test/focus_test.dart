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
        final previousActivity = state['liveActivityID'];
        await native.invokeMethod('focusTestExpire');
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          state = await native.invokeMethod<Map>('focusStatus') ?? {};
          if (state['liveCount'] == 1 &&
              state['liveActivityID'] != previousActivity) {
            break;
          }
        }
        expect(
          state['liveCount'],
          1,
          reason: 'Foreground expiry restores the unfinished card.',
        );
        expect(state['liveActivityID'], isNot(previousActivity));
        expect(item(a['id'])['expectedEnd'], a['expectedEnd']);
        expect(item(b['id'])['expectedEnd'], b['expectedEnd']);
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
        // A stale ready label must not expose a task hours before its start.
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
        expect(state['liveCount'], 0);
        expect(state['liveState'], 'scheduled');
        expect((state['scheduledBoards'] as List).length, 1);
        // All eight supported overlapping tasks remain reachable through local pages.
        final board = [
          for (var i = 0; i < 8; i++)
            {
              ...a,
              'id': 'board-page-$i-$base',
              'title': 'Task ${i + 1}',
              'status': 'active',
              'expectedEnd': iso(now.add(const Duration(hours: 1))),
            },
        ];
        state =
            await native.invokeMethod<Map>('focusApply', {'focuses': board}) ??
            {};
        expect(state['livePages'], 4);
        final activityID = state['liveActivityID'];
        final taskSnapshot = state['focuses'];
        final actionSnapshot = state['pending'];
        final notifications = state['notificationCount'];
        Future<void> page(int value) async {
          state =
              await native.invokeMethod<Map>('focusPage', {'page': value}) ??
              {};
        }

        for (var value = 0; value < 4; value++) {
          await page(value);
          expect(state['livePage'], value);
          expect(state['liveTaskIDs'], [
            board[value * 2]['id'],
            board[value * 2 + 1]['id'],
          ]);
          expect(state['liveActivityID'], activityID);
          expect(state['notificationCount'], notifications);
          expect(
            state['focuses'],
            taskSnapshot,
            reason: 'Paging never edits a task.',
          );
          expect(
            state['pending'],
            actionSnapshot,
            reason: 'Paging creates no server actions.',
          );
        }
        await page(1);
        await page(
          1,
        ); // A repeated tap from the same rendered card is idempotent.
        state = await native.invokeMethod<Map>('focusRestore') ?? {};
        expect(state['livePage'], 1);
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': board.reversed.toList(),
            }) ??
            {};
        expect(state['liveTaskIDs'], [board[2]['id'], board[3]['id']]);
        expect(state['focuses'], taskSnapshot);
        await page(-1);
        expect(state['livePage'], 0);
        await page(999);
        expect(state['livePage'], 3);
        await act(board[6]['id'], 'complete');
        expect(state['liveTaskIDs'], [board[7]['id']]);
        await act(board[7]['id'], 'complete');
        expect(
          state['livePage'],
          2,
          reason: 'Finishing the last page returns to a valid pair.',
        );
        expect(state['liveTaskIDs'], [board[4]['id'], board[5]['id']]);
        // Three tasks yield a pair and a final full-width single task.
        final odd = [
          for (var i = 0; i < 3; i++) {...board[i], 'id': 'board-odd-$i-$base'},
        ];
        state =
            await native.invokeMethod<Map>('focusApply', {'focuses': odd}) ??
            {};
        await page(1);
        expect(state['livePages'], 2);
        expect(state['liveTaskIDs'], [odd[2]['id']]);
        await act(odd[2]['id'], 'complete');
        expect(state['livePages'], 1);
        expect(state['livePage'], 0);
        expect(state['liveTaskIDs'], [odd[0]['id'], odd[1]['id']]);
        final busyDay = [
          for (var i = 0; i < 12; i++)
            {
              ...board.first,
              'id': 'calendar-busy-$i-$base',
              'title': 'Calendar task $i',
            },
        ];
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': busyDay,
            }) ??
            {};
        expect(state['livePages'], 6);
        expect((state['liveCoveredIDs'] as List).length, 12);
        await page(5);
        expect(state['liveTaskIDs'], [busyDay[10]['id'], busyDay[11]['id']]);
        expect(state['liveCount'], 1);
        // Preloading the day must not make future work visible or add pages.
        final later = {
          ...busyDay.last,
          'id': 'calendar-later-$base',
          'status': 'pending',
          'activateAt': iso(now.add(const Duration(hours: 1))),
          'scheduledStart': iso(now.add(const Duration(minutes: 90))),
          'startedAt': '0001-01-01T00:00:00Z',
          'expectedEnd': iso(now.add(const Duration(hours: 2))),
        };
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [busyDay.first, later],
            }) ??
            {};
        expect(state['livePages'], 1);
        expect(state['liveTaskIDs'], [busyDay.first['id']]);
        expect(item(later['id'] as String)['status'], 'pending');
        await page(99);
        expect(state['liveTaskIDs'], [busyDay.first['id']]);
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [
                busyDay.first,
                {
                  ...later,
                  'revision': base + 1,
                  'activateAt': iso(
                    DateTime.now().subtract(const Duration(seconds: 1)),
                  ),
                  'scheduledStart': iso(
                    DateTime.now().add(const Duration(minutes: 30)),
                  ),
                },
              ],
            }) ??
            {};
        expect(state['liveTaskIDs'], [busyDay.first['id'], later['id']]);
        expect(item(later['id'] as String)['status'], 'ready');
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
  testWidgets(
    'Upcoming calendar cards are scheduled, moved and activated without starting work',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Calendar scheduling verification')),
        ),
      );
      var state = await native.invokeMethod<Map>('focusPermission') ?? {};
      final previous = state['focuses'] ?? [];
      final now = DateTime.now();
      Map<String, dynamic> event(
        String id,
        DateTime activation,
        int revision,
      ) => {
        'id': id,
        'title': 'Calendar · Walk',
        'status': 'pending',
        'revision': revision,
        'activateAt': activation.toUtc().toIso8601String(),
        'scheduledStart': activation
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'expectedEnd': activation
            .add(const Duration(minutes: 60))
            .toUtc()
            .toIso8601String(),
        'durationMinutes': 30,
        'intervalMinutes': 15,
        'preview': true,
      };
      final a = event('scheduled-a', now.add(const Duration(seconds: 25)), 1);
      final b = event('scheduled-b', now.add(const Duration(hours: 10)), 1);
      try {
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [a, b],
            }) ??
            {};
        expect(state['liveActive'], false);
        expect(state['liveState'], 'scheduled');
        expect((state['scheduledBoards'] as List).length, 2);
        final ids = (state['scheduledBoards'] as List)
            .map((b) => b['id'])
            .toSet();
        state = await native.invokeMethod<Map>('focusRestore') ?? {};
        expect(
          (state['scheduledBoards'] as List).map((b) => b['id']).toSet(),
          ids,
        );
        await expectLater(
          native.invokeMethod('focusAction', {
            'id': a['id'],
            'expectedRevision': 1,
            'action': 'extend',
            'minutes': 5,
          }),
          throwsA(isA<PlatformException>()),
        );
        final moved = event(
          'scheduled-a',
          DateTime.now().add(const Duration(seconds: 10)),
          2,
        );
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': [moved],
            }) ??
            {};
        expect((state['scheduledBoards'] as List).length, 1);
        final scheduledID = (state['scheduledBoards'] as List).single['id'];
        expect(ids.contains(scheduledID), false);
        // No focusRestore/apply while the clock runs: ActivityKit must activate it.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 14)),
        );
        state = await native.invokeMethod<Map>('focusStatus') ?? {};
        expect(state['liveActive'], true);
        expect(state['liveActivityID'], scheduledID);
        expect((state['focuses'] as List).single['status'], 'ready');
        expect((state['focuses'] as List).single['revision'], 2);
        expect(
          state['pending'],
          isEmpty,
          reason: 'Clock activation is not an owner action.',
        );
        state =
            await native.invokeMethod<Map>('focusAction', {
              'id': a['id'],
              'expectedRevision': 2,
              'action': 'begin',
            }) ??
            {};
        expect((state['focuses'] as List).single['status'], 'active');
        expect((state['pending'] as List).single['action'], 'begin');
      } finally {
        state = await native.invokeMethod<Map>('focusStatus') ?? {};
        for (final request in List<Map>.from(state['pending'] as List)) {
          await native.invokeMethod('focusAcknowledge', {
            'requestId': request['requestId'],
            'discarded': true,
          });
        }
        state =
            await native.invokeMethod<Map>('focusApply', {
              'focuses': previous,
            }) ??
            {};
        expect(state['scheduledBoards'], isEmpty);
      }
    },
  );
}
