import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/core/phone_alarms.dart';
import 'package:cortex/core/memory_notices.dart';
import 'package:cortex/app/shell.dart';

class AlarmApi extends CortexApi {
  Map<String, dynamic> alarm = {
    'id': '11111111-1111-1111-1111-111111111111',
    'revision': 1,
    'action': 'schedule',
    'status': 'pending',
    'spec': {'title': 'Wake up', 'at': '2027-01-01T10:00:00+09:00'},
  };
  final List<Map> acknowledgements = [];
  @override
  Future<dynamic> call(String method, String path, [Object? body]) async {
    if (path == '/v1/alarms') {
      return {
        'alarms': [Map<String, dynamic>.from(alarm)],
      };
    }
    if (path.endsWith('/ack')) {
      acknowledgements.add(body as Map);
      alarm['status'] = body['status'];
    }
    return {'saved': true};
  }
}

Map<String, dynamic> memoryRecord(String event, {String action = 'saved'}) => {
  'memoryEvents': [
    {
      'id': event,
      'recordId': 'morning-preference',
      'text': 'You prefer quiet mornings.',
      'action': action,
      'created': event,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null),
  );

  test(
    'Alarm is only acknowledged after the native phone confirms it',
    () async {
      final nativeResult = Completer<Map>();
      final entered = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (call) async {
            if (call.method == 'alarmStatus') {
              return {'permission': 'authorized', 'scheduledIds': []};
            }
            entered.complete();
            return nativeResult.future;
          });
      final api = AlarmApi();
      final alarms = PhoneAlarms(api: api, changed: () {}, canSync: () => true);
      final work = alarms.sync();
      await entered.future;
      expect(api.acknowledgements, isEmpty);
      expect(alarms.items.single['status'], 'pending');
      nativeResult.complete({'status': 'scheduled'});
      await work;
      expect(api.acknowledgements.single['revision'], 1);
      expect(api.acknowledgements.single['status'], 'scheduled');
      alarms.dispose();
      api.close();
    },
  );

  test(
    'Permission denial stays unconfirmed and granting resumes the request',
    () async {
      var permission = 'notDetermined', applies = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (call) async {
            if (call.method == 'alarmPermission') permission = 'authorized';
            if (call.method != 'alarmApply') {
              return {'permission': permission, 'scheduledIds': []};
            }
            applies++;
            if (permission != 'authorized') {
              permission = 'denied';
              return {'status': 'needs_permission'};
            }
            return {'status': 'scheduled'};
          });
      final api = AlarmApi();
      final alarms = PhoneAlarms(api: api, changed: () {}, canSync: () => true);
      await alarms.sync();
      expect(alarms.items.single['status'], 'needs_permission');
      await alarms.sync();
      expect(applies, 1);
      await alarms.sync(requestPermission: true);
      expect(alarms.items.single['status'], 'scheduled');
      expect(applies, 2);
      alarms.dispose();
      api.close();
    },
  );

  test(
    'Memory notices are not replayed by refresh or restarting the app',
    () async {
      final notices = MemoryNotices();
      await notices.receive([memoryRecord('001')]);
      await notices.receive([memoryRecord('001')]);
      expect(notices.pending, hasLength(1));
      await notices.displayed(notices.pending.single);
      final restarted = MemoryNotices();
      await restarted.receive([
        memoryRecord('001'),
        memoryRecord('002', action: 'updated'),
      ]);
      expect(restarted.pending, hasLength(1));
      expect(restarted.pending.single['action'], 'updated');
    },
  );

  testWidgets('A saved memory shows a snackbar with a working View action', (
    tester,
  ) async {
    final model = CortexModel();
    await model.memoryNotices.receive([memoryRecord('001')]);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(model: model)));
    await tester.pumpAndSettle();
    expect(
      find.text('Memory saved: You prefer quiet mornings.'),
      findsOneWidget,
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Saved memory'), findsOneWidget);
    expect(find.text('You prefer quiet mornings.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
