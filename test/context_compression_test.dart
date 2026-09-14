import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/app/shell.dart';
import 'package:cortex/app/usage_header.dart';
import 'package:cortex/core/compression_notices.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompressionApi extends CortexApi {
  final requests = <Map<String, dynamic>>[];
  bool loseResponse = false;
  Map<String, dynamic> job = {};
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    if (path == '/v1/chat/compact') {
      requests.add(Map<String, dynamic>.from(data as Map));
      job = {
        'id': requests.last['requestId'],
        'source': 'old',
        'status': 'summarizing',
      };
      if (loseResponse) {
        loseResponse = false;
        throw Exception('Connection lost');
      }
      return job;
    }
    return {
      'records': [],
      'messages': [
        {
          'id': 'history',
          'role': 'user',
          'text': 'My previous message',
          'created': '2026-09-14T00:00:00Z',
        },
      ],
      'sessions': [],
      'chat': {'status': 'compressing', 'threadId': 'old', 'compaction': job},
    };
  }
}

CortexModel modelFor(CompressionApi api) => CortexModel(api: api)
  ..account = {
    'account': {'type': 'chatgpt'},
  }
  ..chat = {
    'status': 'ready',
    'threadId': 'old',
    'context': {'used': 48, 'window': 100},
  };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Completion notice survives app restart and ignores late progress',
    () async {
      const job = {'id': 'compression-one', 'status': 'summarizing'};
      final first = CompressionNotices();
      expect(await first.observe(job, initial: true), false);
      // The job finishes while the app is closed: announce it once on reopening.
      final second = CompressionNotices();
      final done = {...job, 'status': 'completed'};
      expect(await second.observe(done, initial: true), true);
      expect(await second.observe(done), false);
      expect(await second.observe(job), false);
      expect(await CompressionNotices().observe(done, initial: true), false);
      expect(
        (await SharedPreferences.getInstance()).getString(
          CompressionNotices.pendingKey,
        ),
        isNull,
      );
      // A genuinely new completion is still announced.
      expect(
        await second.observe({'id': 'compression-two', 'status': 'completed'}),
        true,
      );
    },
  );

  test(
    'Repeated snapshots produce one notification even when concurrent',
    () async {
      final notices = CompressionNotices();
      const done = {'id': 'new-job', 'status': 'failed'};
      expect(
        await Future.wait([notices.observe(done), notices.observe(done)]),
        [true, false],
      );
      expect(await CompressionNotices().observe(done, initial: true), false);
    },
  );

  testWidgets('Reopening with an old result stays quiet and never compresses', (
    tester,
  ) async {
    final api = CompressionApi();
    for (var restart = 0; restart < 2; restart++) {
      final model = modelFor(api)
        ..chat = {
          'status': 'ready',
          'threadId': 'fresh',
          'compaction': {'id': 'old-job', 'status': 'completed'},
        };
      await tester.pumpWidget(MaterialApp(home: HomeScreen(model: model)));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      model.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(api.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    }
  });

  testWidgets('Header opens real compression and keeps history and draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(428, 926);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = CompressionApi();
    final model = modelFor(api);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: model,
          builder: (_, _) => HomeScreen(model: model),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Keep this unsent draft');
    await tester.tap(find.byKey(const Key('compress-context-header')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Older details are retrieved'), findsOneWidget);
    await tester.tap(find.byKey(const Key('compress-context-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.requests, hasLength(1));
    expect(api.requests.single['expectedSessionId'], 'old');
    expect(find.text('Writing a short handoff…'), findsOneWidget);
    expect(model.messages.single['id'], 'history');
    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Keep this unsent draft'), findsOneWidget);
    expect(find.text('Steer'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Steer'))
          .onPressed,
      isNull,
    );
    model.chat = {
      'status': 'ready',
      'threadId': 'fresh',
      'compaction': {...api.job, 'target': 'fresh', 'status': 'completed'},
    };
    model.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Fresh'), findsOneWidget);
    expect(
      find.textContaining('Context compressed. Handoff saved'),
      findsOneWidget,
    );
    expect(find.text('~52% left'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  test(
    'A lost response reuses request ID and failed jobs can be retried',
    () async {
      final api = CompressionApi()..loseResponse = true;
      final model = modelFor(api);
      await expectLater(model.compressContext(), throwsException);
      await model.compressContext();
      expect(api.requests[0]['requestId'], api.requests[1]['requestId']);
      model.chat = {
        'status': 'ready',
        'threadId': 'old',
        'compaction': {...api.job, 'status': 'failed'},
      };
      await model.compressContext();
      expect(api.requests[2]['requestId'], isNot(api.requests[1]['requestId']));
      model.dispose();
    },
  );

  testWidgets(
    'A changed thread clears the old meter without waiting a minute',
    (tester) async {
      final model = modelFor(CompressionApi());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: model,
              builder: (_, _) => AppUsageHeader(model: model),
            ),
          ),
        ),
      );
      expect(find.text('~52% left'), findsOneWidget);
      model.chat = {'threadId': 'new', 'status': 'ready'};
      model.notifyListeners();
      await tester.pump();
      expect(find.text('~52% left'), findsNothing);
      model.chat = {
        'threadId': 'new',
        'status': 'ready',
        'context': {'used': 5, 'window': 100},
      };
      model.notifyListeners();
      await tester.pump();
      expect(find.text('~95% left'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
