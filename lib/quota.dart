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
  final String bucket, name;
  final double? remaining;
  final DateTime? reset;
  const QuotaWindow(this.bucket, this.name, this.remaining, this.reset);
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
  final Map values = buckets is Map && buckets.isNotEmpty
      ? buckets
      : {'codex': response['rateLimits']};
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
        ),
      );
    }
  }
  return result;
}

class QuotaPanel extends StatelessWidget {
  final CortexModel model;
  final bool compact;
  const QuotaPanel({super.key, required this.model, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final windows = quotaWindows(model.quota);
    final now = DateTime.now();
    final stale =
        model.quotaFailed ||
        (model.quotaUpdated != null &&
            now.difference(model.quotaUpdated!) > const Duration(minutes: 2));
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final visible = compact ? windows.take(keyboard ? 0 : 2) : windows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Quota left · account-wide',
                style: TextStyle(
                  fontSize: compact ? 11 : 13,
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (compact)
              InkWell(
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  model.readQuota(force: true);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                        child: AnimatedBuilder(
                          animation: model,
                          builder: (_, _) => QuotaPanel(model: model),
                        ),
                      ),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Details', style: TextStyle(fontSize: 12)),
                ),
              )
            else
              IconButton(
                tooltip: 'Refresh quota',
                onPressed: model.quotaLoading
                    ? null
                    : () => model.readQuota(force: true),
                icon: const Icon(Icons.refresh, size: 20),
              ),
          ],
        ),
        if (windows.isEmpty && !(compact && keyboard))
          Text(
            !model.loggedIn
                ? 'Connect Codex to see usage.'
                : model.quotaLoading
                ? 'Checking usage…'
                : 'Usage is not available yet.',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        for (final window in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${windows.map((w) => w.bucket).toSet().length > 1 ? '${window.bucket} · ' : ''}${window.name} · ${window.resetPassed(now)
                      ? 'awaiting update'
                      : window.remaining == null
                      ? 'unavailable'
                      : '${window.remaining!.round()}% left${stale ? ' (last known)' : ''}'}',
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  window.reset == null
                      ? 'Reset time unavailable'
                      : '${window.resetPassed(now) ? 'Reset was' : 'Resets'} ${localDateTime(window.reset!)}',
                  style: TextStyle(fontSize: compact ? 11 : 12, color: muted),
                ),
              ],
            ),
          ),
        if (!compact) ...[
          const SizedBox(height: 8),
          const Text(
            'Reset times use your phone’s local time. This quota is shared by all Codex sessions on your account.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          if (model.quotaUpdated != null)
            Text(
              'Last checked ${localDateTime(model.quotaUpdated!)}${stale ? ' · refresh needed' : ''}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
        ],
      ],
    );
  }
}
