import 'package:flutter/material.dart';
import '../../app/ui.dart';
import '../../core/cortex.dart';
import '../../core/navigation.dart';
import '../../remote_ui/remote_layout.dart';
import '../fitness/trends.dart';

const pets = {'cookie': 'Cookie', 'wanwan': 'Wanwan'};

// Preserve every reading; same-day reweighs are distinct measurements.
List<HealthPoint> petWeightPoints(List<Entry> entries, String petId) {
  final points = <HealthPoint>[];
  for (final e in entries.where(
    (e) => e.kind == 'pet_weight' && e.data['petId'] == petId,
  )) {
    final date = e.data['date']?.toString() ?? '';
    final parsed = DateTime.tryParse(date);
    final kg = e.data['kg'];
    if (parsed == null ||
        date.length != 10 ||
        day(parsed) != date ||
        kg is! num ||
        !kg.isFinite ||
        kg <= 0 ||
        kg > 500) {
      continue;
    }
    final stamp = e.data['recordedAt']?.toString() ?? '';
    final clock = RegExp(r'T(\d{2}):(\d{2}):(\d{2})').firstMatch(stamp);
    final at = DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      clock == null ? 12 : int.parse(clock[1]!),
      clock == null ? 0 : int.parse(clock[2]!),
      clock == null ? 0 : int.parse(clock[3]!),
    );
    points.add(HealthPoint(e.id, date, at, kg.toDouble(), updated: e.updated));
  }
  points.sort((a, b) {
    final order = a.at.compareTo(b.at);
    if (order != 0) return order;
    final updated = (a.updated ?? DateTime.utc(1970)).compareTo(
      b.updated ?? DateTime.utc(1970),
    );
    return updated == 0 ? a.id.compareTo(b.id) : updated;
  });
  return points;
}

class PetsScreen extends StatefulWidget {
  final CortexModel model;
  final OpenChat onChat;
  const PetsScreen({super.key, required this.model, required this.onChat});
  @override
  State<PetsScreen> createState() => _PetsScreenState();
}

class _PetsScreenState extends State<PetsScreen> {
  int? days;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Pets')),
      body: RefreshIndicator(
        onRefresh: () => action(context, widget.model.refresh),
        child: RemoteLayout(
          page: 'pets',
          slots: {
            'intro': Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleText('Cookie & Wanwan'),
                  const SizedBox(height: 8),
                  caption('Their weight, one reading at a time.'),
                ],
              ),
            ),
            'range': Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SegmentedButton<int?>(
                segments: const [
                  ButtonSegment(value: 30, label: Text('30 days')),
                  ButtonSegment(value: 90, label: Text('90 days')),
                  ButtonSegment(value: null, label: Text('All')),
                ],
                selected: {days},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => days = v.first),
              ),
            ),
            for (final pet in pets.entries)
              pet.key: _petCard(pet.key, pet.value),
            'chat': Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  caption(
                    'Tell Cortex the pet’s name, weight and unit. Add a date for an older reading. Your saved readings update these charts.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => widget.onChat(
                      'I’d like to record Cookie and Wanwan’s weights. ',
                    ),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Record weights in chat'),
                  ),
                  const SizedBox(height: 10),
                  caption(
                    'Tap a chart or use its arrows to review each reading. Dashed lines connect days with no readings.',
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    ),
  );

  Widget _petCard(String id, String name) {
    final all = petWeightPoints(widget.model.entries, id);
    final points = pointsInRange(all, days, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HealthTrendCard(
            key: ValueKey('pet-$id-$days'),
            title: name,
            metric: TrendMetric.weight,
            points: points,
            unit: 'kg',
            decimalPlaces: 2,
            minimumWeightPadding: .05,
            empty: all.isEmpty
                ? 'No readings for $name yet.'
                : 'No readings in this period. Choose All to see earlier readings.',
            summary: all.isEmpty
                ? 'Send $name’s first weight in chat to begin.'
                : null,
          ),
          TextButton.icon(
            onPressed: () => widget.onChat('$name’s weight is '),
            icon: const Icon(Icons.add_rounded, size: 19),
            label: Text('Record $name’s weight'),
          ),
        ],
      ),
    );
  }
}
