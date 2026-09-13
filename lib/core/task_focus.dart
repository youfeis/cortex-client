import 'dart:async';
import 'package:flutter/services.dart';
import 'cortex.dart';

class TaskFocus {
  TaskFocus({required this.api, required this.changed, required this.canSync});
  final CortexApi api;
  final void Function() changed;
  final bool Function() canSync;
  Map<String, dynamic>? current;
  String permission = 'unknown';
  bool liveEnabled = false, liveActive = false, syncing = false;
  int notificationCount = 0;
  String? scheduledThrough, error;
  bool pending = false, _disposed = false;
  DateTime? checked;
  Future<void>? _work;

  bool get visible =>
      current != null && ['active', 'paused'].contains(current!['status']);
  bool get active => current?['status'] == 'active';

  void _receive(Map state) {
    permission = state['permission'] as String? ?? 'unavailable';
    liveEnabled = state['liveEnabled'] == true;
    liveActive = state['liveActive'] == true;
    notificationCount = state['notificationCount'] as int? ?? 0;
    scheduledThrough = state['scheduledThrough'] as String?;
    current = state['focus'] is Map
        ? Map<String, dynamic>.from(state['focus'] as Map)
        : null;
    pending = (state['pending'] as List? ?? []).isNotEmpty;
  }

  Future<Map> _native(String method, [Map<String, dynamic>? args]) async =>
      await native.invokeMethod<Map>(method, args) ?? {};

  Future<void> sync({bool requestPermission = false}) {
    if (_disposed) return Future.value();
    if (_work != null) return _work!;
    final work = _sync(requestPermission);
    _work = work;
    return work.whenComplete(() => _work = null);
  }

  Future<void> _sync(bool requestPermission) async {
    syncing = true;
    String? conflict;
    try {
      final local = await _native(
        requestPermission ? 'focusPermission' : 'focusStatus',
      );
      _receive(local);
      if (!canSync()) return;
      for (final raw in local['pending'] as List? ?? []) {
        final action = Map<String, dynamic>.from(raw as Map);
        var discarded = false;
        try {
          await api.call('POST', '/v1/focus/actions', action);
        } on ApiException catch (e) {
          if (e.status != 409 && e.status != 400) rethrow;
          discarded = true;
          conflict =
              'That task changed. Check the current task before trying again.';
        }
        await _native('focusAcknowledge', {
          'requestId': action['requestId'],
          'discarded': discarded,
        });
      }
      final response = await api.call('GET', '/v1/focus') as Map;
      final result = await _native('focusApply', {'focus': response['focus']});
      _receive(result);
      if (!pending && current != null) {
        final state = !active
            ? 'stopped'
            : notificationCount > 0
            ? (liveActive ? 'scheduled' : 'notifications_only')
            : (permission == 'authorized' ? 'failed' : 'needs_permission');
        await api.call('POST', '/v1/focus/ack', {
          'id': current!['id'],
          'revision': current!['revision'],
          'status': state,
          'scheduledThrough': scheduledThrough ?? '',
        });
      }
      checked = DateTime.now();
      error = conflict;
    } on MissingPluginException {
      permission = 'unavailable';
    } catch (_) {
      error = pending
          ? 'Saved on this phone. The server will catch up when connected.'
          : 'Task check-ins could not refresh. Previously scheduled reminders stay on this phone.';
    } finally {
      syncing = false;
      if (!_disposed) changed();
    }
  }

  Future<void> start({
    required String title,
    String? taskId,
    DateTime? expectedEnd,
    int minutes = 25,
  }) async {
    await sync(
      requestPermission:
          permission == 'notDetermined' || permission == 'unknown',
    );
    final now = DateTime.now();
    final end = expectedEnd != null && expectedEnd.isAfter(now)
        ? expectedEnd
        : now.add(Duration(minutes: minutes.clamp(1, 480)));
    await api.call('POST', '/v1/focus/actions', {
      'action': 'start',
      'expectedRevision': current?['revision'] ?? 0,
      'requestId': newId(),
      'title': String.fromCharCodes(title.runes.take(160)),
      'taskId': taskId ?? '',
      'expectedEnd': end.toUtc().toIso8601String(),
      'intervalMinutes': 15,
    });
    await sync();
  }

  Future<void> act(String action) async {
    await _work;
    if (current == null) return;
    // Persist the action and change notifications before attempting the network.
    final result = await _native('focusAction', {
      'id': current!['id'],
      'expectedRevision': current!['revision'],
      'action': action,
    });
    _receive(result);
    if (!_disposed) changed();
    await sync();
  }

  void dispose() => _disposed = true;
}
