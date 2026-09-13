import 'package:flutter_test/flutter_test.dart';
import 'package:cortex/core/cortex.dart';
import 'package:cortex/features/time/daily_routines.dart';

void main() {
  final left = Entry('left', 'routine', {
    'title': 'Left',
    'weekdays': [7],
    'intervalWeeks': 2,
    'anchorDate': '2026-09-13',
    'period': 'weekly',
  });
  final right = Entry('right', 'routine', {
    'title': 'Right',
    'weekdays': [7],
    'intervalWeeks': 2,
    'anchorDate': '2026-09-20',
    'period': 'weekly',
  });
  test(
    'Alternating routines show the correct next leg across weeks and years',
    () {
      expect(
        nextRoutineDate(left, DateTime(2026, 9, 13, 23, 59)),
        DateTime.utc(2026, 9, 13),
      );
      expect(
        nextRoutineDate(right, DateTime(2026, 9, 13)),
        DateTime.utc(2026, 9, 20),
      );
      expect(
        nextRoutineDate(left, DateTime(2026, 9, 14)),
        DateTime.utc(2026, 9, 27),
      );
      expect(
        nextRoutineDate(right, DateTime(2026, 9, 21)),
        DateTime.utc(2026, 10, 4),
      );
      expect(
        nextRoutineDate(left, DateTime(2027, 1, 1)),
        DateTime.utc(2027, 1, 3),
      );
      expect(
        routineWhen(left, now: DateTime(2026, 9, 13)),
        'Every 2 weeks · Sun · Due today',
      );
      expect(
        routineWhen(right, now: DateTime(2026, 9, 13)),
        'Every 2 weeks · Sun · Next 20 Sep',
      );
      expect(
        routineWhen(left, now: DateTime(2026, 9, 20)),
        'Every 2 weeks · Sun · Next 27 Sep',
      );
    },
  );
  test('Monthly routine uses calendar months and start dates', () {
    final r = Entry('mop', 'routine', {
      'intervalMonths': 1,
      'anchorDate': '2026-01-31',
    });
    expect(nextRoutineDate(r, DateTime(2026, 2, 1)), DateTime.utc(2026, 2, 28));
    expect(nextRoutineDate(r, DateTime(2026, 3, 1)), DateTime.utc(2026, 3, 31));
    expect(routineWhen(r, now: DateTime(2026, 2, 1)), 'Monthly · Next 28 Feb');
  });
  test('Daily routines keep their existing label', () {
    expect(
      routineWhen(Entry('daily', 'routine', {'period': 'morning'})),
      'Daily · Morning',
    );
  });
}
