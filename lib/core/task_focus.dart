import 'dart:async';
import 'package:flutter/services.dart';
import 'cortex.dart';

DateTime? _focusDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date != null && date.year > 1970 ? date : null;
}

String focusTaskPhase(Map<String, dynamic> task, DateTime now) {
  final status = task['status'] as String? ?? '';
  if (status != 'pending' && status != 'ready') return status;
  final activation =
      _focusDate(task['activateAt']) ??
      _focusDate(task['scheduledStart'])?.subtract(const Duration(minutes: 30));
  if (activation == null) return status;
  return activation.isAfter(now) ? 'pending' : 'ready';
}

bool focusTaskVisibleAt(Map<String, dynamic> task, DateTime now) =>
    switch (focusTaskPhase(task, now)) {
      'ready' || 'active' => true,
      'paused' || 'postponed' => _focusDate(task['startedAt']) != null,
      _ => false,
    };

class TaskFocus {
  TaskFocus({
    required this.api,
    required this.changed,
    required this.canSync,
    this.quietHours,
    this.onCompletionSynced,
  });
  final CortexApi api;
  final void Function()? onCompletionSynced;
  final void Function() changed;
  final bool Function() canSync;
  final Map<String, dynamic>? Function()? quietHours;
  Map<String, dynamic>? current, openRequest;
  List<Map<String, dynamic>> tasks = [], plannedTasks = [];
  String? plannedDate, plannedError;
  String permission = 'unknown';
  String liveState = 'none';
  bool liveEnabled = false, liveActive = false, syncing = false;
  int notificationCount = 0;
  String? scheduledThrough, error;
  bool pending = false, _disposed = false;
  DateTime? checked;
  Future<void>? _work;
  bool _syncAgain = false;
  List<Map<String, dynamic>> get visibleTasks {
    final now = DateTime.now();
    return (tasks.isEmpty && current != null ? [current!] : tasks)
        .where((f) => focusTaskVisibleAt(f, now))
        .map((f) => {...f, 'status': focusTaskPhase(f, now)})
        .toList();
  }

  bool get visible => visibleTasks.isNotEmpty;
  bool get active => current?['status'] == 'active';

  void _receive(Map state) {
    permission = state['permission'] as String? ?? 'unavailable';
    liveEnabled = state['liveEnabled'] == true;
    liveActive = state['liveActive'] == true;
    liveState =
        state['liveState'] as String? ?? (liveActive ? 'active' : 'missing');
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
          if (input['action'] == 'complete') onCompletionSynced?.call();
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
              [
                'pending',
                'ready',
                'active',
                'paused',
                'postponed',
              ].contains(f['status']),
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
        final tracked = ['pending', 'ready', 'active'].contains(item['status']);
        final perTask =
            (result['taskNotifications'] as Map?)?[item['id']] as Map?;
        final count = perTask?['count'] as int? ?? notificationCount;
        final coverage = result['liveCoveredIDs'] as List?;
        final covered =
            coverage?.contains(item['id']) ?? (liveActive && count > 0);
        final state = !tracked
            ? 'stopped'
            : covered
            ? 'scheduled'
            : count > 0
            ? 'notifications_only'
            : (permission == 'authorized' ? 'failed' : 'needs_permission');
        await api.call('POST', '/v1/focus/ack', {
          'id': item['id'],
          'revision': item['revision'],
          'status': state,
          'scheduledThrough': perTask?['through'] ?? scheduledThrough ?? '',
        });
      }
      await refreshPlanned();
      checked = DateTime.now();
      error = conflict;
    } on MissingPluginException {
      permission = 'unavailable';
    } catch (_) {
      error = pending
          ? 'Saved on this phone. Changes will sync when Cortex can connect.'
          : 'Task check-ins could not refresh. Saved reminders remain on this phone.';
    } finally {
      syncing = false;
      if (!_disposed) changed();
    }
  }

  Future<void> refreshPlanned() async {
    try {
      final now = DateTime.now();
      final response =
          await api.call(
                'GET',
                '/v1/focus/planned?date=${day(now)}&timezoneOffset=${now.timeZoneOffset.inMinutes}',
              )
              as Map;
      plannedTasks = (response['tasks'] as List? ?? [])
          .whereType<Map>()
          .map((f) => Map<String, dynamic>.from(f))
          .toList();
      plannedDate = day(now);
      plannedError = null;
    } catch (_) {
      plannedError =
          'Today’s calendar tasks could not refresh. Pull down to retry.';
    }
    if (!_disposed) changed();
  }

  List<Map<String, dynamic>> plannedForToday([DateTime? at]) {
    final now = at ?? DateTime.now();
    final rows = <String, Map<String, dynamic>>{};
    if (plannedDate == day(now)) {
      for (final f in plannedTasks) {
        rows[f['id'] as String] = f;
      }
    }
    for (final f in tasks) {
      if (f['preview'] == true || f['status'] == 'cancelled') continue;
      final start = _focusDate(f['scheduledStart'])?.toLocal();
      if (start == null || day(start) != day(now)) continue;
      final existing = rows[f['id']];
      if (existing == null &&
          plannedDate == day(now) &&
          (f['calendarKey'] as String? ?? '').isNotEmpty) {
        continue;
      }
      if (existing == null ||
          (f['revision'] as num? ?? 0) >= (existing['revision'] as num? ?? 0)) {
        rows[f['id'] as String] = f;
      }
    }
    return rows.values
        .map((f) => {...f, 'status': focusTaskPhase(f, now)})
        .toList()
      ..sort(
        (a, b) => (a['scheduledStart'] as String).compareTo(
          b['scheduledStart'] as String,
        ),
      );
  }

  Future<void> actPlanned(
    Map<String, dynamic> item,
    String command, {
    int minutes = 15,
    String? reason,
  }) async {
    if (tasks.any((f) => f['id'] == item['id'])) {
      await act(
        command,
        id: item['id'] as String,
        minutes: minutes,
        reason: reason,
      );
      return;
    }
    // Older occurrences can be shown without registering any notification.
    // Materialize only the exact occurrence the owner acts on.
    await api.call('POST', '/v1/focus/actions', {
      'action': command,
      if ((item['revision'] as num? ?? 0) > 0)
        'id': item['id']
      else
        'calendarKey': item['calendarKey'],
      'expectedRevision': item['revision'] ?? 0,
      'requestId': newId(),
      'timezoneOffset': DateTime.now().timeZoneOffset.inMinutes,
      'minutes': minutes,
      'reason': ?reason,
    });
    await sync();
    await refreshPlanned();
  }

  Future<void> preview() async {
    await _native('focusPreview');
    await sync();
  }

  Future<void> restore() async {
    // The cached task card can be restored before any network request succeeds.
    _receive(await _native('focusRestore'));
    if (!_disposed) changed();
    unawaited(sync(afterAction: true));
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
