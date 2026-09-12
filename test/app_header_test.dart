import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/app/usage_header.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/core/quota.dart';
import 'package:cortex/app/shell.dart';

Map<String, dynamic> limits() => {
  'rateLimitsByLimitId': {
    'spark': {
      'limitName': 'Codex Spark',
      'primary': {'usedPercent': 0, 'windowDurationMins': 10080},
    },
    'codex': {
      'limitName': 'Custom display name',
      'primary': {'usedPercent': 50, 'windowDurationMins': 300},
      'secondary': {
        'usedPercent': 22,
        'windowDurationMins': 10080,
        'resetsAt':
            DateTime.now()
                .add(const Duration(days: 3))
                .millisecondsSinceEpoch ~/
            1000,
      },
    },
  },
};
void main() {
  testWidgets('Context stays visible through heartbeats and updates lazily', (
    tester,
  ) async {
    final model = CortexModel()
      ..account = {
        'account': {'type': 'chatgpt'},
      };
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
    double? progress() => tester
        .widget<LinearProgressIndicator>(
          find.byKey(const Key('main-context-progress')),
        )
        .value;
    expect(progress(), 0);

    // The first usable sample appears immediately, even after an empty start.
    model.chat = {
      'status': 'ready',
      'context': {'used': 25, 'window': 100},
    };
    model.notifyListeners();
    await tester.pump();
    expect(progress(), .75);

    model.chat = {
      'status': 'working',
      'context': {'used': 40, 'window': 100},
    };
    model.notifyListeners();
    await tester.pump(const Duration(seconds: 30));
    expect(progress(), .75);
    expect(find.text('● Working'), findsOneWidget);

    // The stream omits context; a later snapshot provides a newer estimate.
    model.chat = {'status': 'ready'};
    model.notifyListeners();
    await tester.pump();
    expect(progress(), .75);
    expect(find.text('~75% left'), findsOneWidget);
    model.chat = {
      'status': 'ready',
      'context': {'used': 45, 'window': 100},
    };
    model.notifyListeners();
    await tester.pump(const Duration(seconds: 29));
    expect(progress(), .75);
    await tester.pump(const Duration(seconds: 1));
    expect(progress(), .55);

    model.chat = {'status': 'ready', 'context': null};
    model.notifyListeners();
    await tester.pump(const Duration(minutes: 1));
    expect(progress(), .55);
    expect(find.text('~55% left'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  test('Weekly quota selects the Codex ID and seven-day window only', () {
    expect(codexWeeklyQuota(limits())!.remaining, 78);
    expect(
      codexWeeklyQuota({
        'rateLimits': {
          'limitId': 'spark',
          'primary': {'usedPercent': 0, 'windowDurationMins': 10080},
        },
      }),
      isNull,
    );
    expect(
      codexWeeklyQuota({
        'rateLimits': {
          'primary': {'usedPercent': 5, 'windowDurationMins': 300},
        },
      }),
      isNull,
    );
    expect(
      codexWeeklyQuota({
        'rateLimits': {
          'secondary': {'usedPercent': 5, 'windowDurationMins': 10080},
        },
      })!.remaining,
      95,
    );
  });
  testWidgets('Two bars replace the chat heading and fit a narrow iPhone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = CortexModel()
      ..account = {
        'account': {'type': 'chatgpt'},
      }
      ..chat = {
        'status': 'working',
        'context': {'used': 25000, 'window': 100000},
      }
      ..quota = limits();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(model: model)));
    expect(
      find.text('Chat'),
      findsOneWidget,
      reason: 'Only the bottom tab remains',
    );
    expect(find.text('A little space to think.'), findsNothing);
    expect(find.byTooltip('Chat controls explained'), findsNothing);
    expect(find.text('Codex weekly'), findsOneWidget);
    expect(find.textContaining('Spark'), findsNothing);
    expect(find.text('● Working'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('main-context-progress')),
          )
          .value,
      .75,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('codex-weekly-progress')),
          )
          .value,
      .78,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  testWidgets('Unknown and expired quota never displays a full remaining bar', (
    tester,
  ) async {
    final model = CortexModel()
      ..account = {
        'account': {'type': 'chatgpt'},
      }
      ..quota = {
        'rateLimits': {
          'secondary': {
            'usedPercent': 0,
            'windowDurationMins': 10080,
            'resetsAt': 1,
          },
        },
      };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUsageHeader(model: model)),
      ),
    );
    expect(find.text('—'), findsNWidgets(2));
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('codex-weekly-progress')),
          )
          .value,
      0,
    );
    expect(find.textContaining('100%'), findsNothing);
    model.dispose();
  });
}
