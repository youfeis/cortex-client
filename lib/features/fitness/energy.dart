import 'dart:math';
import '../../core/cortex.dart';

/// Uses the owner's stored baseline + extra steps + logged workouts model.
/// Apple Health active energy overlaps those steps, so it is not added again.
class DailyEnergy {
  final int? steps;
  final double intake, stepsExtraKcal, workoutKcal;
  final double? tdee, budget;
  double? get remaining => budget == null ? null : budget! - intake;

  const DailyEnergy({
    required this.steps,
    required this.intake,
    required this.stepsExtraKcal,
    required this.workoutKcal,
    required this.tdee,
    required this.budget,
  });

  factory DailyEnergy.fromRecords(List<Entry> entries, {required String date}) {
    final goals = entries.where((e) => e.kind == 'goal');
    final goal = goals.isEmpty ? <String, dynamic>{} : goals.first.data;
    final today = entries.where((e) => e.data['date'] == date);
    final readings = today.where((e) => e.kind == 'steps').toList()
      ..sort((a, b) {
        // HealthKit supplies one merged phone/watch total for the day. A
        // chat-entered total is a fallback, never another amount to add to it.
        final aHealth = a.data['source'] == 'appleHealth';
        final bHealth = b.data['source'] == 'appleHealth';
        if (aHealth != bHealth) return aHealth ? -1 : 1;
        return (b.updated ?? DateTime(0)).compareTo(a.updated ?? DateTime(0));
      });
    final steps = readings.isEmpty
        ? null
        : (readings.first.data['count'] as num?)?.round();
    final intake = today
        .where((e) => e.kind == 'meal')
        .fold<double>(
          0,
          (sum, e) => sum + ((e.data['kcal'] as num?)?.toDouble() ?? 0),
        );
    final extra =
        max(
          0,
          (steps ?? 0) - ((goal['stepBaseline'] as num?)?.toInt() ?? 3000),
        ) *
        ((goal['kcalPerExtraStep'] as num?)?.toDouble() ?? .045);
    final workouts = today
        .where((e) => e.kind == 'activity' && e.data['source'] != 'appleHealth')
        .fold<double>(
          0,
          (sum, e) => sum + ((e.data['kcal'] as num?)?.toDouble() ?? 0),
        );
    final base = (goal['tdee'] as num?)?.toDouble();
    final tdee = base == null ? null : base + extra + workouts;
    return DailyEnergy(
      steps: steps,
      intake: intake,
      stepsExtraKcal: extra,
      workoutKcal: workouts,
      tdee: tdee,
      budget: tdee == null
          ? (goal['intake'] as num?)?.toDouble()
          : tdee - ((goal['deficit'] as num?)?.toDouble() ?? 0),
    );
  }
}
