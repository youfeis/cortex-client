import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/cortex.dart';
import 'package:cortex/screens.dart';

class LoginApi extends CortexApi {
  final calls = <String>[];
  Completer<Map<String, dynamic>>? pending;
  int counter = 0;
  Map<String, dynamic> response(int id) => {
    'loginId': 'example-$id',
    'userCode': 'EXAMPLE-$id',
    'verificationUrl': 'https://auth.openai.com/codex/device',
  };
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async {
    calls.add('$path:${data is Map ? data['loginId'] ?? '' : ''}');
    if (path == '/v1/account/login') {
      return pending == null ? response(++counter) : pending!.future;
    }
    if (path == '/v1/account') return {'account': null};
    return {};
  }
}

void main() {
  testWidgets(
    'Login recovery explains account setup and replaces the previous code',
    (tester) async {
      final api = LoginApi();
      final model = CortexModel(api: api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LoginSheet(model: model)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('One-time ChatGPT setup'), findsOneWidget);
      expect(find.text('EXAMPLE-1'), findsOneWidget);
      await tester.ensureVisible(find.text('Get a new login code'));
      await tester.tap(find.text('Get a new login code'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('/v1/account/cancel:example-1'));
      expect(find.text('EXAMPLE-2'), findsOneWidget);
      expect(find.text('EXAMPLE-1'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      model.dispose();
    },
  );
  testWidgets(
    'Closing while a login code is loading cancels the late attempt',
    (tester) async {
      final api = LoginApi()..pending = Completer<Map<String, dynamic>>();
      final model = CortexModel(api: api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LoginSheet(model: model)),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      api.pending!.complete(api.response(1));
      await tester.pump();
      expect(api.calls, contains('/v1/account/cancel:example-1'));
      expect(tester.takeException(), isNull);
      model.dispose();
    },
  );
}
