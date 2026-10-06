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

class TodoList extends StatefulWidget {
  final CortexModel model;
  final OpenChat onChat;
  const TodoList({super.key, required this.model, required this.onChat});
  @override
  State<TodoList> createState() => _TodoListState();
}

class _TodoListState extends State<TodoList> {
  final pendingWrites = <String>{};
  CortexModel get model => widget.model;
  OpenChat get onChat => widget.onChat;

  Future<void> toggle(Entry task, bool done) async {
    setState(() => pendingWrites.add(task.id));
    await action(context, () async {
      await model.api.call('POST', '/v1/tasks/${task.id}/complete', {
        'done': done,
      });
      await model.refresh();
    });
    if (mounted) setState(() => pendingWrites.remove(task.id));
  }

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
            Checkbox(
              key: ValueKey('todo-check-${task.id}'),
              value: task.data['done'] == true,
              onChanged: model.online && !pendingWrites.contains(task.id)
                  ? (value) => toggle(task, value ?? false)
                  : null,
              semanticLabel: task.data['title']?.toString() ?? 'To-do',
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
            if (pendingWrites.contains(task.id))
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
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
          'Tap a box to finish or reopen a to-do. Tell Cortex the item and deadline to add or change one.',
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
            initiallyExpanded: false,
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
