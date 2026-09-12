import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';

class CalendarApi extends CortexApi {
  final requests = <Map>[];
  bool fail = false;
  String status = 'ready';
  int refreshes = 0;
  List<String>? selection;
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    if (path == '/v1/google/sync') {
      if (fail) throw ApiException(503, 'Retry');
      final request = data as Map;
      requests.add(request);
      if (request.containsKey('selectedIds')) {
        selection = (request['selectedIds'] as List).cast<String>();
      }
      return {
        'source': 'google',
        'status': status,
        'syncedAt': '2026-09-13T01:00:00Z',
        'selectedIds': selection,
        'calendars': [
          for (final id in ['personal', 'work'])
            {'id': id, 'title': id, 'sourceId': id, 'account': id, 'count': 1},
        ],
        if (status == 'needsLink')
          'error': 'Link a Google account to start sync.',
      };
    }
    expect(path, '/v1/snapshot');
    refreshes++;
    return {'records': [], 'messages': [], 'sessions': [], 'chat': {}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Google owns sync and shared selection; phone calendar import is never called',
    () async {
      final nativeCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (call) async {
            nativeCalls.add(call.method);
            expect(call.method, 'calendarTimeZone');
            return 'Asia/Seoul';
          });
      final api = CalendarApi();
      final m = CortexModel(api: api)..paired = true;
      await m.syncCalendars();
      expect(m.calendarGranted, isTrue);
      expect(m.calendars, hasLength(2));
      expect(api.requests.single['timeZone'], 'Asia/Seoul');
      expect(api.requests.single['force'], isFalse);
      await m.syncCalendars();
      expect(
        api.refreshes,
        1,
        reason: 'Unchanged cache does not reload the screen',
      );
      await m.chooseCalendars({'work'});
      expect(api.requests.last['selectedIds'], ['work']);
      expect(m.selectedCalendars, {'work'});
      final secondDevice = CortexModel(api: api)..paired = true;
      await secondDevice.syncCalendars();
      expect(
        secondDevice.selectedCalendars,
        {'work'},
        reason: 'Selection is stored on the server',
      );
      api.fail = true;
      await m.chooseCalendars({});
      expect(m.calendarError, isNotNull);
      expect(
        m.selectedCalendars,
        {'work'},
        reason: 'Failed save must retain the previous selection',
      );
      api.fail = false;
      await m.chooseCalendars({});
      expect(m.selectedCalendars, isEmpty);
      api.status = 'needsLink';
      await m.syncCalendars();
      expect(m.calendarGranted, isFalse);
      expect(m.calendarError, contains('Link a Google account'));
      expect(nativeCalls, everyElement('calendarTimeZone'));
      m.dispose();
      secondDevice.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, null);
    },
  );
}
