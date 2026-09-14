import 'package:shared_preferences/shared_preferences.dart';

// A saved job result is a snapshot, not a new completion event. Remember which
// results this phone has seen, including when the app was closed mid-compression.
class CompressionNotices {
  static const seenKey = 'cortex.compression.notices.seen.v1';
  static const pendingKey = 'cortex.compression.notices.pending.v1';
  Future<void> _work = Future.value();

  Future<bool> observe(Object? value, {bool initial = false}) {
    if (value is! Map || value['id'] is! String) return Future.value(false);
    final id = value['id'] as String;
    final status = value['status'];
    final terminal = status == 'completed' || status == 'failed';
    if (!terminal && !['saving', 'summarizing', 'starting'].contains(status)) {
      return Future.value(false);
    }
    final task = _work.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$id:$status';
      final seen = prefs.getStringList(seenKey)?.toSet() ?? <String>{};
      if (!terminal) {
        // A late progress snapshot must not re-arm an already seen result.
        if (!seen.contains('$id:completed') && !seen.contains('$id:failed')) {
          await prefs.setString(pendingKey, id);
        }
        return false;
      }
      if (seen.contains(key)) return false;
      final pending = prefs.getString(pendingKey) == id;
      // On upgrade/startup, silently acknowledge historical results. A job
      // observed running on this phone can still notify once after reopening.
      final show = !initial || pending;
      seen.add(key);
      await prefs.setStringList(seenKey, seen.toList());
      if (pending) await prefs.remove(pendingKey);
      return show;
    });
    // Serialize progress and completion writes from consecutive model updates.
    _work = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }
}
