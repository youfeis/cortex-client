import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';

Future<void> showLogin(BuildContext context, CortexModel model) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LoginSheet(model: model),
    );

class LoginSheet extends StatefulWidget {
  final CortexModel model;
  const LoginSheet({super.key, required this.model});
  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  Map<String, dynamic>? login;
  String? error;
  Timer? timer;
  bool done = false;
  bool starting = false;
  int attempt = 0;
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    if (starting) return;
    final generation = ++attempt;
    final previous = login?['loginId'];
    timer?.cancel();
    setState(() {
      starting = true;
      error = null;
      login = null;
    });
    try {
      if (previous != null) {
        await widget.model.api
            .call('POST', '/v1/account/cancel', {'loginId': previous})
            .catchError((_) => null);
      }
      final value =
          await widget.model.api.call('POST', '/v1/account/login') as Map;
      if (!mounted || generation != attempt) {
        if (value['loginId'] != null) {
          await widget.model.api
              .call('POST', '/v1/account/cancel', {'loginId': value['loginId']})
              .catchError((_) => null);
        }
        return;
      }
      setState(() => login = Map<String, dynamic>.from(value));
      timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && generation == attempt) setState(() => starting = false);
    }
  }

  Future<void> poll() async {
    try {
      await widget.model.readAccount();
      if (widget.model.loggedIn && mounted) {
        timer?.cancel();
        setState(() => done = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    attempt++;
    timer?.cancel();
    if (!done && login?['loginId'] != null) {
      widget.model.api
          .call('POST', '/v1/account/cancel', {'loginId': login!['loginId']})
          .catchError((_) => null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: titleText(
                  done ? 'Codex is connected' : 'Connect your Codex account',
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!done) ...[
            Panel(
              color: soft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'One-time ChatGPT setup',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  caption(
                    'In ChatGPT, open Settings → Security and enable “Device code authorization for Codex”. Then return here and get a new code.',
                  ),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://chatgpt.com/#settings/Security'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open ChatGPT settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (done) ...[
            caption('You can return to your conversation now.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to chat'),
            ),
          ] else if (error != null) ...[
            Text(error!),
            const SizedBox(height: 12),
            caption(
              'If device-code login is disabled, enable it in your ChatGPT security settings, then try again.',
            ),
          ] else if (login == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            caption(
              '1. Copy this code.\n2. Open the login page and sign in.\n3. Enter the code, then come back here.',
            ),
            const SizedBox(height: 22),
            Panel(
              color: soft,
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      login!['userCode']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 26,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy login code',
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: login!['userCode'] as String),
                    ),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final uri = Uri.parse(login!['verificationUrl'] as String);
                  if (uri.scheme != 'https' || uri.host != 'auth.openai.com') {
                    if (context.mounted) {
                      notice(
                        context,
                        'Unexpected login address. Please retry.',
                      );
                    }
                    return;
                  }
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('Open Codex login'),
              ),
            ),
            const SizedBox(height: 12),
            caption(
              'Waiting for login… Your login stays on your private server.',
            ),
          ],
          if (!done && !starting) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: start,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Get a new login code'),
            ),
            caption(
              'If OpenAI says device-code login is disabled, enable the setting above first. A fresh code replaces the previous one.',
            ),
          ],
          const SizedBox(height: 18),
        ],
      ),
    ),
  );
}
