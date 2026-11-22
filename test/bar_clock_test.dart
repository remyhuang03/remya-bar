import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/clock/bar_clock.dart';
import 'package:remya_bar/features/clock/calendar_dates.dart';
import 'package:remya_bar/features/clock/calendar_links.dart';

void main() {
  test('week numbers follow the configured week across New Year', () {
    final jan1 = DateTime.utc(2021);
    final iso = calendarWeekStart(jan1, DateTime.monday);
    final sunday = calendarWeekStart(jan1, DateTime.sunday);
    expect(iso, DateTime.utc(2020, 12, 28));
    expect(calendarWeekNumber(iso, DateTime.thursday), 53);
    expect(sunday, DateTime.utc(2020, 12, 27));
    expect(calendarWeekNumber(sunday, DateTime.saturday), 1);
    expect(
      calendarMonthFrom(DateTime.utc(2024, 1, 31), 1),
      DateTime.utc(2024, 2, 29),
    );
  });

  test('new-event handoff keeps day, duration and account', () {
    final link = calendarNewEvent(
      DateTime.utc(2024, 6, 12),
      DateTime(2024, 6, 11, 23, 13),
      'Asia/Taipei',
      'test@example.com',
    );
    expect(link.host, 'calendar.google.com');
    expect(link.queryParameters['authuser'], 'test@example.com');
    expect(link.queryParameters['ctz'], 'Asia/Taipei');
    final [start, end] = link.queryParameters['dates']!
        .split('/')
        .map(DateTime.parse)
        .toList();
    expect(start.toLocal(), DateTime(2024, 6, 12, 9));
    expect(end.difference(start), const Duration(hours: 1));
  });

  test('Google legacy event links open with the connected account', () {
    final link = calendarEventLink(
      Uri.parse('https://www.google.com/calendar/event?eid=example&hl=en'),
      'account@example.com',
    );
    expect(
      link.toString(),
      'https://calendar.google.com/calendar/event?eid=example&hl=en&authuser=account%40example.com',
    );
    expect(
      calendarEventLink(Uri.parse('https://www.google.com/url?q=example')),
      isNull,
    );
    expect(
      calendarEventLink(
        Uri.parse('https://www.google.com.other.test/calendar/event'),
      ),
      isNull,
    );
  });

  testWidgets('shared clock publishes at each consumer cadence', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 18, 12, 34, 58, 500);
    final source = BarClockSource(now: () => now);
    final minutes = <DateTime>[];
    final seconds = <DateTime>[];
    final onMinute = minutes.add;
    final onSecond = seconds.add;

    Future<void> advance(int millis) async {
      final duration = Duration(milliseconds: millis);
      now = now.add(duration);
      await tester.pump(duration);
    }

    expect(source.attach(onMinute, seconds: false), now);
    source.attach(onSecond, seconds: true);
    await advance(500);
    expect(seconds, [now]);
    expect(minutes, isEmpty);
    await advance(1000);
    expect(seconds.length, 2);
    expect(minutes, [now]);

    source.detach(onSecond);
    await advance(59000);
    expect(seconds.length, 2);
    expect(minutes.length, 1);
    await advance(1000);
    expect(minutes.length, 2);
    source.detach(onMinute);
    await advance(60000);
    expect(minutes.length, 2);
  });
}
