import 'package:flutter/material.dart';
import '../core/cortex.dart';
import '../main.dart';
import 'usage_header.dart';
import 'avatars.dart';
import '../features/space/space_screen.dart';

import '../features/chat/chat_screen.dart';
import '../features/settings/settings_screen.dart';

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
          CortexAvatar(size: 34),
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
