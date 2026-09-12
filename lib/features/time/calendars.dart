import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../settings/google_accounts.dart';
import '../../core/quota.dart';
import '../../app/ui.dart';

void openCalendars(BuildContext context, CortexModel model) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => CalendarScreen(model: model)),
);

class CalendarScreen extends StatefulWidget {
  final CortexModel model;
  const CalendarScreen({super.key, required this.model});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.model.syncCalendars(refreshSources: true),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final m = widget.model;
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final c in m.calendars) {
        groups.putIfAbsent(c['sourceId'] as String, () => []).add(c);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Calendars')),
        body: RefreshIndicator(
          onRefresh: () => m.syncCalendars(refreshSources: true),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              titleText('Personal, work, all together.'),
              const SizedBox(height: 10),
              caption(
                'Google Calendar is your main calendar. Choose which calendars to include. Cortex checks for updates every five minutes, even when the app is closed.',
              ),
              const SizedBox(height: 18),
              Panel(
                color: soft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.calendarSyncing
                          ? 'Syncing…'
                          : m.calendarGranted
                          ? 'Connected to Google Calendar'
                          : 'Connect Google Calendar',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (m.calendarError != null) caption(m.calendarError!),
                    if (m.calendarSynced != null)
                      caption(
                        'Last synced ${localDateTime(m.calendarSynced!)}',
                      ),
                  ],
                ),
              ),
              for (final group in groups.values) ...[
                sectionHead(group.first['account'] as String),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    children: [
                      for (final c in group)
                        CheckboxListTile(
                          value:
                              m.selectedCalendars == null ||
                              m.selectedCalendars!.contains(c['id']),
                          title: Text(c['title'] as String),
                          subtitle: Text(
                            m.selectedCalendars == null ||
                                    m.selectedCalendars!.contains(c['id'])
                                ? '${c['count']} event entries · next 30 days'
                                : 'Not included',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: m.calendarSyncing
                              ? null
                              : (selected) {
                                  final ids =
                                      m.selectedCalendars?.toSet() ??
                                      m.calendars
                                          .map((e) => e['id'] as String)
                                          .toSet();
                                  selected == true
                                      ? ids.add(c['id'] as String)
                                      : ids.remove(c['id']);
                                  action(context, () => m.chooseCalendars(ids));
                                },
                        ),
                    ],
                  ),
                ),
              ],
              sectionHead('Google accounts'),
              GoogleAccounts(model: m),
              const SizedBox(height: 12),
              caption(
                'Changes you make in Google appear here automatically. Ask Cortex in chat to add, move or cancel events. All-day entries stay as reminders.',
              ),
            ],
          ),
        ),
      );
    },
  );
}
