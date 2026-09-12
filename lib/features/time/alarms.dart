import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../core/phone_alarms.dart';
import '../../app/ui.dart';

class AlarmAccess extends StatelessWidget {
  const AlarmAccess({super.key, required this.model});
  final CortexModel model;
  @override
  Widget build(BuildContext context) {
    final alarms = model.alarms;
    return ListTile(
      leading: const Icon(Icons.alarm_rounded),
      title: const Text('Alarms'),
      subtitle: Text(switch (alarms.permission) {
        'authorized' => 'Allowed · set alarms through chat',
        'denied' => 'Permission needed · tap to open Settings',
        'unavailable' => 'Requires iOS 26 or later',
        _ => 'Tap to allow Cortex alarms',
      }),
      onTap: alarms.permission == 'unavailable'
          ? null
          : () => action(context, () async {
              if (alarms.permission == 'denied') {
                await native.invokeMethod<bool>('openAppSettings');
              } else {
                await alarms.sync(requestPermission: true);
              }
            }),
    );
  }
}

class AlarmList extends StatelessWidget {
  const AlarmList({super.key, required this.model});
  final CortexModel model;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionHead('Alarms'),
      Panel(
        padding: EdgeInsets.zero,
        child: AlarmAccess(model: model),
      ),
      const SizedBox(height: 8),
      caption('Ask in chat to set, change, or cancel a Cortex alarm.'),
      if (model.alarms.error != null) caption(model.alarms.error!),
      for (final alarm in model.alarms.items.where(
        (a) => !['cancelled', 'ended', 'expired'].contains(a['status']),
      ))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (alarm['spec'] as Map?)?['title'] as String? ?? 'Alarm',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                caption(alarmTime(alarm)),
                Text(alarmStatusLabel(alarm['status'] as String?)),
                if ((alarm['error'] as String? ?? '').isNotEmpty)
                  caption(alarm['error'] as String),
              ],
            ),
          ),
        ),
    ],
  );
}
