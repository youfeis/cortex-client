import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cortex.dart';
import 'main.dart';
import 'ui.dart';
import 'quota.dart';
import 'app_header.dart';
import 'calendars.dart';
import 'space.dart';

class PairScreen extends StatefulWidget {
  final CortexModel model;
  const PairScreen({super.key, required this.model});
  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final code = TextEditingController();
  bool pairing = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> pair() async {
    setState(() {
      pairing = true;
      error = null;
    });
    try {
      await widget.model.pair(code.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          pairing = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.psychology_outlined, size: 52, color: ink),
              const SizedBox(height: 28),
              label('JUST FOR YOU'),
              const SizedBox(height: 12),
              const Text(
                'A little less\nto hold in your head.',
                style: TextStyle(
                  fontSize: 33,
                  height: 1.16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 20),
              caption('External Prefrontal Cortex'),
              const SizedBox(height: 36),
              titleText('Pair this iPhone'),
              const SizedBox(height: 10),
              caption(
                'Paste your one-time pairing code. This device will get its own private key.',
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('pairing-code'),
                controller: code,
                enabled: !pairing,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Pairing code',
                  suffixIcon: IconButton(
                    tooltip: 'Paste code',
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (data?.text != null) {
                        code.text = data!.text!.trim();
                      }
                    },
                    icon: const Icon(Icons.content_paste_outlined),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('pair-device'),
                  onPressed: pairing ? null : pair,
                  child: Text(pairing ? 'Pairing…' : 'Pair my device'),
                ),
              ),
              const SizedBox(height: 20),
              caption('cortex.miaotutu.com · Private connection'),
            ],
          ),
        ),
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  final CortexModel model;
  const HomeScreen({super.key, required this.model});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  final chatKey = GlobalKey<ChatScreenState>();
  void chat(String prompt, {bool photo = false}) {
    setState(() => tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      chatKey.currentState?.prepare(prompt, photo: photo);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 56,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(usageHeaderHeight(context)),
        child: AppUsageHeader(model: widget.model),
      ),
      title: const Row(
        children: [
          Icon(Icons.psychology_outlined, size: 30),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('External', style: TextStyle(fontSize: 13, color: muted)),
                Text(
                  'Prefrontal Cortex',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Memory and settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(model: widget.model),
            ),
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: IndexedStack(
        index: tab,
        children: [
          ChatScreen(key: chatKey, model: widget.model),
          SpaceScreen(model: widget.model, onChat: chat),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => tab = value);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
          label: 'Chat',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view_rounded),
          label: 'My space',
        ),
      ],
    ),
  );
}

class Attachment {
  final Uint8List bytes;
  String? id;
  Attachment(this.bytes);
}

class ChatScreen extends StatefulWidget {
  final CortexModel model;
  const ChatScreen({super.key, required this.model});
  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final draft = TextEditingController(), scroll = ScrollController();
  final focus = FocusNode();
  final images = <Attachment>[];
  bool sending = false;
  String? error;
  int previousCount = 0;
  @override
  void initState() {
    super.initState();
    widget.model.addListener(changed);
  }

  @override
  void dispose() {
    widget.model.removeListener(changed);
    draft.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  void changed() {
    final nearBottom =
        !scroll.hasClients ||
        scroll.position.maxScrollExtent - scroll.offset < 180;
    if (nearBottom || previousCount == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
    previousCount = widget.model.messages.length;
  }

  void prepare(String text, {bool photo = false}) {
    if (draft.text.trim().isEmpty) {
      draft.text = text;
    } else if (text.isNotEmpty) {
      draft.text += '\n$text';
    }
    if (photo) {
      pick();
    } else {
      focus.requestFocus();
    }
  }

  Future<void> pick() async {
    if (images.length >= 4) {
      notice(context, 'Up to four photos per message.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo library'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) {
      return;
    }
    try {
      final picker = ImagePicker();
      final picked = source == ImageSource.camera
          ? [
              ?await picker.pickImage(
                source: source,
                maxWidth: 1800,
                maxHeight: 1800,
                imageQuality: 82,
              ),
            ]
          : await picker.pickMultiImage(
              maxWidth: 1800,
              maxHeight: 1800,
              imageQuality: 82,
              limit: (4 - images.length) < 2 ? 2 : 4 - images.length,
            );
      for (final file in picked.take(4 - images.length)) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 6 * 1024 * 1024) {
          throw Exception('Choose a smaller photo.');
        }
        if (mounted) {
          setState(() => images.add(Attachment(bytes)));
        }
      }
    } catch (e) {
      if (mounted) {
        notice(context, e);
      }
    }
  }

  Future<void> send() async {
    if (sending || (draft.text.trim().isEmpty && images.isEmpty)) {
      return;
    }
    final text = draft.text.trim(),
        selected = List<Attachment>.from(images),
        steer = widget.model.busy;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      for (final image in selected) {
        image.id ??= await widget.model.api.upload(image.bytes);
      }
      await widget.model.send(
        text,
        selected.map((e) => e.id!).toList(),
        steer: steer,
      );
      if (mounted) {
        setState(() {
          if (draft.text.trim() == text) {
            draft.clear();
          }
          images.removeWhere(selected.contains);
          sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          sending = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final status = chatStatus(m);
    return Column(
      children: [
        const Divider(height: 1),
        if (!m.loggedIn)
          Container(
            color: soft,
            padding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Connect Codex to start chatting.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => showLogin(context, m),
                  child: const Text('Log in'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            children: [
              if (m.messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.psychology_outlined,
                        size: 42,
                        color: muted,
                      ),
                      const SizedBox(height: 18),
                      titleText('What’s on your mind?'),
                      const SizedBox(height: 12),
                      caption(
                        'Tell me what happened, send a food photo,\nor ask me to help with your day.',
                      ),
                    ],
                  ),
                ),
              for (final message in m.messages)
                Align(
                  alignment: message['role'] == 'user'
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .85,
                    ),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: message['role'] == 'user' ? soft : Colors.white,
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (((message['images'] ?? []) as List).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final id in message['images'] as List)
                                  Photo(model: m, id: id as String, size: 105),
                              ],
                            ),
                          ),
                        if ((message['text'] as String? ?? '').isNotEmpty)
                          MarkdownBody(
                            data: message['text'] as String,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                fontSize: 15,
                                color: ink,
                                height: 1.5,
                              ),
                            ),
                            onTapLink: (_, href, _) {
                              if (href != null &&
                                  Uri.tryParse(href)?.scheme == 'https') {
                                launchUrl(
                                  Uri.parse(href),
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              if ((m.chat['text'] as String? ?? '').isNotEmpty)
                Panel(child: MarkdownBody(data: m.chat['text'] as String)),
              if (m.busy && (m.chat['text'] as String? ?? '').isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const SizedBox(width: 10),
                      caption('$status…'),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (error != null || m.chat['error'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(
              error ?? m.chat['error'] as String,
              style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
            ),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (images.isNotEmpty)
                SizedBox(
                  height: 84,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final image in images)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  image.bytes,
                                  width: 78,
                                  height: 78,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  tooltip: 'Remove photo',
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                  ),
                                  onPressed: sending
                                      ? null
                                      : () => setState(
                                          () => images.remove(image),
                                        ),
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: draft,
                focusNode: focus,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Tell me, or show me…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Camera or photo library',
                    onPressed: sending ? null : pick,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  const Spacer(),
                  if (m.busy)
                    IconButton(
                      tooltip: 'Stop reply',
                      onPressed: () => action(context, m.stop),
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  FilledButton(
                    onPressed: !m.loggedIn || sending ? null : send,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                    ),
                    child: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : m.busy
                        ? const Text('Steer')
                        : const Icon(Icons.arrow_upward_rounded, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
                ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('Import Apple Health'),
                  subtitle: const Text('Today’s shared readings and activity'),
                  onTap: () => action(context, () async {
                    final text = await model.importHealth();
                    if (context.mounted) {
                      notice(context, text);
                    }
                  }),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Calendars'),
                  subtitle: const Text(
                    'Automatic sync · choose personal and work',
                  ),
                  onTap: () => openCalendars(context, model),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          caption(
            'Enable both Google accounts in iPhone Calendar settings, then choose which calendars Cortex includes.',
          ),
          sectionHead('Saved memory'),
          caption(
            'Linked to you and your main conversation. Ask in chat to add, correct, or forget something.',
          ),
          const SizedBox(height: 12),
          if (model.records('memory').isEmpty)
            const Panel(
              child: Text(
                'Your lasting preferences and milestones will appear here.',
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
          for (final session in model.sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session['kind'] == 'main'
                          ? 'Main conversation'
                          : '${session['kind']} helper',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
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
            'Context can be compressed as a conversation grows. Saved memory stays in MongoDB and is supplied to the main conversation again. Context usage is separate from your account usage limit.',
          ),
          const SizedBox(height: 28),
        ],
      ),
    ),
  );
}
