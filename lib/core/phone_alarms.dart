import 'dart:async';
import 'package:flutter/services.dart';
import 'cortex.dart';

class PhoneAlarms {
  PhoneAlarms({
    required this.api,
    required this.changed,
    required this.canSync,
  });
  final CortexApi api;
  final void Function() changed;
  final bool Function() canSync;
  String permission = 'unknown';
  String? error;
  List<Map<String, dynamic>> items = [];
  bool syncing = false, _disposed = false;
  DateTime? checked;

  Future<void> sync({bool requestPermission = false}) async {
    if (_disposed || syncing || !canSync()) return;
    syncing = true;
    try {
      final status = Map<String, dynamic>.from(
        await native.invokeMethod<Map>(
              requestPermission ? 'alarmPermission' : 'alarmStatus',
            ) ??
            {},
      );
      permission = status['permission'] as String? ?? 'unavailable';
      await api.call('POST', '/v1/alarms/device', {
        'permission': permission,
        'scheduledIds': status['scheduledIds'] ?? [],
      });
      final response = await api.call('GET', '/v1/alarms') as Map;
      items = (response['alarms'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      for (final alarm in items) {
        if (_disposed || !canSync()) break;
        if (alarm['status'] != 'pending' &&
            !(alarm['status'] == 'needs_permission' &&
                permission == 'authorized')) {
          continue;
        }
        Map<String, dynamic> result;
        try {
          result = Map<String, dynamic>.from(
            await native.invokeMethod<Map>('alarmApply', alarm) ?? {},
          );
        } on PlatformException {
          result = {
            'status': 'failed',
            'error':
                'The iPhone could not complete this request. Ask Cortex to retry.',
          };
        }
        if (_disposed) break;
        // If the ACK is lost, the native UUID/revision ledger makes the retry safe.
        await api.call('POST', '/v1/alarms/${alarm['id']}/ack', {
          'revision': alarm['revision'],
          'status': result['status'],
          'error': result['error'] ?? '',
        });
        alarm['status'] = result['status'];
        alarm['error'] = result['error'];
        if (result['status'] == 'needs_permission') permission = 'denied';
      }
      checked = DateTime.now();
      error = null;
    } on MissingPluginException {
      permission = 'unavailable';
    } catch (_) {
      error =
          'Alarm sync will retry. Waiting requests are not yet confirmed on this phone.';
    } finally {
      syncing = false;
      if (!_disposed) changed();
    }
  }

  void dispose() => _disposed = true;
}

String alarmTime(Map<String, dynamic> alarm) {
  final spec = alarm['spec'] as Map? ?? {};
  final at = DateTime.tryParse(spec['at'] as String? ?? '');
  if (at != null) {
    final date = at.toLocal();
    return '${date.day}/${date.month} · ${clock(date.hour * 60 + date.minute)}';
  }
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final days = (spec['weekdays'] as List? ?? [])
      .whereType<int>()
      .where((v) => v >= 1 && v <= 7)
      .map((v) => names[v - 1])
      .join(', ');
  return '$days · ${clock((spec['hour'] as int? ?? 0) * 60 + (spec['minute'] as int? ?? 0))}';
}

String alarmStatusLabel(String? status) => switch (status) {
  'scheduled' => 'Set on this iPhone',
  'cancelled' => 'Cancelled on this iPhone',
  'needs_permission' => 'Alarm permission needed',
  'failed' => 'Could not set or change alarm',
  'expired' => 'Time passed · not scheduled',
  'ended' => 'Ended or removed on iPhone',
  _ => 'Waiting for phone',
};
