import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';

const glucoseFactor = 18.0182;
const bpLower = Color(0xFF9A6845);
const glucoseColor = Color(0xFF686295);

enum TrendMetric { weight, glucose, bp }

class HealthPoint {
  final String id, date, context;
  final DateTime at;
  final DateTime? updated;
  final double value;
  final double? second;
  const HealthPoint(
    this.id,
    this.date,
    this.at,
    this.value, {
    this.second,
    this.context = '',
    this.updated,
  });
}

List<HealthPoint> healthPoints(List<Entry> records, TrendMetric metric) {
  final kind = switch (metric) {
    TrendMetric.weight => 'weight',
    TrendMetric.glucose => 'glucose',
    TrendMetric.bp => 'bp',
  };
  final result = <HealthPoint>[];
  for (final entry in records.where((r) => r.kind == kind)) {
    final d = entry.data;
    final date = d['date']?.toString() ?? '';
    final parsed = DateTime.tryParse(date);
    final raw =
        d[switch (metric) {
          TrendMetric.weight => 'kg',
          TrendMetric.glucose => 'mgdl',
          TrendMetric.bp => 'systolic',
        }];
    final lower = d['diastolic'];
    if (parsed == null || raw is! num || !raw.isFinite || raw <= 0) continue;
    if (metric == TrendMetric.bp &&
        (lower is! num || !lower.isFinite || lower <= 0 || lower >= raw)) {
      continue;
    }
    final stamp = DateTime.tryParse(
      d['recordedAt']?.toString() ?? '',
    )?.toLocal();
    // The record's local date remains authoritative when the owner travels.
    final at = DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      stamp?.hour ?? 12,
      stamp?.minute ?? 0,
      stamp?.second ?? 0,
    );
    result.add(
      HealthPoint(
        entry.id,
        date,
        at,
        raw.toDouble(),
        second: metric == TrendMetric.bp ? (lower as num).toDouble() : null,
        context: d['context']?.toString() ?? 'unspecified',
        updated: entry.updated,
      ),
    );
  }
  result.sort((a, b) {
    final order = a.at.compareTo(b.at);
    if (order != 0) return order;
    // An undated-time reading uses record order, never a random ID, as a tie-break.
    final updatedOrder = (a.updated ?? DateTime.utc(1970)).compareTo(
      b.updated ?? DateTime.utc(1970),
    );
    return updatedOrder == 0 ? a.id.compareTo(b.id) : updatedOrder;
  });
  if (metric == TrendMetric.weight) {
    final byDate = <String, HealthPoint>{};
    for (final point in result) {
      byDate[point.date] = point;
    }
    return byDate.values.toList();
  }
  return result;
}

List<HealthPoint> pointsInRange(
  List<HealthPoint> points,
  int? days,
  DateTime now,
) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final from = days == null ? null : today.subtract(Duration(days: days - 1));
  final until = today.add(const Duration(days: 1));
  return points
      .where(
        (p) => (from == null || !p.at.isBefore(from)) && p.at.isBefore(until),
      )
      .toList();
}

// Calendar days, not the last seven measurements. Missing days are not zeroes.
List<HealthPoint> recentWeightWindow(List<HealthPoint> points) {
  if (points.isEmpty) return [];
  final last = DateTime.parse(points.last.date);
  final from = DateTime.utc(
    last.year,
    last.month,
    last.day,
  ).subtract(const Duration(days: 6));
  return points.where((p) => !p.at.isBefore(from)).toList();
}

double recentWeightAverage(List<HealthPoint> points) {
  final recent = recentWeightWindow(points);
  if (recent.isEmpty) return 0;
  return recent.fold<double>(0, (sum, p) => sum + p.value) / recent.length;
}

String shortDate(String date) {
  final d = DateTime.parse(date);
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
  return '${d.day} ${months[d.month - 1]}';
}

class FitnessTrends extends StatefulWidget {
  final CortexModel model;
  const FitnessTrends({super.key, required this.model});
  @override
  State<FitnessTrends> createState() => _FitnessTrendsState();
}

class _FitnessTrendsState extends State<FitnessTrends> {
  int? days;
  bool mmol = true;
  String glucoseContext = 'fasting';
  bool importing = false;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final allWeight = healthPoints(model.entries, TrendMetric.weight);
    final allGlucose = healthPoints(model.entries, TrendMetric.glucose);
    final allBP = healthPoints(model.entries, TrendMetric.bp);
    final now = DateTime.now();
    final weight = pointsInRange(allWeight, days, now);
    final glucose = pointsInRange(
      allGlucose.where((p) => p.context == glucoseContext).toList(),
      days,
      now,
    );
    final bp = pointsInRange(allBP, days, now);
    final goal = model.records('goal').firstOrNull?.data['weight'];
    return ListView(
      key: const PageStorageKey('fitness-trends'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      children: [
        titleText('See the bigger picture.'),
        const SizedBox(height: 7),
        caption('Small changes become clearer over time.'),
        const SizedBox(height: 16),
        SegmentedButton<int?>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
            ButtonSegment(value: 90, label: Text('90 days')),
            ButtonSegment(value: null, label: Text('All')),
          ],
          selected: {days},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => days = v.first),
        ),
        const SizedBox(height: 20),
        HealthTrendCard(
          key: ValueKey('weight-$days'),
          title: 'Weight',
          metric: TrendMetric.weight,
          points: weight,
          unit: 'kg',
          target: goal is num ? goal.toDouble() : null,
          summary: weight.isEmpty
              ? null
              : '${recentWeightAverage(weight).toStringAsFixed(1)} kg · 7-day average from ${recentWeightWindow(weight).length} weigh-in${recentWeightWindow(weight).length == 1 ? '' : 's'}, ending ${shortDate(weight.last.date)}',
          empty: 'No weight readings in this period.',
        ),
        const SizedBox(height: 18),
        HealthTrendCard(
          key: ValueKey('glucose-$days-$glucoseContext'),
          title: 'Blood glucose',
          metric: TrendMetric.glucose,
          points: glucose,
          unit: mmol ? 'mmol/L' : 'mg/dL',
          factor: mmol ? glucoseFactor : 1,
          controls: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: glucoseContext,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Reading type',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'fasting',
                          child: Text('Fasting'),
                        ),
                        DropdownMenuItem(
                          value: 'beforeMeal',
                          child: Text('Before a meal'),
                        ),
                        DropdownMenuItem(
                          value: 'afterMeal',
                          child: Text('After a meal'),
                        ),
                        DropdownMenuItem(
                          value: 'unspecified',
                          child: Text('Unspecified'),
                        ),
                      ],
                      onChanged: (v) => setState(() => glucoseContext = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => setState(() => mmol = !mmol),
                    child: Text(mmol ? 'mg/dL' : 'mmol/L'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
          empty:
              'No ${switch (glucoseContext) {
                'fasting' => 'fasting',
                'beforeMeal' => 'before-meal',
                'afterMeal' => 'after-meal',
                _ => 'unspecified',
              }} readings in this period.',
          summary:
              'Meal timing stays separate. Before a meal does not necessarily mean fasting.',
        ),
        const SizedBox(height: 18),
        HealthTrendCard(
          key: ValueKey('bp-$days'),
          title: 'Blood pressure',
          metric: TrendMetric.bp,
          points: bp,
          unit: 'mmHg',
          empty: 'No blood pressure readings in this period.',
          summary: bp.isEmpty
              ? null
              : '${(bp.fold<double>(0, (s, p) => s + p.value) / bp.length).round()}/${(bp.fold<double>(0, (s, p) => s + p.second!) / bp.length).round()} mmHg · average of ${bp.length} readings',
        ),
        const SizedBox(height: 20),
        caption(
          'Tap or slide across a chart to inspect a reading. Dashed gaps mean there are days without measurements.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: importing
              ? null
              : () async {
                  setState(() => importing = true);
                  await action(context, () async {
                    final message = await model.importHealth();
                    if (context.mounted) notice(context, message);
                  });
                  if (mounted) setState(() => importing = false);
                },
          icon: const Icon(Icons.favorite_outline, size: 18),
          label: Text(importing ? 'Importing…' : 'Import today’s Apple Health'),
        ),
        caption(
          'You can also tell Cortex a reading in chat. Include the glucose unit and whether it was fasting.',
        ),
      ],
    );
  }
}

class HealthTrendCard extends StatefulWidget {
  final String title, unit, empty;
  final TrendMetric metric;
  final List<HealthPoint> points;
  final String? summary;
  final Widget? controls;
  final double factor;
  final int? decimalPlaces;
  final double minimumWeightPadding;
  final double? target;
  const HealthTrendCard({
    super.key,
    required this.title,
    required this.metric,
    required this.points,
    required this.unit,
    required this.empty,
    this.summary,
    this.controls,
    this.factor = 1,
    this.decimalPlaces,
    this.minimumWeightPadding = .5,
    this.target,
  });
  @override
  State<HealthTrendCard> createState() => _HealthTrendCardState();
}

class _HealthTrendCardState extends State<HealthTrendCard> {
  String? selectedID;
  String value(HealthPoint p) => widget.metric == TrendMetric.bp
      ? '${p.value.round()}/${p.second!.round()}'
      : (p.value / widget.factor).toStringAsFixed(
          widget.decimalPlaces ?? (widget.unit == 'mg/dL' ? 0 : 1),
        );
  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final found = points.indexWhere((p) => p.id == selectedID);
    final index = found >= 0 ? found : points.length - 1;
    final point = points.isEmpty ? null : points[index];
    final color = widget.metric == TrendMetric.glucose ? glucoseColor : ink;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 15),
          if (widget.controls != null) widget.controls!,
          if (point == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: caption(widget.empty),
            ),
            if (widget.summary != null) caption(widget.summary!),
          ] else ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 7,
              children: [
                Text(
                  value(point),
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: caption(widget.unit),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '${point.date} · ${index == points.length - 1 ? 'Latest in this period' : 'Selected reading'}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            if (widget.metric == TrendMetric.bp)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 16,
                  children: const [
                    Text(
                      '● Top · systolic',
                      style: TextStyle(color: ink, fontSize: 12),
                    ),
                    Text(
                      '● Bottom · diastolic',
                      style: TextStyle(color: bpLower, fontSize: 12),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final plot = HealthChartPainter(
                  points: points,
                  selected: index,
                  metric: widget.metric,
                  factor: widget.factor,
                  target: widget.target,
                  color: color,
                  weightDecimals: widget.decimalPlaces ?? 1,
                  minimumWeightPadding: widget.minimumWeightPadding,
                );
                void select(Offset at) {
                  final width = max(1.0, constraints.maxWidth - 52);
                  final range = max(
                    1,
                    points.last.at.difference(points.first.at).inMilliseconds,
                  );
                  final ratio = ((at.dx - 40) / width).clamp(0.0, 1.0);
                  var nearest = 0;
                  var distance = double.infinity;
                  for (var i = 0; i < points.length; i++) {
                    final x = points.length == 1
                        ? .5
                        : points[i].at
                                  .difference(points.first.at)
                                  .inMilliseconds /
                              range;
                    if ((x - ratio).abs() < distance) {
                      nearest = i;
                      distance = (x - ratio).abs();
                    }
                  }
                  setState(() => selectedID = points[nearest].id);
                }

                return Semantics(
                  label:
                      '${widget.title}, ${value(point)} ${widget.unit}, ${point.date}. ${points.length} readings.',
                  onIncrease: index < points.length - 1
                      ? () => setState(() => selectedID = points[index + 1].id)
                      : null,
                  onDecrease: index > 0
                      ? () => setState(() => selectedID = points[index - 1].id)
                      : null,
                  child: GestureDetector(
                    onTapDown: (d) => select(d.localPosition),
                    onHorizontalDragUpdate: (d) => select(d.localPosition),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: CustomPaint(painter: plot),
                    ),
                  ),
                );
              },
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous ${widget.title.toLowerCase()} reading',
                  onPressed: index > 0
                      ? () => setState(() => selectedID = points[index - 1].id)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: caption('${index + 1} of ${points.length} readings'),
                  ),
                ),
                IconButton(
                  tooltip: 'Next ${widget.title.toLowerCase()} reading',
                  onPressed: index < points.length - 1
                      ? () => setState(() => selectedID = points[index + 1].id)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (widget.metric == TrendMetric.weight && points.length > 1) ...[
              Text(
                '${points.last.value - points.first.value >= 0 ? '+' : ''}${(points.last.value - points.first.value).toStringAsFixed(widget.decimalPlaces ?? 1)} kg in this period',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 5),
            ],
            if (widget.target != null)
              caption('Goal ${widget.target!.toStringAsFixed(1)} kg'),
            if (widget.summary != null) caption(widget.summary!),
            if (points.length == 1)
              caption(
                'One reading so far. The trend will appear as you add more.',
              ),
          ],
        ],
      ),
    );
  }
}

class HealthChartPainter extends CustomPainter {
  final List<HealthPoint> points;
  final int selected;
  final TrendMetric metric;
  final double factor;
  final double? target;
  final Color color;
  final int weightDecimals;
  final double minimumWeightPadding;
  HealthChartPainter({
    required this.points,
    required this.selected,
    required this.metric,
    required this.factor,
    required this.target,
    required this.color,
    this.weightDecimals = 1,
    this.minimumWeightPadding = .5,
  });
  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, top = 14.0, bottom = 28.0, right = 12.0;
    final width = size.width - left - right,
        height = size.height - top - bottom;
    final values = points
        .expand(
          (p) => [p.value / factor, if (p.second != null) p.second! / factor],
        )
        .toList();
    var minV = values.reduce(min), maxV = values.reduce(max);
    // Keep a distant goal from flattening normal day-to-day changes.
    final showTarget =
        target != null && target! >= minV - 2 && target! <= maxV + 2;
    if (showTarget) {
      minV = min(minV, target!);
      maxV = max(maxV, target!);
    }
    final pad = max(
      (maxV - minV) * .18,
      metric == TrendMetric.weight
          ? minimumWeightPadding
          : metric == TrendMetric.glucose
          ? (factor == 1 ? 5.0 : .3)
          : 5.0,
    );
    minV = metric == TrendMetric.weight ? max(0, minV - pad) : minV - pad;
    maxV += pad;
    final timeRange = max(
      1,
      points.last.at.difference(points.first.at).inMilliseconds,
    );
    double x(int i) =>
        left +
        (points.length == 1 || points.first.at == points.last.at
                ? .5
                : points[i].at.difference(points.first.at).inMilliseconds /
                      timeRange) *
            width;
    double y(double v) => top + (maxV - v) / (maxV - minV) * height;
    void text(String s, Offset pos, {Color c = muted, bool end = false}) {
      final p = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: c, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(end ? pos.dx - p.width : pos.dx, pos.dy));
    }

    void dashed(Offset a, Offset b, Color c) {
      final length = (b - a).distance;
      if (length == 0) return;
      final vector = (b - a) / length;
      for (double n = 0; n < length; n += 8) {
        canvas.drawLine(
          a + vector * n,
          a + vector * min(n + 4, length),
          Paint()
            ..color = c
            ..strokeWidth = 1.3,
        );
      }
    }

    for (var i = 0; i < 4; i++) {
      final v = maxV - (maxV - minV) * i / 3, yy = top + height * i / 3;
      canvas.drawLine(
        Offset(left, yy),
        Offset(size.width - right, yy),
        Paint()
          ..color = line
          ..strokeWidth = 1,
      );
      text(
        v.toStringAsFixed(
          metric == TrendMetric.weight
              ? weightDecimals
              : metric == TrendMetric.glucose && factor != 1
              ? 1
              : 0,
        ),
        Offset(left - 7, yy - 6),
        end: true,
      );
    }
    if (showTarget) {
      dashed(
        Offset(left, y(target!)),
        Offset(size.width - right, y(target!)),
        muted,
      );
      text(
        'Goal ${target!.toStringAsFixed(0)} kg',
        Offset(size.width - right, y(target!) - 14),
        end: true,
      );
    }
    canvas.drawLine(
      Offset(x(selected), top),
      Offset(x(selected), top + height),
      Paint()
        ..color = color.withValues(alpha: .15)
        ..strokeWidth = 1,
    );
    for (
      var series = 0;
      series < (metric == TrendMetric.bp ? 2 : 1);
      series++
    ) {
      final c = series == 0 ? color : bpLower;
      double val(int i) =>
          (series == 0 ? points[i].value : points[i].second!) / factor;
      for (var i = 0; i < points.length; i++) {
        final at = Offset(x(i), y(val(i)));
        if (i > 0 && metric != TrendMetric.glucose) {
          final previous = Offset(x(i - 1), y(val(i - 1)));
          if (DateTime.parse(
                points[i].date,
              ).difference(DateTime.parse(points[i - 1].date)).inDays >
              1) {
            dashed(previous, at, c.withValues(alpha: .45));
          } else {
            canvas.drawLine(
              previous,
              at,
              Paint()
                ..color = c
                ..strokeWidth = 2
                ..strokeCap = StrokeCap.round,
            );
          }
        }
        canvas.drawCircle(at, i == selected ? 5 : 3, Paint()..color = c);
        if (i == selected) {
          canvas.drawCircle(
            at,
            7,
            Paint()
              ..color = c.withValues(alpha: .18)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        }
      }
    }
    text(shortDate(points.first.date), Offset(left, size.height - 16));
    if (points.first.date != points.last.date) {
      text(
        shortDate(points.last.date),
        Offset(size.width - right, size.height - 16),
        end: true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant HealthChartPainter oldDelegate) => true;
}
