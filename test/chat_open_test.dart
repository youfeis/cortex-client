import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/app/shell.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/chat/chat_screen.dart';

List<Map<String, dynamic>> history() => [
  for (var i = 0; i < 180; i++)
    {
      'id': 'message-$i',
      'role': i.isEven ? 'assistant' : 'user',
      'images': [],
      'text': i == 179
          ? 'Latest reply at the end.'
          : 'Message $i. ${'A paragraph with variable height. ' * (i % 6 + 1)}',
    },
];

void main() {
  late CortexModel model;
  setUp(() {
    model = CortexModel()
      ..paired = true
      ..account = {
        'account': {'type': 'chatgpt'},
      }
      ..messages = history();
  });
  tearDown(() => model.dispose());

  Future<ChatScreenState> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: model,
          builder: (_, _) => HomeScreen(model: model),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<ChatScreenState>(find.byType(ChatScreen));
  }

  testWidgets('Opening a long, already loaded conversation shows its end', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Latest reply at the end.').hitTestable(), findsOneWidget);
  });

  testWidgets('Resume and returning to Chat show the end and keep the draft', (
    tester,
  ) async {
    final state = await open(tester);
    state.draft.text = 'An unsent thought';
    // Read several screens back, regardless of the list's axis direction.
    final reverse = state.scroll.position.axisDirection == AxisDirection.up;
    state.scroll.jumpTo(reverse ? 1500 : 0);
    await tester.pumpAndSettle();
    expect(find.text('Latest reply at the end.').hitTestable(), findsNothing);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('Latest reply at the end.').hitTestable(), findsOneWidget);
    expect(state.draft.text, 'An unsent thought');

    state.scroll.jumpTo(reverse ? 1500 : 0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('My space').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat').last);
    await tester.pumpAndSettle();
    expect(find.text('Latest reply at the end.').hitTestable(), findsOneWidget);
    expect(state.draft.text, 'An unsent thought');
  });

  testWidgets('Delayed history and long streaming replies remain at the end', (
    tester,
  ) async {
    model.messages = [];
    final state = await open(tester);
    model.messages = history();
    model.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Latest reply at the end.').hitTestable(), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      model.chat = {
        'status': 'replying',
        'text': '${'Streaming paragraph.\n\n' * (i * 20)}Stream end $i',
      };
      model.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Stream end $i').hitTestable(), findsOneWidget);
    }
    // Routine status/Health refreshes should not pull someone away from history.
    state.scroll.jumpTo(1500);
    await tester.pumpAndSettle();
    final before = state.scroll.offset;
    model.notifyListeners();
    await tester.pumpAndSettle();
    expect(state.scroll.offset, closeTo(before, .5));
    expect(find.text('Stream end 3').hitTestable(), findsNothing);
  });
}
