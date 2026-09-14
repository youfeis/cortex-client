import 'package:flutter/material.dart';
import '../core/cortex.dart';
import 'ui.dart';

String compressionStatus(CortexModel model) {
  final job = model.chat['compaction'];
  return switch (job is Map ? job['status'] : null) {
    'saving' => 'Saving conversation…',
    'summarizing' => 'Writing a short handoff…',
    'starting' => 'Opening a fresh session…',
    'completed' => 'Context compressed · handoff saved',
    'failed' => 'Compression failed · conversation kept',
    _ => 'Save a handoff and start fresh',
  };
}

Future<void> showContextCompression(
  BuildContext context,
  CortexModel model,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: AnimatedBuilder(
      animation: model,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Compress context',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Cortex saves what it needs to continue, then opens a fresh main session. Your chat history stays here. Older details are retrieved from MongoDB when needed.',
            ),
            const SizedBox(height: 12),
            caption(
              'The handoff stays separate from permanent memories. Making it uses some tokens now and reduces the context carried into later replies. Weekly quota does not reset.',
            ),
            const SizedBox(height: 18),
            if (model.compressing) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                model.busy && !model.compressing
                    ? 'Available after this reply finishes.'
                    : compressionStatus(model),
              ),
            ),
            FilledButton.icon(
              key: const Key('compress-context-confirm'),
              onPressed:
                  !model.online ||
                      !model.loggedIn ||
                      model.busy ||
                      model.compressionSubmitting
                  ? null
                  : () async {
                      try {
                        await model.compressContext();
                      } catch (e) {
                        if (context.mounted) notice(context, e);
                      }
                    },
              icon: const Icon(Icons.compress_rounded),
              label: Text(
                model.compressing || model.compressionSubmitting
                    ? 'Compressing…'
                    : 'Compress context',
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
