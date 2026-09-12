import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cortex/core/cortex.dart';

class CalendarApi extends CortexApi {
  final snapshots = <Map>[];
  bool fail = false;
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    if (path == '/v1/calendars/sync') {
      if (fail) throw ApiException(503, 'Retry');
      snapshots.add(data as Map);
      return {'count': 0};
    }
    return {'records': [], 'messages': [], 'sessions': [], 'chat': {}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Granted permission automatically syncs all calendars, persists selection and protects against denial',
    () async {
      SharedPreferences.setMockInitialValues({});
      var permission = 'granted';
      final calls = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (call) async {
            calls.add(call.arguments as Map);
            if (permission != 'granted') return {'permission': permission};
            final ids =
                (call.arguments as Map)['selectedIds'] as List? ??
                ['personal', 'work'];
            return {
              'permission': 'granted',
              'start': '2026-09-13',
              'end': '2026-10-13',
              'calendars': [
                for (final id in ['personal', 'work'])
                  {
                    'id': id,
                    'title': id,
                    'sourceId': id,
                    'account': id,
                    'count': 1,
                  },
              ],
              'events': [
                for (final id in ids)
                  {
                    'externalId': 'event-$id',
                    'calendarId': id,
                    'date': '2026-09-14',
                    'title': id,
                    'start': 600,
                    'end': 630,
                  },
              ],
            };
          });
      final api = CalendarApi();
      final m = CortexModel(api: api)..paired = true;
      await m.syncCalendars();
      expect(api.snapshots.single['events'], hasLength(2));
      expect(calls.single['requestAccess'], isFalse);
      await m.syncCalendars();
      expect(
        api.snapshots,
        hasLength(1),
        reason: 'Unchanged snapshots do not rewrite MongoDB',
      );
      await m.chooseCalendars({'work'});
      expect(
        (api.snapshots.last['events'] as List).single['calendarId'],
        'work',
      );
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'calendar.selection.v1',
        ),
        ['work'],
      );
      permission = 'denied';
      await m.syncCalendars();
      expect(
        api.snapshots,
        hasLength(2),
        reason: 'Revoked access must not erase events',
      );
      permission = 'granted';
      api.fail = true;
      await m.chooseCalendars({});
      expect(m.calendarError, isNotNull);
      api.fail = false;
      await m.syncCalendars();
      expect(
        api.snapshots.last['events'],
        isEmpty,
        reason: 'Explicitly choosing no calendars clears this device mirror',
      );
      m.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, null);
    },
  );
}
