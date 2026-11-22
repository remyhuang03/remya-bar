import 'dart:io';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const calendarWeekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

DateTime calendarDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

DateTime calendarDaysFrom(DateTime date, int days) =>
    date.add(Duration(days: days));

DateTime calendarWeekStart(DateTime day, int firstWeekday) =>
    calendarDaysFrom(day, -((day.weekday - firstWeekday) % 7));

DateTime calendarMonthFrom(DateTime day, int months) {
  final target = DateTime.utc(day.year, day.month + months);
  final last = DateTime.utc(target.year, target.month + 1, 0).day;
  return DateTime.utc(target.year, target.month, day.day.clamp(1, last));
}

int calendarWeekNumber(DateTime start, int cutoffWeekday) {
  final cutoff = calendarDaysFrom(start, (cutoffWeekday - start.weekday) % 7);
  return (cutoff.difference(DateTime.utc(cutoff.year)).inDays ~/ 7) + 1;
}

final _localeReady = initializeDateFormatting();

({int first, int cutoff}) calendarWeekRule(String choice, String fallback) {
  _localeReady.ignore();
  final env = Platform.environment;
  final configured = [env['LC_ALL'], env['LC_TIME'], env['LANG']]
      .whereType<String>()
      .firstWhere((value) => value.isNotEmpty, orElse: () => fallback);
  final locale = configured.split(RegExp(r'[.@]')).first;
  final symbols = DateFormat(
    null,
    Intl.verifiedLocale(
      locale,
      DateFormat.localeExists,
      onFailure: (_) => 'en_US',
    ),
  ).dateSymbols;
  final first = switch (choice) {
    'monday' => DateTime.monday,
    'sunday' => DateTime.sunday,
    _ => symbols.FIRSTDAYOFWEEK + 1,
  };
  final cutoff = first == DateTime.monday
      ? DateTime.thursday
      : first == symbols.FIRSTDAYOFWEEK + 1
      ? symbols.FIRSTWEEKCUTOFFDAY + 1
      : DateTime.saturday;
  return (first: first, cutoff: cutoff);
}

typedef CalendarWindow = ({DateTime start, DateTime end});

CalendarWindow calendarWindow(DateTime day, DateTime gridStart) {
  final end = calendarDaysFrom(DateTime.utc(day.year, day.month + 1), 60);
  return (start: gridStart.isBefore(day) ? gridStart : day, end: end);
}

String calendarBoundary(DateTime date) =>
    DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
