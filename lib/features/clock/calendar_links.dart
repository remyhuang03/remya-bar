import 'dart:io';

Uri calendarLink(String path, String? email, [Map<String, String>? query]) =>
    Uri.https('calendar.google.com', '/calendar/$path', {
      ...?query,
      'authuser': ?email,
    });

Uri? calendarEventLink(Uri? event, [String? email]) {
  if (event == null ||
      (event.scheme != 'https' && event.scheme != 'http') ||
      !const {'calendar.google.com', 'www.google.com'}.contains(event.host) ||
      !event.path.startsWith('/calendar/') ||
      event.userInfo.isNotEmpty ||
      (event.hasPort && event.port != 443)) {
    return null;
  }
  return event.replace(
    scheme: 'https',
    host: 'calendar.google.com',
    queryParameters: {...event.queryParameters, 'authuser': ?email},
  );
}

Uri calendarNewEvent(
  DateTime day,
  DateTime now,
  String? timezone,
  String? email,
) {
  final sameDay =
      (day.year, day.month, day.day) == (now.year, now.month, now.day);
  final start = DateTime(
    day.year,
    day.month,
    day.day,
    sameDay ? now.hour + 1 : 9,
  );
  String format(DateTime value) {
    final timestamp = value.toUtc().toIso8601String().split('.').first;
    return '${timestamp.replaceAll(RegExp('[-:]'), '')}Z';
  }

  return calendarLink('render', email, {
    'action': 'TEMPLATE',
    'dates': '${format(start)}/${format(start.add(const Duration(hours: 1)))}',
    if (timezone != null && timezone.isNotEmpty) 'ctz': timezone,
  });
}

Future<void> openCalendarLink(Uri? uri) async {
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw StateError('Calendar link unavailable.');
  }
  final result = await Process.run('xdg-open', [uri.toString()]);
  if (result.exitCode != 0) throw StateError('Could not open this link.');
}
