import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/fitness/energy.dart';
import 'package:cortex/features/fitness/fitness_screen.dart';

Map<String, dynamic> stepRow(int count, {String? date}) => {
  'id': 'health-steps-${date ?? day()}',
  'kind': 'steps',
  'data': {'date': date ?? day(), 'source': 'appleHealth', 'count': count},
};

Map<String, dynamic> healthRows(int count) => {
  'permission': 'requested',
  'records': [stepRow(count)],
};

class HealthApi extends CortexApi {
  List<Map<String, dynamic>> rows = [
    {
      'id': 'goal',
      'kind': 'goal',
      'data': {
        'tdee': 2451.6,
        'deficit': 500,
        'stepBaseline': 3000,
        'kcalPerExtraStep': .045,
      },
    },
    {
      'id': 'meal',
      'kind': 'meal',
      'data': {'date': day(), 'kcal': 1000},
    },
    stepRow(4000),
  ];
  Completer<void>? snapshotGate;
  int snapshots = 0, uploads = 0, failures = 0;
  final stream = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> events() => stream.stream;

  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    if (path.startsWith('/v1/snapshot?')) {
      snapshots++;
      final captured = List<Map<String, dynamic>>.of(rows);
      if (failures > 0) {
        failures--;
        throw ApiException(503, 'Snapshot unavailable');
      }
      final gate = snapshotGate;
      snapshotGate = null;
      await gate?.future;
      return {'records': captured, 'messages': [], 'sessions': [], 'chat': {}};
    }
    if (path == '/v1/health/sync') {
      uploads++;
      for (final row in (data as Map)['records'] as List) {
        rows.removeWhere((old) => old['id'] == row['id']);
        rows.add(Map<String, dynamic>.from(row as Map));
      }
      return {'changed': 1};
    }
    return {};
  }

  @override
  void close() {
    unawaited(stream.close());
    super.close();
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'Expected asynchronous work to finish');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late HealthApi api;
  late CortexModel model;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = HealthApi();
    model = CortexModel(api: api)..paired = true;
    messenger.setMockMethodCallHandler(
      native,
      (call) async => call.method == 'readHealth' ? healthRows(10000) : {},
    );
  });
  tearDown(() {
    model.dispose();
    messenger.setMockMethodCallHandler(native, null);
  });

  test('Health upload waits for a snapshot started after the write', () async {
    final gate = Completer<void>();
    api.snapshotGate = gate;
    final oldRefresh = model.refresh();
    final health = model.syncHealth();
    await until(() => api.uploads == 1);
    expect(model.healthSyncing, isTrue);
    gate.complete();
    await Future.wait([oldRefresh, health]);
    final energy = DailyEnergy.fromRecords(model.entries, date: day());
    expect(api.snapshots, 2);
    expect(energy.steps, 10000);
    expect(energy.tdee, closeTo(2766.6, .001));
    expect(energy.remaining, closeTo(1266.6, .001));
    expect(model.healthError, isNull);
  });

  test(
    'Opening during a Health read queues fresh readings instead of dropping them',
    () async {
      final firstRead = Completer<Map>();
      var reads = 0;
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method != 'readHealth') return {};
        reads++;
        return reads == 1 ? firstRead.future : healthRows(10000);
      });
      final initial = model.syncHealth();
      await until(() => reads == 1);
      model.setForeground(false);
      model.setForeground(true);
      firstRead.complete(healthRows(4000));
      await initial;
      expect(reads, 2);
      expect(DailyEnergy.fromRecords(model.entries, date: day()).steps, 10000);
    },
  );

  test(
    'Cold start and every resume read Health, even when readings are unchanged',
    () async {
      var reads = 0;
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method != 'readHealth') return {};
        reads++;
        return healthRows(10000);
      });
      await model.initialize();
      await until(() => reads == 1 && !model.healthSyncing);
      for (var expected = 2; expected <= 3; expected++) {
        model.setForeground(false);
        model.setForeground(true);
        await until(
          () => reads == expected && !model.healthSyncing && !model.refreshing,
        );
      }
      expect(
        api.uploads,
        1,
        reason: 'Unchanged Health readings need no duplicate upload',
      );
    },
  );

  test(
    'Failed post-upload refresh retries unchanged readings on next open',
    () async {
      api.failures = 1;
      await model.syncHealth();
      expect(model.healthError, isNotNull);
      expect(model.healthSyncedAt, isNull);
      await model.syncHealth();
      expect(api.uploads, 2);
      expect(DailyEnergy.fromRecords(model.entries, date: day()).steps, 10000);
      expect(model.healthError, isNull);
      expect(model.healthSyncedAt, isNotNull);
    },
  );

  test(
    'Permission request during an existing read is preserved; empty reads keep saved data',
    () async {
      await model.refresh();
      final gate = Completer<Map>();
      final accessRequests = <bool>[];
      messenger.setMockMethodCallHandler(native, (call) async {
        accessRequests.add((call.arguments as Map)['requestAccess'] as bool);
        return accessRequests.length == 1 ? gate.future : healthRows(10000);
      });
      final automatic = model.syncHealth();
      await until(() => accessRequests.isNotEmpty);
      final permission = model.syncHealth(requestAccess: true);
      gate.complete({'permission': 'setupNeeded', 'records': []});
      await Future.wait([automatic, permission]);
      expect(accessRequests, [false, true]);
      messenger.setMockMethodCallHandler(
        native,
        (_) async => {'permission': 'requested', 'records': []},
      );
      await model.syncHealth();
      expect(DailyEnergy.fromRecords(model.entries, date: day()).steps, 10000);
      expect(api.uploads, 1);
    },
  );

  test(
    'Daily energy prefers Health total and excludes yesterday and duplicate active energy',
    () {
      final records = api.rows.map(Entry.fromJson).toList();
      records.insert(
        0,
        Entry('manual', 'steps', {
          'date': day(),
          'count': 99999,
        }, updated: DateTime.now()),
      );
      records.add(Entry.fromJson(stepRow(25000, date: '2020-01-01')));
      records.add(
        Entry('active', 'activity', {
          'date': day(),
          'source': 'appleHealth',
          'kcal': 600,
        }),
      );
      records.add(Entry('workout', 'activity', {'date': day(), 'kcal': 200}));
      final energy = DailyEnergy.fromRecords(records, date: day());
      expect(energy.steps, 4000);
      expect(energy.stepsExtraKcal, 45);
      expect(energy.workoutKcal, 200);
      expect(energy.tdee, closeTo(2696.6, .001));
      expect(energy.budget, closeTo(2196.6, .001));
      expect(energy.intake, 1000);
    },
  );

  testWidgets(
    'Refreshing Fitness updates the calorie bar and walking contribution together',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await model.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: FitnessScreen(model: model, onChat: (_, {photo = false}) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Today’s energy'));
      await tester.pumpAndSettle();
      final fill = find.byKey(const ValueKey('energy-intake-fill'));
      final before = tester.getSize(fill).width;
      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await indicator.onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('TDEE ~2767'), findsOneWidget);
      expect(find.text('Food budget 2267'), findsOneWidget);
      expect(find.text('1267 kcal left in your plan'), findsOneWidget);
      expect(tester.getSize(fill).width, lessThan(before));
      await tester.scrollUntilVisible(
        find.text('10000 steps'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.text('Walking adds ~315 kcal to today’s estimate.'),
        findsOneWidget,
      );
    },
  );
}
