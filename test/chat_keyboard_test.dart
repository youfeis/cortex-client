import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/app/shell.dart';
import 'package:cortex/app/ui.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/chat/chat_screen.dart';

void main() {
  testWidgets('Keyboard opening and closing anchor the latest chat after layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final model = CortexModel()
      ..paired = true
      ..account = {
        'account': {'type': 'chatgpt'},
      }
      ..messages = [
        for (var i = 0; i < 24; i++)
          {
            'id': '$i',
            'role': i.isEven ? 'assistant' : 'user',
            'images': [],
            'text':
                'Message $i. ${'A longer message that wraps onto more lines. ' * (i % 4 + 1)}',
          },
      ];
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => KeyboardDismissBar(child: child!),
        home: HomeScreen(model: model),
      ),
    );
    final state = tester.state<ChatScreenState>(find.byType(ChatScreen));
    await tester.pumpAndSettle();
    expect(state.scroll.position.extentBefore, closeTo(0, 1));
    await tester.enterText(find.byType(TextField), 'Keep this unsent draft');
    for (final inset in [120.0, 240.0, 300.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(state.scroll.position.extentBefore, closeTo(0, 1));
    expect(find.text('Hide keyboard'), findsOneWidget);

    // Normal reading of older messages is not overridden once the keyboard settles.
    state.scroll.jumpTo(800);
    await tester.pumpAndSettle();
    expect(state.scroll.offset, 800);
    await tester.tap(find.text('Hide keyboard'));
    for (final inset in [200.0, 90.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(state.scroll.position.extentBefore, closeTo(0, 1));
    expect(state.scroll.position.outOfRange, isFalse);
    expect(state.draft.text, 'Keep this unsent draft');
    expect(find.text('Hide keyboard'), findsNothing);

    // Removing the screen mid-transition must cancel pending work safely.
    state.focus.requestFocus();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    model.dispose();
  });
}
