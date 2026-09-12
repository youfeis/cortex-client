import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/cortex.dart';
import 'package:cortex/screens.dart';
import 'package:cortex/ui.dart';

class FakeModel extends CortexModel {
  bool steered = false;
  bool failSend = false;
  FakeModel() {
    paired = true;
    account = {
      'account': {'type': 'chatgpt'},
    };
  }
  @override
  Future<void> send(
    String text,
    List<String> images, {
    bool steer = false,
  }) async {
    steered = steer;
    if (failSend) {
      throw ApiException(503, 'Connection lost. Try again.');
    }
    chat = {'status': 'thinking', 'turnId': 'turn-1'};
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    chat = {'status': 'stopped'};
    notifyListeners();
  }
}

class ClosingApi extends CortexApi {
  final finished = Completer<void>();
  @override
  Stream<Map<String, dynamic>> events() async* {
    await finished.future;
    throw ApiException(503, 'Connection closed');
  }
}

void main() {
  test(
    'Closing the app cancels a late stream error without updating disposed state',
    () async {
      final api = ClosingApi();
      final model = CortexModel(api: api)..paired = true;
      model.startStream();
      await Future<void>.delayed(Duration.zero);
      model.dispose();
      api.finished.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
  );
  test('Context stays unknown until Codex reports a window', () {
    expect(contextLabel(null), contains('waiting'));
    expect(
      contextLabel({'used': 25000, 'window': 100000}),
      '~75% context left',
    );
    expect(
      contextLabel({'used': 110000, 'window': 100000}),
      '~0% context left',
    );
  });
  testWidgets(
    'Failed send keeps draft, steering works, stop keeps next draft',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = FakeModel();
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: model,
            builder: (context, _) => HomeScreen(model: model),
          ),
        ),
      );
      model.failSend = true;
      await tester.enterText(find.byType(TextField), 'Keep this message');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(find.text('Keep this message'), findsOneWidget);
      expect(find.text('Connection lost. Try again.'), findsOneWidget);
      model.failSend = false;
      model.chat = {'status': 'working', 'turnId': 'active'};
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: model,
            builder: (context, _) => HomeScreen(model: model),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Steer'));
      await tester.pump();
      expect(model.steered, isTrue);
      await tester.enterText(find.byType(TextField), 'My next thought');
      await tester.tap(find.byTooltip('Stop reply'));
      await tester.pump();
      expect(find.text('My next thought'), findsOneWidget);
      await tester.tap(find.text('My space'));
      await tester.pump();
      await tester.tap(find.text('Chat').last);
      await tester.pump();
      expect(find.text('My next thought'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
