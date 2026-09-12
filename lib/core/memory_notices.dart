import 'package:shared_preferences/shared_preferences.dart';

class MemoryNotices {
  static const key = 'cortex.memory.notice.ids.v1';
  final List<Map<String, dynamic>> pending = [];
  Set<String>? _seen;
  Future<void> receive(List<dynamic> records) async {
    if (!records.whereType<Map>().any(
      (r) => (r['memoryEvents'] as List? ?? []).isNotEmpty,
    )) {
      return;
    }
    _seen ??=
        (await SharedPreferences.getInstance()).getStringList(key)?.toSet() ??
        {};
    final queued = pending.map((n) => n['id']).toSet();
    for (final record in records.whereType<Map>()) {
      for (final event
          in (record['memoryEvents'] as List? ?? []).whereType<Map>()) {
        final id = event['id'];
        if (id is! String || _seen!.contains(id) || !queued.add(id)) continue;
        pending.add(Map<String, dynamic>.from(event));
      }
    }
    pending.sort(
      (a, b) => (a['created'] as String? ?? '').compareTo(
        b['created'] as String? ?? '',
      ),
    );
  }

  Future<void> displayed(Map<String, dynamic> notice) async {
    pending.removeWhere((n) => n['id'] == notice['id']);
    (_seen ??= {}).add(notice['id'] as String);
    await (await SharedPreferences.getInstance()).setStringList(
      key,
      _seen!.toList(),
    );
  }
}
