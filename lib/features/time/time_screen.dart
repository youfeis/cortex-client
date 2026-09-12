import 'alarms.dart';
import '../fitness/medical_routines.dart';
import '../../remote_ui/remote_layout.dart';
import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';
import 'calendars.dart';
import 'todos.dart';

import '../../core/navigation.dart';

class TimeScreen extends StatelessWidget {
  final CortexModel model;
  final OpenChat onChat;
  const TimeScreen({super.key, required this.model, required this.onChat});
  Future<void> checkIn(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CheckIn(model: model),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final plans = model
          .records('plan')
          .where((e) => e.id == 'plan-${day()}')
          .toList();
      final plan = plans.isEmpty ? null : plans.first;
      final blocks = ((plan?.data['blocks'] ?? []) as List)
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      final now = DateTime.now().hour * 60 + DateTime.now().minute;
      final upcoming = blocks
          .where((b) => b['done'] != true && (b['end'] as num) > now)
          .toList();

      return Scaffold(
        appBar: AppBar(title: const Text('Time management')),
        body: RefreshIndicator(
          onRefresh: model.refresh,
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
                  const SizedBox(height: 24),
                  if (plan == null)
                    Panel(
                      color: soft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.wb_sunny_outlined,
                            color: muted,
                            size: 30,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Start where you are.',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          caption(
                            'Tell me you’re awake. We’ll make room for tasks, meals, movement, and something just for you.',
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => checkIn(context),
                              child: const Text('I’m awake · arrange my day'),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if (upcoming.isNotEmpty)
                      Panel(
                        color: soft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label('JUST THE NEXT STEP'),
                            const SizedBox(height: 12),
                            Text(
                              upcoming.first['title'] as String,
                              style: const TextStyle(
                                fontSize: 25,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            caption(
                              '${clock((upcoming.first['start'] as num).toInt())} – ${clock((upcoming.first['end'] as num).toInt())}',
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () => complete(
                                context,
                                plan,
                                blocks,
                                upcoming.first,
                              ),
                              icon: const Icon(Icons.check, size: 19),
                              label: const Text('Done with this'),
                            ),
                          ],
                        ),
                      )
                    else
                      const Panel(
                        color: soft,
                        child: Text(
                          'No more scheduled steps right now. Take a breath.',
                        ),
                      ),
                    sectionHead('Coming up'),
                    for (final b in upcoming.skip(1).take(3)) blockRow(b),
                    if (blocks.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('See the whole day'),
                        children: [for (final b in blocks) blockRow(b)],
                      ),
                    if (((plan.data['unscheduled'] ?? []) as List)
                        .isNotEmpty) ...[
                      sectionHead('Needs another time'),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final text in plan.data['unscheduled'] as List)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('• $text'),
                              ),
                            caption(
                              'We can shorten, move, or drop something. Tell Cortex what feels right.',
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => checkIn(context),
                      child: const Text('Adjust today’s plan'),
                    ),
                  ],
                ],
              ),
              'routines': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AlarmList(model: model),
                  sectionHead('Your routines'),
                  if (model.records('routine').isEmpty)
                    caption(
                      'A few gentle defaults will be added at your first check-in. Change them through chat.',
                    ),
                  for (final r
                      in model
                          .records('routine')
                          .where((r) => r.data['enabled'] != false))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            r.data['kind'] == 'movement'
                                ? Icons.directions_walk
                                : r.data['kind'] == 'rest'
                                ? Icons.spa_outlined
                                : Icons.repeat,
                            size: 17,
                            color: muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r.data['title'] as String)),
                          caption(
                            r.data['medical'] == true
                                ? routineWhen(r)
                                : '${r.data['minutes']} min',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 22),
                ],
              ),
              'calendars': Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionHead(
                    'Calendar events',
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
                    'Google Calendar changes appear here automatically. Ask Cortex to adjust your day plan when needed.',
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
              (e) => (e.data['date']?.toString() ?? '').compareTo(day()) >= 0,
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
              '${e.data['date']} · ${e.data['allDay'] == true ? 'All day' : '${clock((e.data['start'] as num).toInt())} – ${clock((e.data['end'] as num).toInt())}'}',
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

  Widget blockRow(Map<String, dynamic> b) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 55, child: caption(clock((b['start'] as num).toInt()))),
        Container(
          width: 3,
          height: 38,
          margin: const EdgeInsets.only(right: 12),
          color: b['kind'] == 'rest' ? const Color(0xFFBECDAA) : line,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b['title'] as String,
                style: TextStyle(
                  decoration: b['done'] == true
                      ? TextDecoration.lineThrough
                      : null,
                  color: b['done'] == true ? muted : ink,
                ),
              ),
              caption(
                '${(b['end'] as num) - (b['start'] as num)} min · ${b['kind']}',
              ),
            ],
          ),
        ),
        if (b['done'] == true) const Icon(Icons.check, size: 17, color: muted),
      ],
    ),
  );
  Future<void> complete(
    BuildContext context,
    Entry plan,
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> target,
  ) => action(context, () async {
    for (final b in blocks) {
      if (b['id'] == target['id']) {
        b['done'] = true;
      }
    }
    await model.save(
      'plan',
      {...plan.data, 'blocks': blocks},
      id: plan.id,
      reload: false,
    );
    final taskId = target['taskId'];
    if (taskId != null) {
      final tasks = model.records('task').where((t) => t.id == taskId);
      if (tasks.isNotEmpty) {
        final task = tasks.first;
        final completed = blocks
            .where((b) => b['taskId'] == taskId && b['done'] == true)
            .fold<num>(
              0,
              (sum, b) => sum + (b['end'] as num) - (b['start'] as num),
            );
        if (completed >= ((task.data['minutes'] ?? 25) as num)) {
          await model.save(
            'task',
            {...task.data, 'done': true},
            id: task.id,
            reload: false,
          );
        }
      }
    }
    await model.refresh();
  });
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
      if (!widget.model
          .records('routine')
          .any((r) => r.id.startsWith('routine-'))) {
        final defaults = [
          ('Slow start & breakfast', 30, 0, 'routine'),
          if (!widget.model.records('routine').any((r) => r.id == 'medical-bp'))
            ('Weight & blood pressure', 10, 1, 'routine'),
          ('Lunch, away from the screen', 45, 750, 'routine'),
          ('Get outside for a walk', 25, 930, 'movement'),
          ('Something just for you', 45, 990, 'rest'),
          ('Dinner & time to unwind', 45, 1170, 'routine'),
          ('Wind down for sleep', 30, -1, 'rest'),
        ];
        for (var i = 0; i < defaults.length; i++) {
          final d = defaults[i];
          await widget.model.save(
            'routine',
            {
              'title': d.$1,
              'minutes': d.$2,
              'at': d.$3,
              'enabled': true,
              'kind': d.$4,
            },
            id: 'routine-$i',
            reload: false,
          );
        }
      }
      final now = DateTime.now();
      await widget.model.arrange({
        'date': day(now),
        'wake': clock(wake.hour * 60 + wake.minute),
        'bedtime': clock(bed.hour * 60 + bed.minute),
        'energy': energy,
        'now': now.hour * 60 + now.minute,
      });
      if (mounted) {
        Navigator.pop(context);
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
