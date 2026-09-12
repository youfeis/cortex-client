import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';

DateTime? nextRoutineDate(Entry r, DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final rawAnchor = DateTime.tryParse(r.data['anchorDate'] as String? ?? '');
  final anchor = rawAnchor == null
      ? null
      : DateTime.utc(rawAnchor.year, rawAnchor.month, rawAnchor.day);
  final interval = (r.data['intervalWeeks'] as num? ?? 1).toInt();
  if (interval < 1 || interval > 52 || (interval > 1 && anchor == null))
    return null;
  final days = (r.data['weekdays'] as List? ?? []).cast<int>();
  var date = anchor != null && anchor.isAfter(today) ? anchor : today;
  for (var i = 0; i < 366; i++, date = date.add(const Duration(days: 1))) {
    if (days.isNotEmpty && !days.contains(date.weekday)) continue;
    if (anchor != null && (date.difference(anchor).inDays ~/ 7) % interval != 0)
      continue;
    return date;
  }
  return null;
}

String routineWhen(Entry r, {DateTime? now}) {
  final days = (r.data['weekdays'] as List? ?? []).cast<int>();
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final cadence = days.isEmpty
      ? 'Daily'
      : days.where((d) => d >= 1 && d <= 7).map((d) => names[d - 1]).join(', ');
  final period = switch (r.data['period']) {
    'morning' => 'Morning',
    'evening' => 'After evening meal',
    _ => '',
  };
  final interval = (r.data['intervalWeeks'] as num? ?? 1).toInt();
  final label = period.isEmpty ? cadence : '$cadence · $period';
  if (interval <= 1) return label;
  final today = now ?? DateTime.now();
  final next = nextRoutineDate(r, today);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final due = next == null
      ? ''
      : next.year == today.year &&
            next.month == today.month &&
            next.day == today.day
      ? ' · Due today'
      : ' · Next ${next.day} ${months[next.month - 1]}';
  return 'Every $interval weeks · $label$due';
}

class MedicalRoutines extends StatelessWidget {
  final CortexModel model;
  const MedicalRoutines({super.key, required this.model});
  @override
  Widget build(BuildContext context) {
    final rows =
        model
            .records('routine')
            .where(
              (r) => r.data['medical'] == true && r.data['enabled'] != false,
            )
            .toList()
          ..sort((a, b) => routineWhen(a).compareTo(routineWhen(b)));
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHead('Medical routines'),
        Panel(
          child: Column(
            children: [
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.medical_services_outlined,
                    color: muted,
                    size: 21,
                  ),
                  title: Text(
                    r.data['title'] as String,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(routineWhen(r)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        caption(
          'From your health records. Tell Cortex when a routine changes or when you have done it.',
        ),
      ],
    );
  }
}
