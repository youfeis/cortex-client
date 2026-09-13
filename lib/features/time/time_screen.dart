import 'task_focus.dart';
import 'alarms.dart';
import 'daily_routines.dart';
import '../../remote_ui/remote_layout.dart';
import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../app/ui.dart';
import 'calendars.dart';
import 'todos.dart';

import '../../core/navigation.dart';

String planClock(int minute) =>
    '${clock(minute % 1440)}${minute >= 1440 ? ' +1 day' : ''}';

class TimeScreen extends StatelessWidget {
  final CortexModel model;
  final OpenChat onChat;
  const TimeScreen({super.key, required this.model, required this.onChat});
  Future<void> checkIn(BuildContext context) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CheckIn(model: model),
    );
    if (sent == true && context.mounted) onChat('');
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final plans = model
          .records('plan')
          .where((e) => e.id == 'plan-${day()}')
          .toList();
      final plan = plans.isEmpty ? null : plans.first;

      return Scaffold(
        appBar: AppBar(title: const Text('Time management')),
        body: RefreshIndicator(
          onRefresh: () async {
            await model.taskFocus.sync();
            await model.refresh();
          },
          child: RemoteLayout(
            page: 'time',
            slots: {
              'intro': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label(day()),
                  const SizedBox(height: 10),
                  titleText('A day you can actually live.'),
                  const SizedBox(height: 10),
                  caption('Room for what matters. Room to breathe.'),
                ],
              ),
              'todos': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [TodoList(model: model, onChat: onChat)],
              ),
              'plan': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionHead('Planned for today'),
                  caption(
                    'Start early or mark anything done here. Live Activities appear 30 minutes before the planned start, or when you start early.',
                  ),
                  const SizedBox(height: 12),
                  if (model.taskFocus.plannedForToday().isEmpty)
                    const Panel(
                      child: Text('No timed tasks loaded for today yet.'),
                    ),
                  FocusPanel(
                    model: model,
                    items: model.taskFocus.plannedForToday(),
                    planned: true,
                    showHeading: false,
                  ),
                  if (model.taskFocus.plannedError != null)
                    caption(model.taskFocus.plannedError!),
                  if (plan == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.icon(
                        onPressed: () => checkIn(context),
                        icon: const Icon(Icons.wb_sunny_outlined),
                        label: const Text('I’m awake · arrange my day'),
                      ),
                    )
                  else
                    OutlinedButton(
                      onPressed: () =>
                          onChat('I’d like to adjust today’s calendar. '),
                      child: const Text('Adjust today’s plan'),
                    ),
                ],
              ),
              'routines': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DailyRoutines(model: model),
                  AlarmList(model: model),
                ],
              ),
              'calendars': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionHead(
                    'Other calendar events',
                    trailing: IconButton(
                      tooltip: 'Choose calendars',
                      onPressed: () => openCalendars(context, model),
                      icon: const Icon(Icons.tune, size: 20),
                    ),
                  ),
                  caption(
                    model.calendarSyncing
                        ? 'Syncing calendars…'
                        : model.calendarError ??
                              (model.calendarGranted
                                  ? 'Google Calendar · next 30 days · automatic sync'
                                  : 'Connect your personal and work calendars.'),
                  ),
                  const SizedBox(height: 12),
                  ...calendarRows(model),
                  OutlinedButton.icon(
                    onPressed: () => openCalendars(context, model),
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: const Text('Choose calendars'),
                  ),
                  const SizedBox(height: 10),
                  caption(
                    'Google Calendar holds your planned times. Falling behind won’t move them. Ask Cortex when you want a change.',
                  ),
                ],
              ),
              'chat': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => onChat('Help me with my day. '),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Talk it through with Cortex'),
                  ),
                ],
              ),
            },
          ),
        ),
      );
    },
  );
  List<Widget> calendarRows(CortexModel m) {
    final events =
        m
            .records('event')
            .where(
              (e) =>
                  (e.data['date']?.toString() ?? '').compareTo(day()) > 0 ||
                  (e.data['date'] == day() && e.data['allDay'] == true),
            )
            .toList()
          ..sort(
            (
              a,
              b,
            ) => '${a.data['date']}-${(a.data['start'] as num).toInt().toString().padLeft(4, '0')}'
                .compareTo(
                  '${b.data['date']}-${(b.data['start'] as num).toInt().toString().padLeft(4, '0')}',
                ),
          );
    Widget row(Entry e) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.data['title']?.toString() ?? 'Calendar event',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            caption(
              '${e.data['date']} · ${e.data['allDay'] == true ? 'All day' : '${planClock((e.data['start'] as num).toInt())} – ${planClock((e.data['end'] as num).toInt())}'}',
            ),
            if (e.data['calendar'] != null)
              caption('${e.data['account'] ?? ''} · ${e.data['calendar']}'),
          ],
        ),
      ),
    );
    return [
      if (events.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('No upcoming events yet.'),
        ),
      for (final e in events.take(5)) row(e),
      if (events.length > 5)
        ExpansionTile(
          title: Text('All ${events.length} event entries'),
          children: [for (final e in events.skip(5)) row(e)],
        ),
    ];
  }
}

class CheckIn extends StatefulWidget {
  final CortexModel model;
  const CheckIn({super.key, required this.model});
  @override
  State<CheckIn> createState() => _CheckInState();
}

class _CheckInState extends State<CheckIn> {
  TimeOfDay wake = TimeOfDay.now(), bed = const TimeOfDay(hour: 23, minute: 0);
  String energy = 'okay';
  bool saving = false;
  String? error;
  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final now = DateTime.now();
      await widget.model.arrange({
        'date': day(now),
        'wake': clock(wake.hour * 60 + wake.minute),
        'bedtime': clock(bed.hour * 60 + bed.minute),
        'energy': energy,
        'now': now.hour * 60 + now.minute,
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleText('Good to see you.'),
          const SizedBox(height: 12),
          caption(
            'We’ll start from now. No catching up with a day that already passed.',
          ),
          const SizedBox(height: 22),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I woke up at'),
            trailing: Text(wake.format(context)),
            onTap: saving
                ? null
                : () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: wake,
                    );
                    if (value != null && mounted) {
                      setState(() => wake = value);
                    }
                  },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aim for bed at'),
            trailing: Text(bed.format(context)),
            onTap: saving
                ? null
                : () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: bed,
                    );
                    if (value != null && mounted) {
                      setState(() => bed = value);
                    }
                  },
          ),
          const SizedBox(height: 18),
          const Text('How much energy do you have?'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'low', label: Text('Low')),
              ButtonSegment(value: 'okay', label: Text('Okay')),
              ButtonSegment(value: 'good', label: Text('Good')),
            ],
            selected: {energy},
            onSelectionChanged: saving
                ? null
                : (value) => setState(() => energy = value.first),
          ),
          const SizedBox(height: 20),
          caption(
            'Meals, movement, breaks and leisure get their own space. Tasks are split into small blocks.',
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Arranging…' : 'Arrange my day'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
