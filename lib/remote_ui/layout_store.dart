import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/cortex.dart';
import 'bundled.dart';
import 'layout_release.dart';

final layouts = LayoutStore();

class LayoutStore extends ChangeNotifier {
  LayoutRelease current = LayoutRelease.parse(bundledLayoutJSON);
  LayoutRelease? pending;
  bool _loaded = false, _fetching = false;
  DateTime? _lastCheck;
  String source = 'Included with app';
  String? error;
  bool get canApply =>
      FocusManager.instance.primaryFocus == null ||
      FocusManager.instance.primaryFocus is FocusScopeNode;

  Future<void> refresh(CortexModel model, {bool force = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_loaded) {
        _loaded = true;
        final cached = prefs.getString('layout.lastGood.v1');
        if (cached != null) {
          try {
            current = LayoutRelease.parse(cached);
            source = 'Saved on iPhone';
            notifyListeners();
          } catch (_) {
            await prefs.remove('layout.lastGood.v1');
          }
        }
      }
      if (pending != null && canApply && !model.busy) {
        await _apply(pending!, prefs);
      }
      if (!force &&
          _lastCheck != null &&
          DateTime.now().difference(_lastCheck!) < const Duration(minutes: 3)) {
        return;
      }
      _lastCheck = DateTime.now();
      final response = await model.api.call('GET', '/v1/ui');
      final release = LayoutRelease.parse(jsonEncode(response));
      error = null;
      if (release.revision == current.revision &&
          jsonEncode(release.document) == jsonEncode(current.document)) {
        return;
      }
      // Do not rearrange the screen under an active input or streaming answer.
      if (!canApply || model.busy) {
        pending = release;
        return;
      }
      await _apply(release, prefs);
    } catch (_) {
      error = 'Using the saved layout';
    } finally {
      _fetching = false;
    }
  }

  Future<void> _apply(LayoutRelease release, SharedPreferences prefs) async {
    await prefs.setString('layout.lastGood.v1', jsonEncode(release.document));
    current = release;
    pending = null;
    source = 'Updated from Cortex';
    notifyListeners();
  }
}
