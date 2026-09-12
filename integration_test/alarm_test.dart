import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cortex/core/cortex.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native AlarmKit schedules, retries, changes and cancels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Cortex alarm verification'))),
      ),
    );
    final permission = await native.invokeMethod<Map>('alarmPermission');
    expect(
      permission?['permission'],
      'authorized',
      reason: 'Allow alarms in the simulator system prompt.',
    );
    const id = 'b34b3a89-9999-4444-8888-111111111111';
    final baseRevision = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> command(
      int revision,
      String action,
      Map<String, dynamic> spec,
    ) => {
      'id': id,
      'revision': baseRevision + revision,
      'action': action,
      'spec': spec,
    };
    String future(int seconds) => DateTime.now()
        .toUtc()
        .add(Duration(seconds: seconds))
        .toIso8601String()
        .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    var spec = <String, dynamic>{
      'title': 'Cortex verification',
      'at': future(90),
    };
    try {
      // Reset only this fixed test ID, never the user's other alarms.
      await native.invokeMethod<Map>('alarmApply', command(100, 'cancel', {}));
      var result = await native.invokeMethod<Map>(
        'alarmApply',
        command(101, 'schedule', spec),
      );
      expect(result?['status'], 'scheduled');
      result = await native.invokeMethod<Map>(
        'alarmApply',
        command(101, 'schedule', spec),
      );
      expect(result?['status'], 'scheduled');
      var state = await native.invokeMethod<Map>('alarmStatus');
      expect(
        (state?['scheduledIds'] as List).where((v) => v == id),
        hasLength(1),
      );
      spec = {'title': 'Changed verification', 'at': future(100)};
      result = await native.invokeMethod<Map>(
        'alarmApply',
        command(102, 'schedule', spec),
      );
      expect(result?['status'], 'scheduled');
      result = await native.invokeMethod<Map>(
        'alarmApply',
        command(101, 'schedule', spec),
      );
      expect(
        result?['status'],
        'failed',
        reason: 'Old requests must not overwrite a newer alarm.',
      );
      spec = {
        'title': 'Weekly verification',
        'hour': 10,
        'minute': 0,
        'weekdays': [1, 3],
      };
      result = await native.invokeMethod<Map>(
        'alarmApply',
        command(103, 'schedule', spec),
      );
      expect(result?['status'], 'scheduled');
      // Exercise the actual system ringing state, not just the scheduled list.
      spec = {'title': 'Cortex alarm test', 'at': future(12)};
      result = await native.invokeMethod<Map>(
        'alarmApply',
        command(104, 'schedule', spec),
      );
      expect(result?['status'], 'scheduled');
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        state = await native.invokeMethod<Map>('alarmStatus');
        if ((state?['states'] as Map?)?[id] == 'alerting') break;
      }
      expect((state?['states'] as Map?)?[id], 'alerting');
      await binding.takeScreenshot('alarm-ringing');
    } finally {
      final result = await native.invokeMethod<Map>(
        'alarmApply',
        command(105, 'cancel', {}),
      );
      expect(result?['status'], 'cancelled');
      final state = await native.invokeMethod<Map>('alarmStatus');
      expect((state?['scheduledIds'] as List).contains(id), isFalse);
    }
  });
}
