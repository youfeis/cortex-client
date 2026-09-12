import 'package:flutter/material.dart';
import '../core/cortex.dart';
import '../main.dart';
import '../core/quota.dart';
import 'ui.dart';

String chatStatus(CortexModel model) {
  if (!model.online) return 'Reconnecting';
  if (!model.loggedIn) return 'Login needed';
  return switch (model.chat['status']) {
    'thinking' => 'Thinking',
    'working' => 'Working',
    'replying' => 'Replying',
    'steering' => 'Updating direction',
    'stopped' => 'Stopped',
    'error' => 'Needs attention',
    _ => 'Ready',
  };
}

double usageHeaderHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(32) + 28;

class AppUsageHeader extends StatelessWidget {
  final CortexModel model;
  const AppUsageHeader({super.key, required this.model});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final contextLeft = contextRemaining(model.chat['context']);
    final weekly = codexWeeklyQuota(model.quota);
    final expired = weekly?.resetPassed(now) ?? false;
    final weeklyLeft = expired || !model.loggedIn ? null : weekly?.remaining;
    final stale = quotaIsStale(model, now);
    final reset = weekly?.reset;
    // The year is unnecessary in this week's compact header; settings shows it.
    final resetText = reset == null
        ? 'Reset time unavailable'
        : localDateTime(reset).replaceFirst(' ${reset.toLocal().year},', ' ·');
    return SizedBox(
      height: usageHeaderHeight(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _UsageMeter(
                meterKey: const Key('main-context-progress'),
                label: 'Main context',
                valueLabel: contextLeft == null
                    ? '—'
                    : '~${(contextLeft * 100).round()}% left',
                fraction: contextLeft,
                subtitle: '● ${chatStatus(model)}',
                description:
                    '${contextLabel(model.chat['context'])}. ${chatStatus(model)}.',
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _UsageMeter(
                meterKey: const Key('codex-weekly-progress'),
                label: 'Codex weekly',
                valueLabel: weeklyLeft == null
                    ? '—'
                    : '${weeklyLeft.round()}%${stale ? ' cached' : ' left'}',
                fraction: weeklyLeft == null ? null : weeklyLeft / 100,
                subtitle: expired
                    ? 'Updating · $resetText'
                    : reset == null
                    ? resetText
                    : 'Resets $resetText',
                description:
                    'Codex weekly quota, shared across sessions. ${weeklyLeft == null ? 'Unavailable.' : '${weeklyLeft.round()} percent remaining.'} ${stale ? 'Last known usage.' : ''} ${reset == null ? 'Reset time unavailable.' : 'Resets ${localDateTime(reset)} in phone local time.'}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageMeter extends StatelessWidget {
  final Key meterKey;
  final String label, valueLabel, subtitle, description;
  final double? fraction;
  const _UsageMeter({
    required this.meterKey,
    required this.label,
    required this.valueLabel,
    required this.subtitle,
    required this.description,
    required this.fraction,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: description,
    excludeSemantics: true,
    child: Tooltip(
      message: description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                valueLabel,
                style: const TextStyle(fontSize: 10, height: 1.3, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            key: meterKey,
            value: fraction ?? 0,
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: line,
            color: ink,
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, height: 1.3, color: muted),
          ),
        ],
      ),
    ),
  );
}
