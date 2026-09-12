import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cortex.dart';
import 'main.dart';
import 'quota.dart';
import 'ui.dart';

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
                'Choose any calendars below. Cortex keeps the next 30 days up to date when you open the app and while it stays open.',
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
                          ? 'Calendar access is on'
                          : 'Allow calendar access',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (m.calendarError != null) caption(m.calendarError!),
                    if (!m.calendarGranted) ...[
                      const SizedBox(height: 10),
                      caption(
                        m.calendarPermission == 'denied'
                            ? 'In iPhone Settings, give Cortex Full Access to Calendars.'
                            : 'Allow access to include your fixed events in your day.',
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: m.calendarSyncing
                            ? null
                            : () => m.calendarPermission == 'denied'
                                  ? native.invokeMethod('openAppSettings')
                                  : m.syncCalendars(
                                      requestAccess: true,
                                      refreshSources: true,
                                    ),
                        child: Text(
                          m.calendarPermission == 'denied'
                              ? 'Open Cortex settings'
                              : 'Allow calendars',
                        ),
                      ),
                    ] else ...[
                      if (m.calendarSynced != null)
                        caption(
                          'Last synced ${localDateTime(m.calendarSynced!)}',
                        ),
                      TextButton.icon(
                        onPressed: m.calendarSyncing
                            ? null
                            : () => m.syncCalendars(refreshSources: true),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Refresh now'),
                      ),
                    ],
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
              sectionHead('Missing Google events?'),
              caption(
                '1. Open iPhone Settings → Apps → Calendar → Calendar Accounts.\n2. Add both Google accounts, or open each existing account and turn Calendars on.\n3. Open Apple Calendar and check that the events appear there. Return here and refresh.',
              ),
              const SizedBox(height: 10),
              caption(
                'Signing in only inside the Google Calendar app does not share its events with Cortex. Work account rules may also restrict calendar access.',
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://support.google.com/calendar/answer/99358?co=GENIE.Platform%3DiOS&hl=en',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Google calendar setup guide'),
              ),
              const SizedBox(height: 10),
              caption(
                'Cortex reads these calendars. Changes made in Google or Apple Calendar arrive after iOS syncs them. All-day entries stay as reminders; they do not block the whole day.',
              ),
            ],
          ),
        ),
      );
    },
  );
}
