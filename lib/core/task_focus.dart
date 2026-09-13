import 'dart:async';
import 'package:flutter/services.dart';
import 'cortex.dart';

class TaskFocus {
  TaskFocus({
    required this.api,
    required this.changed,
    required this.canSync,
    this.quietHours,
  });
  final CortexApi api;
  final void Function() changed;
  final bool Function() canSync;
  final Map<String, dynamic>? Function()? quietHours;
  Map<String, dynamic>? current, openRequest;
  List<Map<String, dynamic>> tasks = [];
  String permission = 'unknown';
  bool liveEnabled = false, liveActive = false, syncing = false;
  int notificationCount = 0;
  String? scheduledThrough, error;
  bool pending = false, _disposed = false;
  DateTime? checked;
  Future<void>? _work;
  bool _syncAgain = false;
  List<Map<String, dynamic>> get visibleTasks =>
      (tasks.isEmpty && current != null ? [current!] : tasks)
          .where(
            (f) => [
              'ready',
              'active',
              'paused',
              'postponed',
            ].contains(f['status']),
          )
          .toList();
  bool get visible => visibleTasks.isNotEmpty;
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
    tasks = (state['focuses'] as List? ?? (current == null ? [] : [current]))
        .whereType<Map>()
        .map((f) => Map<String, dynamic>.from(f))
        .toList();
    openRequest = state['openRequest'] is Map
        ? Map<String, dynamic>.from(state['openRequest'] as Map)
        : null;
    pending = (state['pending'] as List? ?? []).isNotEmpty;
  }

  Future<Map> _native(String method, [Map<String, dynamic>? args]) async =>
      await native.invokeMethod<Map>(method, args) ?? {};
  Future<void> sync({
    bool requestPermission = false,
    bool afterAction = false,
  }) {
    if (_disposed) return Future.value();
    if (_work != null) {
      if (afterAction) _syncAgain = true;
      return _work!;
    }
    final work = _sync(requestPermission);
    _work = work;
    return work.whenComplete(() {
      _work = null;
      if (_syncAgain && !_disposed) {
        _syncAgain = false;
        unawaited(sync());
      }
    });
  }

  Future<void> _sync(bool requestPermission) async {
    syncing = true;
    String? conflict;
    try {
      var local = await _native(
        requestPermission ? 'focusPermission' : 'focusStatus',
      );
      _receive(local);
      if (!canSync()) return;
      final discardedTasks = <String>{};
      for (final raw in local['pending'] as List? ?? []) {
        final input = Map<String, dynamic>.from(raw as Map);
        if (discardedTasks.contains(input['id'])) continue;
        var discarded = false;
        try {
          await api.call('POST', '/v1/focus/actions', input);
        } on ApiException catch (e) {
          if (e.status != 409 && e.status != 400) rethrow;
          discarded = true;
          discardedTasks.add(input['id'] as String);
          conflict = 'That task changed. Check it before trying again.';
        }
        await _native('focusAcknowledge', {
          'requestId': input['requestId'],
          'discarded': discarded,
        });
      }
      var response = await api.call('GET', '/v1/focus') as Map;
      final preview = local['previewRequest'];
      if (preview is Map) {
        final all =
            response['focuses'] as List? ??
            (response['focus'] == null ? [] : [response['focus']]);
        if (!all.whereType<Map>().any(
          (f) =>
              f['preview'] != true &&
              ['ready', 'active', 'paused', 'postponed'].contains(f['status']),
        )) {
          local = await _native('focusPermission');
          final at = DateTime.parse(preview['at'] as String);
          for (final (key, title, mode, minutes) in [
            ('first', 'Preview · Read for 25 minutes', 'prepare', 25),
            ('second', 'Preview · Laundry timer', 'start', 40),
          ]) {
            await api.call('POST', '/v1/focus/actions', {
              'action': mode,
              'requestId': preview[key],
              'expectedRevision': 0,
              'title': title,
              'preview': true,
              'minutes': minutes,
              'actionAt': preview['at'],
              'scheduledStart': preview['at'],
              'expectedEnd': at
                  .add(Duration(minutes: minutes))
                  .toUtc()
                  .toIso8601String(),
              'timezoneOffset': preview['timezoneOffset'],
            });
          }
          response = await api.call('GET', '/v1/focus') as Map;
        }
        await _native('focusPreviewAcknowledge');
      }
      final result = await _native('focusApply', {
        'focus': response['focus'],
        'quietHours': quietHours?.call(),
        if (response.containsKey('focuses')) 'focuses': response['focuses'],
      });
      _receive(result);
      final pendingIDs = (result['pending'] as List? ?? [])
          .whereType<Map>()
          .map((f) => f['id'])
          .toSet();
      for (final item in tasks) {
        if (pendingIDs.contains(item['id'])) continue;
        final tracked = ['ready', 'active'].contains(item['status']);
        final perTask =
            (result['taskNotifications'] as Map?)?[item['id']] as Map?;
        final count = perTask?['count'] as int? ?? notificationCount;
        final state = !tracked
            ? 'stopped'
            : count > 0
            ? (liveActive ? 'scheduled' : 'notifications_only')
            : (permission == 'authorized' ? 'failed' : 'needs_permission');
        await api.call('POST', '/v1/focus/ack', {
          'id': item['id'],
          'revision': item['revision'],
          'status': state,
          'scheduledThrough': perTask?['through'] ?? scheduledThrough ?? '',
        });
      }
      checked = DateTime.now();
      error = conflict;
    } on MissingPluginException {
      permission = 'unavailable';
    } catch (_) {
      error = pending
          ? 'Saved on this phone. Planning will catch up when Cortex can connect.'
          : 'Task check-ins could not refresh. Saved reminders remain on this phone.';
    } finally {
      syncing = false;
      if (!_disposed) changed();
    }
  }

  Future<void> preview() async {
    await _native('focusPreview');
    await sync();
  }

  Future<void> acknowledgeOpen() async {
    openRequest = null;
    await _native('focusOpenAcknowledge');
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
      'expectedRevision': 0,
      'requestId': newId(),
      'title': String.fromCharCodes(title.runes.take(160)),
      'taskId': taskId ?? '',
      'expectedEnd': end.toUtc().toIso8601String(),
      'minutes': minutes.clamp(1, 480),
      'intervalMinutes': 15,
      'timezoneOffset': now.timeZoneOffset.inMinutes,
    });
    await sync();
  }

  Future<void> act(
    String action, {
    String? id,
    int minutes = 15,
    String? reason,
  }) async {
    final f = id == null
        ? current
        : tasks.where((f) => f['id'] == id).firstOrNull;
    if (f == null) return;
    final result = await _native('focusAction', {
      'id': f['id'],
      'expectedRevision': f['revision'],
      'action': action,
      'minutes': minutes,
      'reason': ?reason,
    });
    _receive(result);
    if (!_disposed) changed();
    if (_work != null) {
      _syncAgain = true;
      return;
    }
    await sync();
  }

  void dispose() => _disposed = true;
}
