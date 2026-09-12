import 'package:flutter/material.dart';
import 'cortex.dart';
import 'main.dart';

String localDateTime(DateTime value) {
  final d = value.toLocal();
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
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${clock(d.hour * 60 + d.minute)}';
}

class QuotaWindow {
  final String bucket, name, limitId;
  final int? durationMinutes;
  final double? remaining;
  final DateTime? reset;
  const QuotaWindow(
    this.bucket,
    this.name,
    this.remaining,
    this.reset, {
    required this.limitId,
    this.durationMinutes,
  });
  bool resetPassed(DateTime now) => reset != null && !reset!.isAfter(now);
}

String quotaDuration(dynamic minutes, String fallback) {
  if (minutes is! num || minutes <= 0) return fallback;
  if (minutes == 10080) return 'Weekly';
  if (minutes % 1440 == 0) return '${minutes ~/ 1440}-day';
  if (minutes % 60 == 0) return '${minutes ~/ 60}-hour';
  return '$minutes-min';
}

List<QuotaWindow> quotaWindows(Map<String, dynamic>? response) {
  if (response == null) return [];
  final buckets = response['rateLimitsByLimitId'];
  final legacy = response['rateLimits'];
  final Map values = buckets is Map && buckets.isNotEmpty
      ? buckets
      : {(legacy is Map ? legacy['limitId'] : null) ?? 'codex': legacy};
  final result = <QuotaWindow>[];
  for (final entry in values.entries) {
    if (entry.value is! Map) continue;
    final bucket = entry.value as Map;
    final name =
        bucket['limitName'] ?? (entry.key == 'codex' ? 'Codex' : entry.key);
    for (final key in ['primary', 'secondary']) {
      final window = bucket[key];
      if (window is! Map) continue;
      final used = window['usedPercent'];
      final seconds = window['resetsAt'];
      result.add(
        QuotaWindow(
          name.toString(),
          quotaDuration(
            window['windowDurationMins'],
            key == 'primary' ? 'Primary' : 'Secondary',
          ),
          used is num && used.isFinite
              ? (100 - used).clamp(0, 100).toDouble()
              : null,
          seconds is num && seconds > 0 && seconds < 8640000000000
              ? DateTime.fromMillisecondsSinceEpoch(
                  (seconds * 1000).round(),
                  isUtc: true,
                ).toLocal()
              : null,
          limitId: entry.key.toString(),
          durationMinutes: (window['windowDurationMins'] as num?)?.toInt(),
        ),
      );
    }
  }
  return result;
}

QuotaWindow? codexWeeklyQuota(Map<String, dynamic>? response) {
  for (final window in quotaWindows(response)) {
    if (window.limitId == 'codex' && window.durationMinutes == 10080) {
      return window;
    }
  }
  return null;
}

bool quotaIsStale(CortexModel model, DateTime now) =>
    model.quotaFailed ||
    (model.quotaUpdated != null &&
        now.difference(model.quotaUpdated!) > const Duration(minutes: 2));

class QuotaPanel extends StatelessWidget {
  final CortexModel model;
  const QuotaPanel({super.key, required this.model});
  @override
  Widget build(BuildContext context) {
    final weekly = codexWeeklyQuota(model.quota);
    final now = DateTime.now();
    final expired = weekly?.resetPassed(now) ?? false;
    final remaining = expired ? null : weekly?.remaining;
    final stale = quotaIsStale(model, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Codex weekly',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Refresh quota',
              onPressed: model.quotaLoading
                  ? null
                  : () => model.readQuota(force: true),
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        Text(
          !model.loggedIn
              ? 'Connect Codex to see usage.'
              : expired
              ? 'Waiting for the next quota update'
              : remaining == null
              ? 'Weekly quota unavailable'
              : '${remaining.round()}% left${stale ? ' · last known' : ''}',
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (remaining ?? 0) / 100,
          backgroundColor: line,
          color: muted,
          semanticsLabel: 'Codex weekly quota remaining',
          semanticsValue: remaining == null
              ? 'Unavailable'
              : '${remaining.round()} percent',
        ),
        const SizedBox(height: 8),
        Text(
          weekly?.reset == null
              ? 'Reset time unavailable'
              : '${expired ? 'Reset was' : 'Resets'} ${localDateTime(weekly!.reset!)}',
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 8),
        const Text(
          'Shared across your Codex sessions. Reset times use your phone’s local time.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        if (model.quotaUpdated != null)
          Text(
            'Last checked ${localDateTime(model.quotaUpdated!)}',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
      ],
    );
  }
}
