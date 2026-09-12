import 'package:flutter/material.dart';
import 'cortex.dart';
import 'main.dart';

void notice(BuildContext context, Object message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message.toString()),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> action(BuildContext context, Future<void> Function() work) async {
  try {
    await work();
  } catch (e) {
    if (context.mounted) {
      notice(context, e);
    }
  }
}

Widget titleText(String text) => Text(
  text,
  style: const TextStyle(
    fontSize: 25,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.7,
    color: ink,
  ),
);
Widget caption(String text) =>
    Text(text, style: const TextStyle(fontSize: 13, color: muted, height: 1.5));
Widget label(String text) => Text(
  text.toUpperCase(),
  style: const TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
    color: muted,
  ),
);
Widget sectionHead(String text, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(top: 26, bottom: 12),
  child: Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      ?trailing,
    ],
  ),
);

class Panel extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(18),
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
}

class Photo extends StatelessWidget {
  final CortexModel model;
  final String id;
  final double size;
  const Photo({
    super.key,
    required this.model,
    required this.id,
    this.size = 100,
  });
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: model.image(id),
    builder: (context, snapshot) {
      final data = snapshot.data;
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: data == null
            ? Container(
                width: size,
                height: size,
                color: soft,
                child: Icon(
                  snapshot.hasError
                      ? Icons.broken_image_outlined
                      : Icons.image_outlined,
                  color: muted,
                ),
              )
            : InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: InteractiveViewer(child: Image.memory(data)),
                  ),
                ),
                child: Image.memory(
                  data,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              ),
      );
    },
  );
}

String contextLabel(dynamic usage) {
  if (usage is! Map ||
      usage['window'] == null ||
      usage['used'] == null ||
      (usage['window'] as num) <= 0) {
    return 'Context · waiting for first reply';
  }
  final remaining =
      (100 * (1 - (usage['used'] as num) / (usage['window'] as num)))
          .clamp(0, 100)
          .round();
  return '~$remaining% context left';
}

/// A consistent iPhone accessory for chat, sheets, and numeric input fields.
class KeyboardDismissBar extends StatelessWidget {
  final Widget child;
  const KeyboardDismissBar({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    const height = 40.0;
    return Stack(
      children: [
        MediaQuery(
          data: keyboard > 0
              ? media.copyWith(
                  viewInsets: media.viewInsets.copyWith(
                    bottom: keyboard + height,
                  ),
                )
              : media,
          child: child,
        ),
        if (keyboard > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            height: height,
            child: Material(
              color: const Color(0xFFF0F2EF),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  icon: const Icon(Icons.keyboard_hide_outlined, size: 20),
                  label: const Text('Hide keyboard'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
