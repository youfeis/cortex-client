import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cortex/core/cortex.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Task Live Activity, reminder delivery, offline actions, and stale actions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Cortex task check-in verification')),
          ),
        ),
      );
      var state = await native.invokeMethod<Map>('focusStatus') ?? {};
      expect(
        (state['pending'] as List).isEmpty,
        isTrue,
        reason: 'Use an idle simulator with no pending owner actions.',
      );
      expect((state['focus'] as Map?)?['status'], isNot('active'));
      final previous = state['focus'];
      state = await native.invokeMethod<Map>('focusPermission') ?? {};
      expect(
        state['permission'],
        'authorized',
        reason: 'Allow notifications in the simulator prompt.',
      );
      final base = DateTime.now().millisecondsSinceEpoch;
      final id = 'focus-verification-$base';
      String iso(DateTime d) => d.toUtc().toIso8601String();
      final f = {
        'id': id,
        'revision': base,
        'title': 'One small step · test',
        'status': 'active',
        'startedAt': iso(DateTime.now().subtract(const Duration(minutes: 25))),
        'expectedEnd': iso(
          DateTime.now().subtract(const Duration(minutes: 14, seconds: 48)),
        ),
        'intervalMinutes': 15,
      };
      try {
        state =
            await native.invokeMethod<Map>('focusApply', {'focus': f}) ?? {};
        for (var i = 0; i < 5 && state['liveActive'] != true; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          state =
              await native.invokeMethod<Map>('focusApply', {'focus': f}) ?? {};
        }
        expect(state['liveActive'], isTrue, reason: state.toString());
        expect(state['notificationCount'], 32);
        state =
            await native.invokeMethod<Map>('focusApply', {'focus': f}) ?? {};
        expect(
          state['notificationCount'],
          32,
          reason: 'Retries must not duplicate alerts.',
        );
        for (var i = 0; i < 25; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          state = await native.invokeMethod<Map>('focusStatus') ?? {};
          if ((state['deliveredCount'] as int) > 0) break;
        }
        expect(state['deliveredCount'], greaterThan(0));
        await binding.takeScreenshot('task-checkin-notification');
        state =
            await native.invokeMethod<Map>('focusAction', {
              'id': id,
              'expectedRevision': base,
              'action': 'pause',
            }) ??
            {};
        expect(state['notificationCount'], 0);
        expect(state['liveActive'], isFalse);
        expect((state['pending'] as List), hasLength(1));
        state =
            await native.invokeMethod<Map>('focusApply', {'focus': f}) ?? {};
        expect((state['focus'] as Map)['status'], 'paused');
        expect(state['notificationCount'], 0);
        final request = (state['pending'] as List).first as Map;
        await native.invokeMethod<Map>('focusAcknowledge', {
          'requestId': request['requestId'],
        });
        state =
            await native.invokeMethod<Map>('focusAction', {
              'id': id,
              'expectedRevision': base + 1,
              'action': 'extend',
            }) ??
            {};
        expect(state['notificationCount'], 32);
        expect(state['liveActive'], isTrue);
        await expectLater(
          native.invokeMethod<Map>('focusAction', {
            'id': id,
            'expectedRevision': base,
            'action': 'complete',
          }),
          throwsA(isA<PlatformException>()),
        );
        state =
            await native.invokeMethod<Map>('focusAction', {
              'id': id,
              'expectedRevision': base + 2,
              'action': 'complete',
            }) ??
            {};
        expect(state['notificationCount'], 0);
        expect(state['liveActive'], isFalse);
        expect((state['focus'] as Map)['status'], 'done');
      } finally {
        state = await native.invokeMethod<Map>('focusStatus') ?? {};
        for (final request in state['pending'] as List) {
          await native.invokeMethod<Map>('focusAcknowledge', {
            'requestId': (request as Map)['requestId'],
            'discarded': true,
          });
        }
        await native.invokeMethod<Map>('focusApply', {'focus': previous});
      }
    },
  );
}
