import '../../core/phone_alarms.dart';
import '../../remote_ui/remote_layout.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';
import '../../app/avatars.dart';
import '../../app/usage_header.dart';

import '../settings/codex_login.dart';

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

class ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final draft = TextEditingController(), scroll = ScrollController();
  final focus = FocusNode();
  final images = <Attachment>[];
  bool sending = false;
  String? error;
  int previousCount = 0;
  double? _keyboardInset;
  bool _chatKeyboardActive = false;
  bool _followingKeyboard = false;
  bool _keyboardScrollQueued = false;
  Timer? _keyboardSettled;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.model.addListener(changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Scaffold removes the consumed keyboard inset from its body's MediaQuery.
    // Read the actual Flutter view so both opening and dismissal are detected.
    _keyboardInset ??= View.of(context).viewInsets.bottom;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final inset = View.of(context).viewInsets.bottom;
    if (inset == _keyboardInset) return;
    _keyboardInset = inset;
    if (!focus.hasFocus && !_chatKeyboardActive) return;
    _chatKeyboardActive = inset > 0;
    _followingKeyboard = true;
    _queueKeyboardScroll();
    _keyboardSettled?.cancel();
    _keyboardSettled = Timer(const Duration(milliseconds: 350), () {
      _queueKeyboardScroll();
      // Keep following layout changes through the last keyboard animation frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _followingKeyboard = false;
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  void _queueKeyboardScroll() {
    if (!_followingKeyboard || _keyboardScrollQueued) return;
    _keyboardScrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardScrollQueued = false;
      if (!mounted || !_followingKeyboard || !scroll.hasClients) return;
      final position = scroll.position;
      if ((position.pixels - position.maxScrollExtent).abs() > 0.5) {
        scroll.jumpTo(position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardSettled?.cancel();
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
    return RemoteLayout(
      page: 'chat',
      slots: {
        'divider': const Divider(height: 1),
        'login': Column(
          children: [
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
          ],
        ),
        'conversation': Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              // Long messages and image rows can change the extent after resize.
              _queueKeyboardScroll();
              return false;
            },
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              children: [
                if (m.messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 50),
                    child: Column(
                      children: [
                        const CortexAvatar(size: 58),
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
                  RemoteLayout(
                    page: message['role'] == 'user'
                        ? 'userMessage'
                        : 'assistantMessage',
                    slots: {
                      'content': messageContent(
                        m,
                        message['role'] == 'user',
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
                                      Photo(
                                        model: m,
                                        id: id as String,
                                        size: 105,
                                      ),
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
                    },
                  ),
                if ((m.chat['text'] as String? ?? '').isNotEmpty)
                  Panel(
                    child: messageContent(
                      m,
                      false,
                      child: MarkdownBody(data: m.chat['text'] as String),
                    ),
                  ),
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
                        Expanded(
                          child: caption(
                            (m.chat['helper'] as String? ?? '').isNotEmpty
                                ? m.chat['helper'] as String
                                : '$status…',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        'error': Column(
          children: [
            for (final alarm
                in m.alarms.items
                    .where(
                      (a) =>
                          ['pending', 'needs_permission'].contains(a['status']),
                    )
                    .take(2))
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Row(
                  children: [
                    const Icon(Icons.alarm_rounded, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${alarmTime(alarm)} · ${alarmStatusLabel(alarm['status'] as String?)}',
                        style: const TextStyle(fontSize: 12),
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
          ],
        ),
        'composer': Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(22),
          ),
          child: RemoteLayout(
            page: 'composer',
            slots: {
              'images': Column(
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
                ],
              ),
              'input': TextField(
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
              'actions': Row(
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
            },
          ),
        ),
      },
    );
  }
}
