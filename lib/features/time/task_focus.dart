import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/ui.dart';
import '../../core/cortex.dart';
import '../../main.dart';

Future<void> postponeFocus(
  BuildContext context,
  CortexModel model,
  Map<String, dynamic> item,
) async {
  final controller = TextEditingController();
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Postpone ${item['title']}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            item['preview'] == true
                ? 'Try a reason or new time. This preview won’t change your real plan.'
                : 'What changed? When would work better?',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'I’m tired. Give me an hour.',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(sheetContext, controller.text.trim());
              }
            },
            child: const Text('Send to Cortex'),
          ),
        ],
      ),
    ),
  );
  // Let the closing sheet release its TextField before disposing the controller.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  if (reason == null || !context.mounted) return;
  await action(
    context,
    () => model.taskFocus.act(
      'postpone',
      id: item['id'] as String,
      reason: reason,
    ),
  );
}

class FocusPanel extends StatefulWidget {
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
  State<FocusPanel> createState() => _FocusPanelState();
}

class _FocusPanelState extends State<FocusPanel> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && widget.model.taskFocus.visible) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final focus = widget.model.taskFocus,
          items = widget.model.taskFocus.visibleTasks;
      if (items.isEmpty) return const SizedBox.shrink();
      if (widget.compact) {
        return Material(
          color: soft,
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              builder: (sheetContext) => SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: FocusPanel(
                    model: widget.model,
                    onFinished: () {
                      if (!focus.visible) Navigator.pop(sheetContext);
                    },
                  ),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.timelapse, size: 21, color: muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items.length == 1
                              ? items.first['title'] as String
                              : '${items.length} tasks · ${items.first['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          focus.pending
                              ? 'Saved on phone · planning update pending'
                              : 'Tap to review your task timers',
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
          sectionHead(
            items.length == 1 ? 'Your current task' : 'Your overlapping tasks',
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(context, item),
            ),
          if (focus.pending)
            caption(
              'Saved on this phone · chat planning will follow when connected.',
            ),
          if (focus.error != null) caption(focus.error!),
        ],
      );
    },
  );
  Widget _card(BuildContext context, Map<String, dynamic> item) {
    final focus = widget.model.taskFocus;
    final status = item['status'];
    final active = status == 'active', ready = status == 'ready';
    final end = DateTime.tryParse(
      item['expectedEnd'] as String? ?? '',
    )?.toLocal();
    final start = DateTime.tryParse(
      item['startedAt'] as String? ?? '',
    )?.toLocal();
    final now = DateTime.now(),
        left = end?.difference(DateTime.now()).inMinutes;
    final detail = active
        ? (left != null && left >= 0
              ? '$left min remaining · until ${clock(end!.hour * 60 + end.minute)}'
              : 'Time’s up. Still working? Are you doing okay?')
        : ready
        ? 'Ready when you are. Tap “I’ve started”.'
        : status == 'postponed'
        ? (item['preview'] == true
              ? 'Preview postponed · your real plan is unchanged.'
              : 'Postponed · Cortex will review your reason in chat.')
        : 'Paused. A break is okay.';
    Future<void> respond(String command, [int minutes = 15]) async {
      await focus.act(command, id: item['id'] as String, minutes: minutes);
      await widget.model.refresh().catchError((_) {});
      if (command == 'complete' || command == 'cancel') {
        widget.onFinished?.call();
      }
    }

    return Panel(
      color: soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['title'] as String,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(detail),
          if (active && start != null && end != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value:
                  end.difference(now).inSeconds /
                          end.difference(start).inSeconds.clamp(1, 100000) >
                      1
                  ? 1
                  : (end.difference(now).inSeconds /
                            end.difference(start).inSeconds.clamp(1, 100000))
                        .clamp(0, 1),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (active)
                TextButton.icon(
                  onPressed: () => action(context, () => respond('complete')),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Completed!'),
                )
              else
                TextButton.icon(
                  onPressed: () => action(context, () => respond('begin')),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(ready ? 'I’ve started' : 'Resume'),
                ),
              TextButton(
                onPressed: () => postponeFocus(context, widget.model, item),
                child: const Text('Postpone'),
              ),
              if (active)
                TextButton(
                  onPressed: () => action(context, () => respond('pause')),
                  child: const Text('Take a break'),
                ),
              if (!active && !ready)
                TextButton(
                  onPressed: () => action(context, () => respond('cancel')),
                  child: const Text('Stop tracking'),
                ),
            ],
          ),
          if (active)
            Wrap(
              spacing: 8,
              children: [
                for (final minutes in [5, 10, 15])
                  OutlinedButton(
                    onPressed: () =>
                        action(context, () => respond('extend', minutes)),
                    child: Text('+$minutes min'),
                  ),
              ],
            ),
          if (item['planningStatus'] == 'pending')
            caption('Planning update queued for chat.'),
          if (item['planningStatus'] == 'sent')
            caption(
              'Update sent to chat · see Cortex’s reply for the new arrangement.',
            ),
          if (item['planningStatus'] == 'needs_review' ||
              item['planningStatus'] == 'forwarding')
            caption(
              'Task update saved. Check chat before relying on a new arrangement.',
            ),
          if (item['preview'] == true)
            caption('Preview only · excluded from planning and statistics'),
          if (focus.notificationCount == 0 && (active || ready))
            TextButton(
              onPressed: () =>
                  action(context, () => focus.sync(requestPermission: true)),
              child: const Text('Enable check-ins'),
            ),
        ],
      ),
    );
  }
}

class FocusSettings extends StatelessWidget {
  const FocusSettings({super.key, required this.model});
  final CortexModel model;
  @override
  Widget build(BuildContext context) {
    final focus = model.taskFocus;
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
                'One Lock Screen card shows two tasks side by side. Each has a progress bar and large buttons. The clock-arrow button postpones a task. Extra tasks open in Cortex.',
              ),
              const SizedBox(height: 8),
              caption(
                'Check-ins arrive at the expected finish, 10 minutes later, then every 15 minutes. Pausing or postponing stops reminders but keeps the unfinished task on the card. Completing or stopping tracking removes it.',
              ),
              const SizedBox(height: 8),
              caption(
                'Reopening Cortex restores unfinished tasks, even offline. iOS can remove a card after 8 hours or when you dismiss it. Focus and notification settings control alerts. Planning updates need a connection.',
              ),
              if (focus.visible) ...[
                const SizedBox(height: 12),
                Text(
                  focus.liveActive
                      ? 'Task card is available'
                      : focus.liveState == 'disabled'
                      ? 'Live Activities are off in iPhone settings'
                      : 'Task card is not showing',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                FilledButton.icon(
                  onPressed: () => action(context, focus.restore),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restore task card'),
                ),
              ],
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
              TextButton(
                onPressed: () => action(context, focus.preview),
                child: const Text('Preview overlapping task card'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
