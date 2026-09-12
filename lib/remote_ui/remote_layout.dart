import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart';
import '../main.dart';
import 'layout_store.dart';

/// Owns only presentation. Controllers, requests, permissions and navigation
/// belong to the native feature that provides these slots.
class RemoteLayout extends StatefulWidget {
  final String page;
  final Map<String, Widget> slots;
  const RemoteLayout({super.key, required this.page, required this.slots});
  @override
  State<RemoteLayout> createState() => _RemoteLayoutState();
}

class _RemoteLayoutState extends State<RemoteLayout> {
  final runtime = Runtime(), data = DynamicContent();
  final keys = <String, GlobalKey>{};
  static const local = LibraryName(['cortex']),
      remote = LibraryName(['layout']);
  Object? library;
  @override
  void initState() {
    super.initState();
    runtime.update(local, _widgets());
  }

  @override
  void dispose() {
    runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: layouts,
    builder: (context, _) {
      final next = layouts.current.libraries[widget.page]!;
      if (!identical(library, next)) {
        library = next;
        runtime.update(remote, next);
      }
      return _Slots(
        slots: {
          for (final e in widget.slots.entries)
            e.key: KeyedSubtree(
              key: keys.putIfAbsent(e.key, () => GlobalKey()),
              child: e.value,
            ),
        },
        child: RemoteWidget(
          runtime: runtime,
          data: data,
          widget: const FullyQualifiedWidgetName(remote, 'root'),
        ),
      );
    },
  );
}

class _Slots extends InheritedWidget {
  final Map<String, Widget> slots;
  const _Slots({required this.slots, required super.child});
  @override
  bool updateShouldNotify(_Slots oldWidget) => true;
}

double _n(DataSource s, String key, double fallback) =>
    s.v<double>([key]) ?? s.v<int>([key])?.toDouble() ?? fallback;
Color _tone(DataSource s) => switch (s.v<String>(['tone'])) {
  'soft' => soft,
  'paper' => paper,
  _ => Colors.white,
};
Widget _column(DataSource s) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: s.childList(['children']),
);

LocalWidgetLibrary _widgets() => LocalWidgetLibrary({
  'Slot': (context, s) => context
      .dependOnInheritedWidgetOfExactType<_Slots>()!
      .slots[s.v<String>(['name'])]!,
  'Column': (context, s) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: s.childList(['children']),
  ),
  'List': (context, s) => ListView(
    padding: EdgeInsets.all(_n(s, 'padding', 22)),
    physics: const AlwaysScrollableScrollPhysics(),
    children: s.childList(['children']),
  ),
  'Grid': (context, s) => GridView.count(
    crossAxisCount: s.v<int>(['columns']) ?? 2,
    mainAxisSpacing: _n(s, 'gap', 14),
    crossAxisSpacing: _n(s, 'gap', 14),
    childAspectRatio: _n(s, 'ratio', .69),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: s.childList(['children']),
  ),
  'Text': (context, s) => Text(
    s.v<String>(['text']) ?? '',
    style: TextStyle(
      fontSize: _n(s, 'size', 14),
      height: 1.4,
      color: _n(s, 'size', 14) > 18 ? ink : muted,
      fontWeight: _n(s, 'size', 14) > 18 ? FontWeight.w500 : FontWeight.normal,
    ),
  ),
  'Gap': (context, s) => SizedBox(height: _n(s, 'height', 12)),
  'Surface': (context, s) => Container(
    padding: EdgeInsets.all(_n(s, 'padding', 16)),
    decoration: BoxDecoration(
      color: _tone(s),
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(_n(s, 'radius', 20)),
    ),
    child: _column(s),
  ),
  'Bubble': (context, s) => Align(
    alignment: s.v<String>(['align']) == 'right'
        ? Alignment.centerRight
        : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 18),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * _n(s, 'width', .85),
      ),
      padding: EdgeInsets.all(_n(s, 'padding', 16)),
      decoration: BoxDecoration(
        color: _tone(s),
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(_n(s, 'radius', 20)),
      ),
      child: _column(s),
    ),
  ),
});
