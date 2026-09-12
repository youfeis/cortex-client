import '../time/alarms.dart';
import 'google_accounts.dart';
import '../fitness/health_access.dart';
import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../app/ui.dart';
import '../../app/avatars.dart';
import '../../core/quota.dart';
import '../time/calendars.dart';

import 'codex_login.dart';

class SettingsScreen extends StatelessWidget {
  final CortexModel model;
  const SettingsScreen({super.key, required this.model});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Memory & settings')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Panel(
            child: Row(
              children: [
                OwnerAvatar(model: model, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your space',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      caption(
                        model.ownerAvatarId == null
                            ? 'Your personal assistant'
                            : 'Your account photo · stored privately',
                      ),
                    ],
                  ),
                ),
                const CortexAvatar(size: 40),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label('YOUR PRIVATE CONNECTION'),
                const SizedBox(height: 10),
                const Text(
                  'This device is paired',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                caption(
                  'cortex.miaotutu.com\nYour private signing key stays on this device.',
                ),
              ],
            ),
          ),
          sectionHead('Codex account'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.loggedIn ? 'Connected' : 'Login needed',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (model.account?['account'] is Map &&
                    model.account!['account']['email'] != null)
                  caption(model.account!['account']['email'] as String),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => showLogin(context, model),
                  child: Text(
                    model.loggedIn ? 'Reconnect account' : 'Log in to Codex',
                  ),
                ),
              ],
            ),
          ),
          sectionHead('Phone permissions'),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: HealthAccess(model: model),
                ),
                const Divider(height: 1),
                AlarmAccess(model: model),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Calendars'),
                  subtitle: Text(
                    model.calendarGranted
                        ? 'Google connected · automatic sync'
                        : 'Link Google accounts to sync',
                  ),
                  onTap: () => openCalendars(context, model),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          caption(
            'Link your personal and work Google accounts below, then choose which calendars Cortex includes.',
          ),
          sectionHead('Google accounts'),
          GoogleAccounts(model: model),
          sectionHead('Saved memory'),
          caption(
            'Only routines, lasting changes, and things you ask to remember. Ask in chat to correct or forget a fact.',
          ),
          const SizedBox(height: 12),
          if (model.records('memory').isEmpty)
            const Panel(
              child: Text(
                'Routines, lasting changes, and things you ask Cortex to remember appear here.',
              ),
            ),
          for (final memory in model.records('memory'))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(child: Text(memory.data['text'] as String? ?? '')),
            ),
          sectionHead('Account usage'),
          Panel(child: QuotaPanel(model: model)),
          sectionHead('Sessions'),
          caption(
            'The main conversation always answers you. Focused helpers work in the background.',
          ),
          const SizedBox(height: 12),
          if (model.sessions.isEmpty)
            const Panel(
              child: Text('Your main session starts with your first message.'),
            ),
          for (final session in [
            ...model.sessions.where((s) => s['kind'] == 'main'),
            ...model.sessions.where((s) => s['kind'] != 'main'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session['kind'] == 'main'
                          ? 'Main conversation'
                          : session['title'] as String? ??
                                '${session['kind']} helper',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    if (session['kind'] != 'main') ...[
                      caption(
                        '${session['kind']} helper · ${session['status'] ?? 'ready'}',
                      ),
                      if ((session['summary'] as String? ?? '').isNotEmpty)
                        Text(
                          session['summary'] as String,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                    caption(contextLabel(session['context'])),
                    if (session['context'] is Map)
                      caption(
                        '${session['context']['used']} of ${session['context']['window']} tokens · latest reported snapshot',
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          caption(
            'Context can be compressed as a conversation grows. Saved memory stays in MongoDB. Only changed facts are sent again; helpers keep detailed task history. Context usage is separate from your account usage limit.',
          ),
          const SizedBox(height: 28),
        ],
      ),
    ),
  );
}
