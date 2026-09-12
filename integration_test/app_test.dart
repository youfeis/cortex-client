import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cortex/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Pair a real simulator key and inspect production screens', (
    tester,
  ) async {
    app.main();
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (finder.evaluate().isNotEmpty) {
          return;
        }
      }
      fail('Screen did not become ready');
    }

    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byKey(const Key('pairing-code')).evaluate().isNotEmpty ||
          find.text('My space').evaluate().isNotEmpty) {
        break;
      }
    }
    if (find.byKey(const Key('pairing-code')).evaluate().isNotEmpty) {
      const code = String.fromEnvironment('CORTEX_PAIR_CODE');
      expect(
        code.isNotEmpty,
        isTrue,
        reason:
            'Supply a private one-time pairing code with --dart-define-from-file.',
      );
      await tester.enterText(find.byKey(const Key('pairing-code')), code);
      await tester.tap(find.byKey(const Key('pair-device')));
    }
    await waitFor(find.text('My space'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Camera or photo library'), findsOneWidget);
    await tester.pumpAndSettle();
    await waitFor(find.textContaining('Resets '));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('chat');
    await tester.enterText(
      find.byType(TextField),
      'A draft to keep while I check my progress',
    );
    await tester.pump(const Duration(seconds: 1));
    if (find.text('Hide keyboard').evaluate().isNotEmpty) {
      await binding.takeScreenshot('keyboard');
      await tester.tap(find.text('Hide keyboard'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('My space'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('my-space');
    await tester.tap(find.text('Fitness').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Today’s energy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('fitness');
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.text('See the bigger picture.'), findsOneWidget);
    await binding.takeScreenshot('trends-weight');
    await tester.scrollUntilVisible(
      find.text('Blood glucose'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('trends-glucose');
    await tester.scrollUntilVisible(
      find.text('Blood pressure'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byTooltip('Previous blood pressure reading'),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('trends-bp');
    await tester.tap(find.byTooltip('Previous blood pressure reading'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Time\nmanagement'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('To-do list'), findsOneWidget);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('time');
    await tester.scrollUntilVisible(
      find.byTooltip('Choose calendars'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byTooltip('Choose calendars'));
    await tester.pumpAndSettle();
    expect(find.text('Personal, work, all together.'), findsOneWidget);
    await binding.takeScreenshot('calendars');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Chat').last);
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('A draft to keep while I check my progress'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('Camera or photo library'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Photo library'), findsOneWidget);
    await tester.tapAt(const Offset(20, 160));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
