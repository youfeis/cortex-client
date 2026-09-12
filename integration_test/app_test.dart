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
    expect(find.text('Connect Codex to start chatting.'), findsOneWidget);
    await binding.takeScreenshot('chat');
    await tester.enterText(
      find.byType(TextField),
      'A draft to keep while I check my progress',
    );
    await tester.tap(find.text('My space'));
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('my-space');
    await tester.tap(find.text('Fitness').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Today’s energy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('fitness');
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Time\nmanagement'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('I’m awake · arrange my day'), findsOneWidget);
    await binding.takeScreenshot('time');
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
