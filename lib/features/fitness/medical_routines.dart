import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';

String routineWhen(Entry r) {
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
  return period.isEmpty ? cadence : '$cadence · $period';
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
