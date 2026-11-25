import '../google/google_links.dart';

Uri calendarLink(String path, String? email, [Map<String, String>? query]) =>
    googleAuthUser(
      Uri.https('calendar.google.com', '/calendar/$path', query),
      email,
    )!;

Uri? calendarEventLink(Uri? event, [String? email]) {
  if (event == null ||
      (event.scheme != 'https' && event.scheme != 'http') ||
      !const {'calendar.google.com', 'www.google.com'}.contains(event.host) ||
      !event.path.startsWith('/calendar/') ||
      event.userInfo.isNotEmpty ||
      (event.hasPort && event.port != 443)) {
    return null;
  }
  return googleAuthUser(
    event.replace(scheme: 'https', host: 'calendar.google.com'),
    email,
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
