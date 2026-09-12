import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/app/shell.dart';
import 'package:cortex/remote_ui/bundled.dart';
import 'package:cortex/remote_ui/layout_release.dart';
import 'package:cortex/remote_ui/layout_store.dart';

class LayoutApi extends CortexApi {
  dynamic response = jsonDecode(bundledLayoutJSON);
  @override
  Future<dynamic> call(String method, String path, [Object? data]) async =>
      response;
}

void main() {
  test(
    'Unknown components, missing controls and incompatible releases are rejected',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['schema'] = 2,
        (d) => d['pages']['chat']['children'].removeLast(),
        (d) => d['pages']['chat']['children'].add({
          'type': 'slot',
          'name': 'composer',
        }),
        (d) => d['pages']['space']['children'].add({
          'type': 'WebView',
          'url': 'https://example.com',
        }),
        (d) => d['pages']['userMessage']['width'] = 100,
      ]) {
        final doc = jsonDecode(bundledLayoutJSON) as Map<String, dynamic>;
        change(doc);
        expect(() => LayoutRelease.parse(jsonEncode(doc)), throwsA(anything));
      }
    },
  );
  testWidgets(
    'Remote chat/composer swaps preserve unsent input and the two-tab frame',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = LayoutApi(), model = CortexModel();
      model.paired = true;
      model.account = {
        'account': {'type': 'chatgpt'},
      };
      final remoteModel = CortexModel(api: api)..paired = true;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(model: model)));
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      final doc = jsonDecode(bundledLayoutJSON) as Map<String, dynamic>;
      doc['revision'] = 'test-layout-2';
      doc['pages']['composer']['children'] = [
        {'type': 'slot', 'name': 'actions'},
        {'type': 'slot', 'name': 'images'},
        {'type': 'slot', 'name': 'input'},
      ];
      doc['pages']['userMessage']['radius'] = 4;
      api.response = doc;
      await layouts.refresh(remoteModel, force: true);
      expect(layouts.pending, isNotNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await layouts.refresh(remoteModel, force: true);
      await tester.pumpAndSettle();
      expect(layouts.current.revision, 'test-layout-2');
      expect(find.text('Keep my draft'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(find.byTooltip('Camera or photo library'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.response = {'schema': 999};
      await layouts.refresh(remoteModel, force: true);
      expect(layouts.current.revision, 'test-layout-2');
      await tester.pumpWidget(const SizedBox());
      api.response = jsonDecode(bundledLayoutJSON);
      await layouts.refresh(remoteModel, force: true);
      model.dispose();
      remoteModel.dispose();
    },
  );
}
