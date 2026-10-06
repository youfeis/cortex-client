import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../core/navigation.dart';
import '../../app/ui.dart';
import '../../remote_ui/remote_layout.dart';
import 'daily_routines.dart';
import 'todos.dart';

String planClock(int minute) =>
    '${clock(minute % 1440)}${minute >= 1440 ? ' +1 day' : ''}';

class TimeScreen extends StatefulWidget {
  final CortexModel model;
  final OpenChat onChat;
  final bool initialRoutines;
  const TimeScreen({
    super.key,
    required this.model,
    required this.onChat,
    this.initialRoutines = false,
  });

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  late bool showRoutines = widget.initialRoutines;
  CortexModel get model => widget.model;
  OpenChat get onChat => widget.onChat;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('To-dos & routines')),
      body: RefreshIndicator(
        onRefresh: model.refresh,
        child: RemoteLayout(
          page: 'time',
          slots: {
            'intro': Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(day()),
                const SizedBox(height: 10),
                titleText('One thing at a time.'),
                const SizedBox(height: 10),
                caption('Check off what you finish. Your progress stays here.'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('To-dos'),
                        icon: Icon(Icons.checklist),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Routines'),
                        icon: Icon(Icons.repeat),
                      ),
                    ],
                    selected: {showRoutines},
                    onSelectionChanged: (value) =>
                        setState(() => showRoutines = value.first),
                  ),
                ),
              ],
            ),
            'todos': showRoutines
                ? const SizedBox.shrink()
                : TodoList(model: model, onChat: onChat),
            'routines': !showRoutines
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DailyRoutines(model: model),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            onChat('Add or change a repeating routine: '),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Tell Cortex a routine'),
                      ),
                    ],
                  ),
            // Retain legacy slots so cached layouts remain compatible.
            // Calendar connections and alarms remain available in Settings.
            'plan': const SizedBox.shrink(),
            'calendars': const SizedBox.shrink(),
            'chat': const SizedBox.shrink(),
          },
        ),
      ),
    ),
  );
}
