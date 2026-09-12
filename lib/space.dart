import 'dart:math';
import 'package:flutter/material.dart';
import 'cortex.dart';
import 'main.dart';
import 'ui.dart';
import 'fitness_trends.dart';

typedef OpenChat = void Function(String prompt, {bool photo});

class SpaceScreen extends StatelessWidget {
  final CortexModel model;
  final OpenChat onChat;
  const SpaceScreen({super.key, required this.model, required this.onChat});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
    children: [
      titleText('My space'),
      const SizedBox(height: 8),
      caption('See where you are. Let’s take it one step at a time.'),
      const SizedBox(height: 28),
      GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: .78,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          area(
            context,
            'Time\nmanagement',
            'A day with breathing room',
            Icons.schedule_rounded,
            () => open(context, false),
          ),
          area(
            context,
            'Fitness',
            'Small steps, visible progress',
            Icons.favorite_border_rounded,
            () => open(context, true),
          ),
          area(
            context,
            'Money\nspending',
            'Later',
            Icons.account_balance_wallet_outlined,
            null,
          ),
          area(
            context,
            'Personal\ntargets',
            'Later',
            Icons.flag_outlined,
            null,
          ),
        ],
      ),
      const SizedBox(height: 26),
      Panel(
        color: soft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: caption(
                'Tell Cortex what changed. Your chat updates these records, so you don’t have to manage lots of forms.',
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget area(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? tap,
  ) => Material(
    color: tap == null ? const Color(0xFFF2F4EE) : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 29, color: tap == null ? muted : ink),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: tap == null ? muted : ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
    ),
  );
  void open(BuildContext context, bool fitness) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (pageContext) {
        void backToChat(String prompt, {bool photo = false}) {
          Navigator.pop(pageContext);
          onChat(prompt, photo: photo);
        }

        return fitness
            ? FitnessScreen(model: model, onChat: backToChat)
            : TimeScreen(model: model, onChat: backToChat);
      },
    ),
  );
}

class FitnessScreen extends StatelessWidget {
  final CortexModel model;
  final OpenChat onChat;
  const FitnessScreen({super.key, required this.model, required this.onChat});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final today = day();
      final goals = model.records('goal');
      final goal = goals.isEmpty ? <String, dynamic>{} : goals.first.data;
      final weights = model.records('weight')
        ..sort(
          (a, b) =>
              (b.data['date'] as String).compareTo(a.data['date'] as String),
        );
      final current = weights.isNotEmpty
          ? (weights.first.data['kg'] as num).toDouble()
          : (goal['start'] as num?)?.toDouble();
      final start = (goal['start'] as num?)?.toDouble(),
          target = (goal['weight'] as num?)?.toDouble();
      final progress =
          current != null && start != null && target != null && start != target
          ? ((start - current) / (start - target)).clamp(0.0, 1.0)
          : 0.0;
      List<Entry> todayRecords(String kind) =>
          model.records(kind).where((e) => e.data['date'] == today).toList();
      final meals = todayRecords('meal'),
          activity = todayRecords('activity'),
          bps = todayRecords('bp'),
          stepRecords = todayRecords('steps');
      final steps = stepRecords.isEmpty
          ? null
          : (stepRecords.first.data['count'] as num).round();
      final intake = meals.fold<double>(
        0,
        (sum, e) => sum + (e.data['kcal'] as num).toDouble(),
      );
      final extra =
          max(
            0,
            (steps ?? 0) - ((goal['stepBaseline'] as num?)?.toInt() ?? 3000),
          ) *
          ((goal['kcalPerExtraStep'] as num?)?.toDouble() ?? .045);
      final workouts = activity
          .where((e) => e.data['source'] != 'appleHealth')
          .fold<double>(
            0,
            (sum, e) => sum + (e.data['kcal'] as num).toDouble(),
          );
      final base = (goal['tdee'] as num?)?.toDouble();
      final tdee = base == null ? null : base + extra + workouts;
      final budget = tdee == null
          ? (goal['intake'] as num?)?.toDouble()
          : tdee - ((goal['deficit'] as num?)?.toDouble() ?? 0);
      final remaining = budget == null ? null : budget - intake;
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Fitness'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Today'),
                Tab(text: 'Trends'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              RefreshIndicator(
                onRefresh: model.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                  children: [
                    label(today),
                    const SizedBox(height: 10),
                    titleText('Keep showing up for yourself.'),
                    const SizedBox(height: 22),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label('YOUR WEIGHT GOAL'),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        current?.toStringAsFixed(1) ?? '—',
                                        style: const TextStyle(
                                          fontSize: 42,
                                          height: 1,
                                          letterSpacing: -1.5,
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          bottom: 4,
                                          left: 6,
                                        ),
                                        child: Text(
                                          'kg',
                                          style: TextStyle(color: muted),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      target == null
                                          ? 'Set your goal in chat'
                                          : '→ ${target.toStringAsFixed(0)} kg',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (goal['date'] != null)
                                      Text(
                                        'by ${goal['date']}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: soft,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          caption(
                            current != null && target != null
                                ? '${max(0.0, current - target).toStringAsFixed(1)} kg to your target · one day at a time'
                                : 'Tell Cortex your current weight and target.',
                          ),
                        ],
                      ),
                    ),
                    sectionHead('Today’s energy'),
                    Panel(
                      color: soft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                intake.round().toString(),
                                style: const TextStyle(
                                  fontSize: 36,
                                  height: 1,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 7),
                              caption('kcal recorded'),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (budget != null && budget > 0) ...[
                            LayoutBuilder(
                              builder: (context, box) {
                                final scale =
                                    max(max(tdee ?? budget, budget), intake) *
                                    1.08;
                                return SizedBox(
                                  height: 23,
                                  child: Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      Container(
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        height: 10,
                                        width:
                                            box.maxWidth *
                                            (intake / scale).clamp(0, 1),
                                        decoration: BoxDecoration(
                                          color: ink,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left:
                                            box.maxWidth *
                                            (budget / scale).clamp(0, 1),
                                        child: Container(
                                          height: 22,
                                          width: 2,
                                          color: ink,
                                        ),
                                      ),
                                      if (tdee != null)
                                        Positioned(
                                          left:
                                              box.maxWidth *
                                              (tdee / scale).clamp(0, 1),
                                          child: Container(
                                            height: 16,
                                            width: 2,
                                            color: muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: caption(
                                    'Food budget ${budget.round()}',
                                  ),
                                ),
                                caption(
                                  tdee == null ? '' : 'TDEE ~${tdee.round()}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Text(
                              remaining! >= 0
                                  ? '${remaining.round()} kcal left in your plan'
                                  : '${(-remaining).round()} kcal above your plan',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else
                            caption(
                              'Tell Cortex your energy plan to see your daily bar.',
                            ),
                          const SizedBox(height: 10),
                          caption(
                            'Food and activity numbers are estimates. This bar reflects what you’ve logged so far.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => onChat(
                          'Please estimate this meal. Let me check the estimate before you record it.',
                          photo: true,
                        ),
                        icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                        label: const Text('Take a food photo'),
                      ),
                    ),
                    sectionHead('Daily check-in'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.monitor_weight_outlined,
                                  color: muted,
                                ),
                                const SizedBox(height: 12),
                                label('WEIGHT'),
                                const SizedBox(height: 7),
                                Text(
                                  todayRecords('weight').isEmpty
                                      ? 'Not recorded'
                                      : '${todayRecords('weight').first.data['kg']} kg',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.favorite_outline,
                                  color: muted,
                                ),
                                const SizedBox(height: 12),
                                label('BLOOD PRESSURE'),
                                const SizedBox(height: 7),
                                Text(
                                  bps.isEmpty
                                      ? 'Not recorded'
                                      : '${bps.first.data['systolic']}/${bps.first.data['diastolic']}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (bps.isNotEmpty) caption('mmHg'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    sectionHead('Movement'),
                    Panel(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_walk_outlined,
                            size: 32,
                            color: muted,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  steps == null
                                      ? 'No steps imported yet'
                                      : '$steps steps',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                caption(
                                  activity.isEmpty
                                      ? 'Activity will appear after you log or import it.'
                                      : '${activity.length} activity records today',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => action(context, () async {
                        final message = await model.importHealth();
                        if (context.mounted) {
                          notice(context, message);
                        }
                      }),
                      icon: const Icon(Icons.favorite_outline, size: 18),
                      label: const Text('Import today’s Apple Health'),
                    ),
                    sectionHead('Food today'),
                    if (meals.isEmpty)
                      caption('Send a photo or tell Cortex what you ate.'),
                    for (final meal in meals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Panel(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(meal.data['title'] as String),
                              ),
                              Text(
                                '${meal.data['kcal']} kcal',
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    sectionHead('Recent readings'),
                    for (final weight in weights.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: caption(weight.data['date'] as String),
                            ),
                            Text('${weight.data['kg']} kg'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 26),
                    OutlinedButton.icon(
                      onPressed: () => onChat(''),
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Tell Cortex an update'),
                    ),
                    const SizedBox(height: 12),
                    caption(
                      'Weight, glucose, blood pressure, meals, goals — just tell me in chat.',
                    ),
                  ],
                ),
              ),
              FitnessTrends(model: model),
            ],
          ),
        ),
      );
    },
  );
}

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
      final tasks = model
          .records('task')
          .where((e) => e.data['done'] != true)
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('Time management')),
        body: RefreshIndicator(
          onRefresh: model.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            children: [
              label(day()),
              const SizedBox(height: 10),
              titleText('A day you can actually live.'),
              const SizedBox(height: 10),
              caption('Room for what matters. Room to breathe.'),
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
                          onPressed: () =>
                              complete(context, plan, blocks, upcoming.first),
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
                if (((plan.data['unscheduled'] ?? []) as List).isNotEmpty) ...[
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
              sectionHead('Tasks with a deadline'),
              if (tasks.isEmpty)
                caption('Tell Cortex a task and when it’s due.'),
              for (final task in tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.data['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 5),
                        caption(
                          '${task.data['minutes']} min · due ${task.data['deadline'].toString().replaceAll('T', ' ')}',
                        ),
                      ],
                    ),
                  ),
                ),
              sectionHead('Your routines'),
              if (model.records('routine').isEmpty)
                caption(
                  'A few gentle defaults will be added at your first check-in. Change them through chat.',
                ),
              for (final r in model.records('routine'))
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
                      caption('${r.data['minutes']} min'),
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () => action(context, () async {
                  final message = await model.importCalendars();
                  if (context.mounted) {
                    notice(context, message);
                  }
                }),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Import iPhone calendars'),
              ),
              const SizedBox(height: 10),
              caption(
                'Imports the next 7 days from calendars on this iPhone. Replan after importing. All-day events are reminders, not blocked hours.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => onChat('Help me with my day. '),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Talk it through with Cortex'),
              ),
            ],
          ),
        ),
      );
    },
  );
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
        if (completed >= (task.data['minutes'] as num)) {
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
      if (widget.model.records('routine').isEmpty) {
        final defaults = [
          ('Slow start & breakfast', 30, 0, 'routine'),
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
