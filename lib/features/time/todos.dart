import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../core/navigation.dart';
import '../../core/quota.dart';
import '../../app/ui.dart';

DateTime? todoDeadline(Entry task) {
  final value = task.data['deadline']?.toString() ?? '';
  final date = DateTime.tryParse(value);
  if (date == null) return null;
  return value.length == 10
      ? DateTime(date.year, date.month, date.day + 1)
      : date.toLocal();
}

bool todoIsDueToday(Entry task, DateTime now) {
  final value = task.data['deadline']?.toString() ?? '';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  final date = value.length == 10 ? parsed : parsed.toLocal();
  return day(date) == day(now);
}

String todoDueLabel(Entry task, DateTime now) {
  final value = task.data['deadline']?.toString() ?? '';
  final end = todoDeadline(task);
  if (end == null) return 'Deadline needed';
  final parsed = DateTime.parse(value);
  final date = value.length == 10 ? parsed : parsed.toLocal();
  final text = value.length == 10
      ? localDateTime(date).split(',').first
      : localDateTime(date);
  if (task.data['done'] == true) return 'Was due $text';
  return '${!end.isAfter(now)
      ? 'Overdue'
      : day(date) == day(now)
      ? 'Due today'
      : 'Due'} · $text';
}

bool todoCompletedToday(Entry task, DateTime now) {
  final at = DateTime.tryParse(task.data['completedAt']?.toString() ?? '');
  return task.data['done'] == true &&
      at != null &&
      day(at.toLocal()) == day(now);
}

class TodoList extends StatelessWidget {
  final CortexModel model;
  final OpenChat onChat;
  const TodoList({super.key, required this.model, required this.onChat});
  @override
  Widget build(BuildContext context) {
    final tasks = model.records('task').toList()
      ..sort(
        (a, b) => (todoDeadline(a) ?? DateTime(9999)).compareTo(
          todoDeadline(b) ?? DateTime(9999),
        ),
      );
    final pending = tasks.where((t) => t.data['done'] != true).toList();
    final completed = tasks.where((t) => t.data['done'] == true).toList();
    final now = DateTime.now();
    final doneToday = completed
        .where((t) => todoCompletedToday(t, now))
        .toList();
    final olderDone = completed
        .where((t) => !todoCompletedToday(t, now))
        .toList();
    final today = pending.where((t) => todoIsDueToday(t, now)).toList();
    final other = pending.where((t) => !todoIsDueToday(t, now)).toList();
    Widget row(Entry task) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(
                task.data['done'] == true
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                size: 19,
                color: muted,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.data['title']?.toString() ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: task.data['done'] == true
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  caption(
                    todoCompletedToday(task, now)
                        ? 'Completed today · ${todoDueLabel(task, now)}'
                        : todoDueLabel(task, now),
                  ),
                ],
              ),
            ),
            if (task.data['done'] != true && !model.taskFocus.visible)
              IconButton(
                tooltip: 'Start this task',
                onPressed: () => action(
                  context,
                  () => model.taskFocus.start(
                    title: task.data['title'] as String,
                    taskId: task.id,
                    minutes: (task.data['minutes'] as num?)?.toInt() ?? 25,
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline, size: 22),
              ),
            IconButton(
              tooltip: 'Discuss this to-do',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChat(
                'About my to-do “${task.data['title']}” (due ${task.data['deadline']}): ',
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 19),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHead(
          'To-do list',
          trailing: Text(
            '${pending.length} open',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ),
        caption(
          'Tell Cortex the item and deadline. Ask in chat to change it or mark it done.',
        ),
        const SizedBox(height: 12),
        sectionHead('Due today', trailing: Text('${today.length}')),
        if (today.isEmpty)
          const Panel(
            child: Text('Nothing due today. A little breathing room.'),
          ),
        for (final task in today) row(task),
        sectionHead(
          'Done today',
          trailing: Text('${doneToday.length} completed'),
        ),
        if (doneToday.isEmpty)
          caption('Finished tasks will stay here, crossed out.'),
        for (final task in doneToday) row(task),
        if (other.isNotEmpty) sectionHead('Other deadlines'),
        for (final task in other) row(task),
        if (olderDone.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: true,
            title: Text('Other completed tasks · ${olderDone.length}'),
            children: [for (final task in olderDone) row(task)],
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => onChat('Add a to-do: '),
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('Tell Cortex a to-do'),
        ),
      ],
    );
  }
}
