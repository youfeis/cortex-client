import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cortex/core/cortex.dart';

// Device UI test on a disposable simulator: after the READY line, send the app
// Home, expand its reminder, and tap Take a break. This exercises UIKit's real
// background notification completion, which a mocked MethodChannel cannot test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Background notification action saves locally without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Notification recovery QA'))),
    );
    var state = await native.invokeMethod<Map>('focusStatus') ?? {};
    expect(state['focuses'], isEmpty, reason: 'Use a disposable simulator.');
    expect(state['pending'], isEmpty);
    state = await native.invokeMethod<Map>('focusPermission') ?? {};
    expect(state['permission'], 'authorized');
    final now = DateTime.now().toUtc();
    try {
      await native.invokeMethod('focusApply', {
        'focuses': [
          {
            'id': 'notification-callback-qa',
            'title': 'Notification recovery QA',
            'status': 'active',
            'revision': 1,
            'preview': true,
            'startedAt': now.toIso8601String(),
            'expectedEnd': now
                .add(const Duration(seconds: 15))
                .toIso8601String(),
            'durationMinutes': 1,
            'intervalMinutes': 15,
          },
        ],
      });
      debugPrint(
        'READY: background the app; expand reminder; tap Take a break.',
      );
      for (var i = 0; i < 120; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        state = await native.invokeMethod<Map>('focusStatus') ?? {};
        if ((state['pending'] as List).isNotEmpty) break;
      }
      expect((state['focuses'] as List).single['status'], 'paused');
      expect((state['pending'] as List).single['action'], 'pause');
      expect(state['notificationCount'], 0);
      expect(state['liveActive'], true, reason: 'Paused work keeps its card.');
    } finally {
      state = await native.invokeMethod<Map>('focusStatus') ?? {};
      for (final action in state['pending'] as List) {
        await native.invokeMethod('focusAcknowledge', {
          'requestId': action['requestId'],
          'discarded': true,
        });
      }
      await native.invokeMethod('focusApply', {'focuses': []});
    }
  });
}
