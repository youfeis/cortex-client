import 'package:flutter/material.dart';
import '../../app/ui.dart';
import '../../core/cortex.dart';
import '../../main.dart';

class FocusPanel extends StatelessWidget {
  const FocusPanel({
    super.key,
    required this.model,
    this.compact = false,
    this.onFinished,
  });
  final CortexModel model;
  final bool compact;
  final VoidCallback? onFinished;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final focus = model.taskFocus, item = focus.current;
      if (!focus.visible || item == null) return const SizedBox.shrink();
      final end = DateTime.tryParse(
        item['expectedEnd'] as String? ?? '',
      )?.toLocal();
      final paused = !focus.active;
      final late = end != null && end.isBefore(DateTime.now());
      final detail = paused
          ? 'Paused. A break is okay.'
          : late
          ? 'Still unconfirmed. Are you doing okay?'
          : end == null
          ? 'One thing at a time.'
          : 'Aim for ${clock(end.hour * 60 + end.minute)}';
      Future<void> respond(String action) async {
        await focus.act(action);
        await model.refresh().catchError((_) {});
        if (action == 'complete' || action == 'cancel') onFinished?.call();
      }

      final actions = Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: () => action(context, () => respond('complete')),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Done'),
          ),
          TextButton.icon(
            onPressed: () => action(context, () => respond('extend')),
            icon: const Icon(Icons.more_time, size: 18),
            label: Text(paused ? 'Resume · 15 min' : 'Still working'),
          ),
          if (!paused)
            TextButton.icon(
              onPressed: () => action(context, () => respond('pause')),
              icon: const Icon(Icons.pause, size: 18),
              label: const Text('Need a break'),
            ),
          if (paused)
            TextButton(
              onPressed: () => action(context, () => respond('cancel')),
              child: const Text('Stop tracking'),
            ),
        ],
      );
      if (compact) {
        return Material(
          color: soft,
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              builder: (_) => Padding(
                padding: const EdgeInsets.all(20),
                child: FocusPanel(
                  model: model,
                  onFinished: () => Navigator.pop(context),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    paused ? Icons.pause_circle_outline : Icons.timelapse,
                    size: 21,
                    color: muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionHead(paused ? 'Take a breath' : 'Your current task'),
          Panel(
            color: soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] as String,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(detail),
                actions,
                if (focus.pending)
                  caption('Saved on your phone · sync pending'),
                if (focus.active && focus.notificationCount == 0) ...[
                  caption('Reminders need notification permission.'),
                  TextButton(
                    onPressed: () => action(
                      context,
                      () => focus.sync(requestPermission: true),
                    ),
                    child: const Text('Enable check-ins'),
                  ),
                ],
                if (focus.error != null) caption(focus.error!),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class FocusSettings extends StatelessWidget {
  const FocusSettings({super.key, required this.model});
  final CortexModel model;
  @override
  Widget build(BuildContext context) {
    final focus = model.taskFocus;
    final through = DateTime.tryParse(focus.scheduledThrough ?? '')?.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHead('Task check-ins'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                focus.permission == 'authorized'
                    ? 'Notifications allowed'
                    : focus.permission == 'denied'
                    ? 'Notifications are off'
                    : 'Allow gentle reminders',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              caption(
                'Tell Cortex “I’m starting…” or tap Start on a task. After its planned finish, I’ll check in every 15 minutes until you finish or pause.',
              ),
              const SizedBox(height: 8),
              caption(
                'A Live Activity keeps the task on your Lock Screen for up to 8 hours. Reminders are scheduled on this phone in advance and refreshed when Cortex opens. Focus and notification settings control alerts.',
              ),
              if (through != null && focus.active)
                caption(
                  'Reminders scheduled through ${through.day}/${through.month} · ${clock(through.hour * 60 + through.minute)}.',
                ),
              if (focus.permission == 'authorized')
                caption(
                  focus.liveEnabled
                      ? 'Live Activities available'
                      : 'Enable Live Activities in iPhone Settings for the task card.',
                ),
              TextButton(
                onPressed: () => action(
                  context,
                  () =>
                      focus.permission == 'denied' ||
                          focus.permission == 'authorized'
                      ? native.invokeMethod<void>('openAppSettings')
                      : focus.sync(requestPermission: true),
                ),
                child: Text(
                  focus.permission == 'denied' ||
                          focus.permission == 'authorized'
                      ? 'Open iPhone settings'
                      : 'Allow notifications',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
