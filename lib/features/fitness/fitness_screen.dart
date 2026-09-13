import 'nutrition.dart';
import 'medical_routines.dart';
import 'health_access.dart';
import 'energy.dart';
import '../../remote_ui/remote_layout.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';
import 'trends.dart';

import '../../core/navigation.dart';

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
      final meals = todayRecords('meal'), bps = todayRecords('bp');
      final energy = DailyEnergy.fromRecords(model.entries, date: today);
      final steps = energy.steps, intake = energy.intake;
      final tdee = energy.tdee, budget = energy.budget;
      final remaining = energy.remaining;
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
                onRefresh: model.refreshFitness,
                child: RemoteLayout(
                  page: 'fitness',
                  slots: {
                    'intro': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label(today),
                        const SizedBox(height: 10),
                        titleText('Keep showing up for yourself.'),
                        const SizedBox(height: 22),
                      ],
                    ),
                    'goal': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
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
                      ],
                    ),
                    'energy': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                  Expanded(child: caption('kcal recorded')),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (budget != null && budget > 0) ...[
                                LayoutBuilder(
                                  builder: (context, box) {
                                    final scale =
                                        max(
                                          max(tdee ?? budget, budget),
                                          intake,
                                        ) *
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
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          Container(
                                            key: const ValueKey(
                                              'energy-intake-fill',
                                            ),
                                            height: 10,
                                            width:
                                                box.maxWidth *
                                                (intake / scale).clamp(0, 1),
                                            decoration: BoxDecoration(
                                              color: ink,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          Positioned(
                                            key: const ValueKey(
                                              'energy-budget-marker',
                                            ),
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
                                              key: const ValueKey(
                                                'energy-tdee-marker',
                                              ),
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
                                      tdee == null
                                          ? ''
                                          : 'TDEE ~${tdee.round()}',
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
                      ],
                    ),
                    'foodPhoto': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => onChat(
                              'This is what I ate. Infer the food and nutrition, research and estimate missing values, save reusable food facts, and record my portion.',
                              photo: true,
                            ),
                            icon: const Icon(
                              Icons.add_a_photo_outlined,
                              size: 20,
                            ),
                            label: const Text('Log food from a photo'),
                          ),
                        ),
                      ],
                    ),
                    'checkIn': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                    'movement': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                      steps == null
                                          ? 'Steps refresh from Apple Health each time you open Cortex.'
                                          : 'Walking adds ~${energy.stepsExtraKcal.round()} kcal to today’s estimate.',
                                    ),
                                    if (energy.workoutKcal > 0)
                                      caption(
                                        'Logged workouts add ~${energy.workoutKcal.round()} kcal.',
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    'health': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        HealthAccess(model: model),
                        MedicalRoutines(model: model),
                      ],
                    ),
                    'meals': FoodToday(
                      model: model,
                      meals: meals,
                      onChat: onChat,
                    ),
                    'readings': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                    'chat': Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                  },
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
