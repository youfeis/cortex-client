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
  final monthInterval = (r.data['intervalMonths'] as num?)?.toInt();
  final interval = (r.data['intervalWeeks'] as num? ?? 1).toInt();
  if (interval < 1 || interval > 52 || (interval > 1 && anchor == null)) {
    return null;
  }
  final days = (r.data['weekdays'] as List? ?? []).cast<int>();
  var date = anchor != null && anchor.isAfter(today) ? anchor : today;
  final start = DateTime.tryParse(r.data['startDate']?.toString() ?? '');
  if (start != null) {
    final startDate = DateTime.utc(start.year, start.month, start.day);
    if (startDate.isAfter(date)) date = startDate;
  }
  for (var i = 0; i < 735; i++, date = date.add(const Duration(days: 1))) {
    if (monthInterval != null) {
      if (anchor == null || monthInterval < 1 || monthInterval > 12) {
        return null;
      }
      final months = (date.year - anchor.year) * 12 + date.month - anchor.month;
      final lastDay = DateTime.utc(date.year, date.month + 1, 0).day;
      if (months % monthInterval == 0 &&
          date.day == anchor.day.clamp(1, lastDay)) {
        return date;
      }
      continue;
    }
    if (days.isNotEmpty && !days.contains(date.weekday)) continue;
    if (anchor != null &&
        (date.difference(anchor).inDays ~/ 7) % interval != 0) {
      continue;
    }
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
    'evening' => 'Evening',
    _ => '',
  };
  final interval = (r.data['intervalWeeks'] as num? ?? 1).toInt();
  final label = period.isEmpty ? cadence : '$cadence · $period';
  final monthInterval = (r.data['intervalMonths'] as num?)?.toInt();
  if (interval <= 1 && monthInterval == null) return label;
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
  return monthInterval != null
      ? '${monthInterval == 1 ? 'Monthly' : 'Every $monthInterval months'}$due'
      : 'Every $interval weeks · $label$due';
}

class DailyRoutines extends StatefulWidget {
  final CortexModel model;
  const DailyRoutines({super.key, required this.model});
  @override
  State<DailyRoutines> createState() => _DailyRoutinesState();
}

class _DailyRoutinesState extends State<DailyRoutines> {
  final pending = <String>{};
  CortexModel get model => widget.model;
  Future<void> toggle(Entry routine, bool done) async {
    setState(() => pending.add(routine.id));
    await action(context, () async {
      await model.api.call('POST', '/v1/routines/complete', {
        'routineId': routine.id,
        'date': day(),
        'done': done,
      });
      await model.taskFocus.sync();
      await model.refresh();
    });
    if (mounted) setState(() => pending.remove(routine.id));
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        model
            .records('routine')
            .where((r) => r.data['enabled'] != false)
            .toList()
          ..sort((a, b) => routineWhen(a).compareTo(routineWhen(b)));
    if (rows.isEmpty) return const SizedBox.shrink();
    Map state(Entry r) {
      final value = model.routineStates[r.id];
      return value is Map && value['date'] == day() ? value : {};
    }

    final today = rows.where((r) => state(r)['due'] == true).toList();
    final upcoming = rows.where((r) => state(r)['due'] != true).toList();
    Widget row(Entry r) {
      final value = state(r);
      final due = value['due'] == true;
      final done = value['done'] == true;
      final source = switch (value['source']) {
        'record' => 'Checked from a matching record',
        'plan' => 'Done · day plan',
        'chat' => done ? 'Done · reported in chat' : 'Unchecked in chat',
        'checkbox' => done ? 'Done · checked by you' : 'Unchecked by you',
        _ => '',
      };
      return CheckboxListTile(
        key: ValueKey(r.id),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: done,
        onChanged: due && !pending.contains(r.id) && model.online
            ? (v) => toggle(r, v ?? false)
            : null,
        title: Text(
          r.data['title'] as String,
          style: TextStyle(
            fontSize: 16,
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          source.isNotEmpty ? '${routineWhen(r)}\n$source' : routineWhen(r),
        ),
        secondary: pending.contains(r.id)
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHead(
          'Daily routines',
          trailing: Text(
            '${today.where((r) => state(r)['done'] == true).length}/${today.length} today',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ),
        Panel(
          child: Column(
            children: [
              for (final r in today) row(r),
              if (upcoming.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Other days'),
                  children: [for (final r in upcoming) row(r)],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        caption(
          'Matching records check these automatically. Tell Cortex when you finish, or tap a box. Doses need your confirmation.',
        ),
      ],
    );
  }
}
