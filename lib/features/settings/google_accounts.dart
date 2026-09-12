import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';

class GoogleAccounts extends StatelessWidget {
  final CortexModel model;
  const GoogleAccounts({super.key, required this.model});
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Google Calendar',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        caption(
          'Link your personal and work accounts. Then ask Cortex to create, move or remove events.',
        ),
        for (final account in model.googleAccounts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline, color: muted),
            title: Text(account['email'] as String),
            subtitle: const Text('Calendar access connected'),
          ),
        if (model.googleError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: caption(model.googleError!),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => action(context, () async {
            final link = await model.api.call('POST', '/v1/google/link') as Map;
            final uri = Uri.parse(link['url'] as String);
            if (uri.scheme != 'https' || uri.host != 'accounts.google.com') {
              throw Exception('Invalid Google sign-in address');
            }
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              throw Exception('Could not open Google sign-in');
            }
          }),
          icon: const Icon(Icons.link),
          label: Text(
            model.googleAccounts.isEmpty
                ? 'Link Google account'
                : 'Link another Google account',
          ),
        ),
        const SizedBox(height: 8),
        caption(
          'Return here after Google sign-in. Your account appears automatically. Your work account may require administrator approval.',
        ),
      ],
    ),
  );
}
