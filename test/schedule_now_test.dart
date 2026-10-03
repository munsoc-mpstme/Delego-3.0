import 'package:delego/models/schedule.dart';
import 'package:delego/models/schedule_now.dart';
import 'package:delego/widgets/now_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Schedule ev(String id, String day, String name, String time, [String where = 'Hall']) =>
    Schedule(
      id: id, day: day, name: name, location: where, time: time,
      description: '', imageUrl: '',
    );

final days = [
  ConferenceDay(dayKey: 'Day 1', displayDate: 'October 30, 2026'),
  ConferenceDay(dayKey: 'Day 2', displayDate: 'October 31, 2026'),
  ConferenceDay(dayKey: 'Day 3', displayDate: 'November 1, 2026'),
];

final events = [
  ev('1', 'Day 1', 'Registration Desk', '9:00 - 10:30 AM', 'Main Gate'),
  ev('2', 'Day 1', 'Opening Ceremony', '10:30 AM - 12:00 PM', 'Big Auditorium'),
  ev('3', 'Day 1', 'Lunch', '12:00 PM - 2:00 PM', 'Canteen'),
  ev('4', 'Day 1', 'Formal Socials', '5:30 PM - 7:30 PM'),
  ev('5', 'Day 2', 'Breakfast', '8:00 - 9:00 AM', 'Canteen'),
  ev('6', 'Day 3', 'Closing Ceremony', '5:00 PM - 7:00 PM'),
];

final timed = timeEvents(days, events);
NowStatus at(int month, int day, int h, [int m = 0]) =>
    computeNow(timed, DateTime(2026, month, day, h, m))!;

void main() {
  group('reading the schedule text', () {
    test('dates', () {
      expect(parseDisplayDate('November 7, 2025'), DateTime(2025, 11, 7));
      expect(parseDisplayDate('October 30, 2026'), DateTime(2026, 10, 30));
      expect(parseDisplayDate('whenever'), isNull);
    });

    test('time ranges, including a start with no AM/PM', () {
      expect(parseTimeRange('9:00 - 10:30 AM'), (sh: 9, sm: 0, eh: 10, em: 30));
      expect(parseTimeRange('10:30 AM - 12:00 PM'), (sh: 10, sm: 30, eh: 12, em: 0));
      expect(parseTimeRange('12:00 PM - 2:00 PM'), (sh: 12, sm: 0, eh: 14, em: 0));
      expect(parseTimeRange('8:00 - 9:00 AM'), (sh: 8, sm: 0, eh: 9, em: 0));
      // 11 -> 1 PM can only mean 11 AM
      expect(parseTimeRange('11:00 - 1:00 PM'), (sh: 11, sm: 0, eh: 13, em: 0));
      expect(parseTimeRange('5:30 PM - 7:30 PM'), (sh: 17, sm: 30, eh: 19, em: 30));
      expect(parseTimeRange('all day'), isNull);
      expect(parseTimeRange('25:00 - 26:00 PM'), isNull);
    });

    test('events that cannot be read are skipped, not guessed', () {
      final out = timeEvents(days, [
        ev('a', 'Day 1', 'Fine', '9:00 - 10:00 AM'),
        ev('b', 'Day 1', 'No time', 'TBD'),
        ev('c', 'Day 9', 'No such day', '9:00 - 10:00 AM'),
      ]);
      expect(out.map((e) => e.event.name), ['Fine']);
    });
  });

  group('what is on now', () {
    test('long before the event', () {
      final s = computeNow(timed, DateTime(2026, 10, 1, 12))!;
      expect(s.kind, NowKind.beforeEvent);
      expect(s.daysToGo, 29);
    });

    test('the day before', () {
      final s = at(10, 29, 22);
      expect(s.kind, NowKind.beforeEvent);
      expect(s.daysToGo, 1);
    });

    test('event day, before the first session: up next', () {
      final s = at(10, 30, 8);
      expect(s.kind, NowKind.upNext);
      expect(s.next!.event.name, 'Registration Desk');
    });

    test('during a session: live', () {
      final s = at(10, 30, 10);
      expect(s.kind, NowKind.live);
      expect(s.events.single.event.name, 'Registration Desk');
    });

    test('at the changeover the new session is live and the old one is over', () {
      expect(at(10, 30, 10, 30).events.single.event.name, 'Opening Ceremony');
      expect(at(10, 30, 10, 29).events.single.event.name, 'Registration Desk');
    });

    test('a gap between sessions on the same day: up next', () {
      final s = at(10, 30, 15);
      expect(s.kind, NowKind.upNext);
      expect(s.next!.event.name, 'Formal Socials');
    });

    test('after the last session of a day: wrapped, next day is next', () {
      final s = at(10, 30, 22);
      expect(s.kind, NowKind.wrappedForToday);
      expect(s.next!.event.name, 'Breakfast');
    });

    test('after the whole event', () {
      expect(at(11, 1, 21).kind, NowKind.over);
      expect(computeNow(timed, DateTime(2027, 1, 1))!.kind, NowKind.over);
    });

    test('overlapping sessions are all reported', () {
      final both = timeEvents(days, [
        ev('a', 'Day 1', 'Committee A', '9:00 AM - 12:00 PM'),
        ev('b', 'Day 1', 'Committee B', '10:00 AM - 11:00 AM'),
      ]);
      final s = computeNow(both, DateTime(2026, 10, 30, 10, 30))!;
      expect(s.events.length, 2);
    });

    test('nothing to go on gives no status', () {
      expect(computeNow([], DateTime.now()), isNull);
    });
  });

  group('wording', () {
    test('live', () {
      final t = describeNow(at(10, 30, 11), DateTime(2026, 10, 30, 11));
      expect(t.label, 'HAPPENING NOW');
      expect(t.title, 'Opening Ceremony');
      expect(t.subtitle, 'Big Auditorium · 10:30 AM – 12:00 PM');
      expect(t.live, isTrue);
    });

    test('up next within the hour counts down', () {
      final now = DateTime(2026, 10, 30, 8, 35);
      final t = describeNow(computeNow(timed, now)!, now);
      expect(t.title, 'Registration Desk');
      expect(t.subtitle, 'Main Gate · starts in 25 min');
    });

    test('up next later gives the clock time', () {
      final now = DateTime(2026, 10, 30, 15);
      final t = describeNow(computeNow(timed, now)!, now);
      expect(t.subtitle, contains('at 5:30 PM'));
    });

    test('before the event', () {
      final now = DateTime(2026, 10, 29, 12);
      expect(describeNow(computeNow(timed, now)!, now).title, 'Mumbai MUN starts tomorrow');
      final earlier = DateTime(2026, 10, 25, 12);
      expect(describeNow(computeNow(timed, earlier)!, earlier).title, 'Mumbai MUN starts in 5 days');
    });

    test('wrapped for today points at tomorrow', () {
      final now = DateTime(2026, 10, 30, 22);
      final t = describeNow(computeNow(timed, now)!, now);
      expect(t.title, 'See you tomorrow');
      expect(t.subtitle, 'Tomorrow: Breakfast · 8:00 AM');
    });

    test('clock format', () {
      expect(formatClock(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(formatClock(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
      expect(formatClock(DateTime(2026, 1, 1, 17, 30)), '5:30 PM');
    });
  });

  testWidgets('the strip shows the words and reacts to taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NowStripView(
          text: describeNow(at(10, 30, 11), DateTime(2026, 10, 30, 11)),
          onTap: () => taps++,
        ),
      ),
    ));
    expect(find.text('HAPPENING NOW'), findsOneWidget);
    expect(find.text('OPENING CEREMONY'), findsOneWidget);
    await tester.tap(find.byType(NowStripView));
    expect(taps, 1);
  });
}
