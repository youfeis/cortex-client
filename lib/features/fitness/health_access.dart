import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../core/quota.dart';
import '../../app/ui.dart';

class HealthAccess extends StatelessWidget {
  final CortexModel model;
  const HealthAccess({super.key, required this.model});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.favorite_outline, color: muted),
        title: const Text('Apple Health'),
        subtitle: Text(
          model.healthSyncing
              ? 'Syncing automatically…'
              : switch (model.healthPermission) {
                  'setupNeeded' => 'Permission setup needed',
                  'requested' =>
                    model.healthHasData
                        ? 'Shared data · automatic sync'
                        : 'Access requested · no shared data found',
                  'unavailable' => 'Unavailable on this device',
                  _ => 'Checking access…',
                },
        ),
        trailing: model.healthPermission == 'setupNeeded'
            ? TextButton(
                onPressed: model.healthSyncing
                    ? null
                    : () => model.syncHealth(requestAccess: true),
                child: const Text('Allow'),
              )
            : null,
      ),
      if (model.healthError != null)
        caption(model.healthError!)
      else if (model.healthSyncedAt != null)
        caption('Last checked ${localDateTime(model.healthSyncedAt!)}'),
      if (model.healthPermission == 'requested')
        TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            useSafeArea: true,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleText('Your Health permissions'),
                  const SizedBox(height: 12),
                  caption(
                    'In Apple Health, tap your profile → Apps → Cortex. Choose the data you want to share.\n\nApple keeps the individual permission choices private. Cortex can only see the readings you allow.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Got it'),
                  ),
                ],
              ),
            ),
          ),
          child: const Text('Manage Health access'),
        ),
    ],
  );
}
