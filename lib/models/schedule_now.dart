import 'schedule.dart';

/// An event with real start and end times, worked out from the schedule's day dates
/// ("October 30, 2026") and time text ("10:30 AM - 12:00 PM").
class TimedEvent {
  TimedEvent(this.event, this.start, this.end);
  final Schedule event;
  final DateTime start;
  final DateTime end;
}

const _months = {
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
  'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11,
  'december': 12,
};

/// "November 7, 2025" -> a local date, or null if it cannot be read.
DateTime? parseDisplayDate(String text) {
  final m = RegExp(r'([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})').firstMatch(text);
  final month = m == null ? null : _months[m.group(1)!.toLowerCase()];
  if (m == null || month == null) return null;
  return DateTime(int.parse(m.group(3)!), month, int.parse(m.group(2)!));
}

/// "9:00 - 10:30 AM", "10:30 AM - 12:00 PM" -> start and end as (hour, minute) on a
/// 24 hour clock, or null if it cannot be read. A start with no AM/PM takes the end's
/// ("9:00 - 10:30 AM"), unless that would put it after the end ("11:00 - 1:00 PM").
({int sh, int sm, int eh, int em})? parseTimeRange(String text) {
  final m = RegExp(
    r'^\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?\s*[-–—]\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\s*$',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;

  int to24(int h, bool pm) => (h % 12) + (pm ? 12 : 0);
  final eh12 = int.parse(m.group(4)!);
  final em = int.parse(m.group(5) ?? '0');
  final endPm = m.group(6)!.toUpperCase() == 'PM';
  final endMinutes = to24(eh12, endPm) * 60 + em;

  final sh12 = int.parse(m.group(1)!);
  final sm = int.parse(m.group(2) ?? '0');
  var startPm = m.group(3) == null ? endPm : m.group(3)!.toUpperCase() == 'PM';
  if (m.group(3) == null && to24(sh12, startPm) * 60 + sm > endMinutes) {
    startPm = !startPm;
  }
  if (sh12 > 12 || eh12 > 12 || sm > 59 || em > 59) return null;
  return (sh: to24(sh12, startPm), sm: sm, eh: to24(eh12, endPm), em: em);
}

/// Every event that can be given real times, earliest first. Events on a day with an
/// unreadable date, or with unreadable times, are left out rather than guessed.
List<TimedEvent> timeEvents(List<ConferenceDay> days, List<Schedule> events) {
  final dates = {
    for (final d in days) d.dayKey: parseDisplayDate(d.displayDate),
  };
  final out = <TimedEvent>[];
  for (final e in events) {
    final date = dates[e.day];
    final t = parseTimeRange(e.time);
    if (date == null || t == null) continue;
    final start = DateTime(date.year, date.month, date.day, t.sh, t.sm);
    var end = DateTime(date.year, date.month, date.day, t.eh, t.em);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    out.add(TimedEvent(e, start, end));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

enum NowKind {
  /// Before the first day: [NowStatus.daysToGo] days to go.
  beforeEvent,

  /// Something is on right now ([NowStatus.events], more than one if they overlap).
  live,

  /// Nothing right now, but [NowStatus.next] starts later today.
  upNext,

  /// Today's programme is finished; [NowStatus.next] is on a later day.
  wrappedForToday,

  /// The whole event is over.
  over,
}

class NowStatus {
  const NowStatus(this.kind,
      {this.events = const [], this.next, this.daysToGo = 0});
  final NowKind kind;
  final List<TimedEvent> events;
  final TimedEvent? next;
  final int daysToGo;
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// What is happening at [now]. Null when there is nothing to base it on.
NowStatus? computeNow(List<TimedEvent> all, DateTime now) {
  if (all.isEmpty) return null;

  final live = all.where((e) => !now.isBefore(e.start) && now.isBefore(e.end)).toList();
  if (live.isNotEmpty) return NowStatus(NowKind.live, events: live);

  final upcoming = all.where((e) => e.start.isAfter(now));
  if (upcoming.isEmpty) return const NowStatus(NowKind.over);
  final next = upcoming.first;

  if (_day(next.start) == _day(now)) {
    return NowStatus(NowKind.upNext, next: next);
  }
  if (now.isBefore(all.first.start)) {
    return NowStatus(
      NowKind.beforeEvent,
      next: next,
      daysToGo: _day(next.start).difference(_day(now)).inDays,
    );
  }
  return NowStatus(NowKind.wrappedForToday, next: next);
}
