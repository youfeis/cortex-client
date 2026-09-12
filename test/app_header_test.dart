import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/app_header.dart';
import 'package:cortex/cortex.dart';
import 'package:cortex/quota.dart';
import 'package:cortex/screens.dart';

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
