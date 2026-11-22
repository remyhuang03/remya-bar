import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/data/latest.dart' as zone_data;
import 'package:timezone/timezone.dart' as zone;

import 'calendar_links.dart';

enum CalendarResponse { accepted, tentative, awaitingReply, declined }

/// A Google occurrence. All-day dates use UTC as a civil-date container.
class CalendarEvent {
  CalendarEvent._({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.location,
    required this.start,
    required this.end,
    required this.allDay,
    required this.rawColor,
    required this.htmlLink,
    required this.meetingLink,
    required this.response,
  }) : fill = calendarReadableFill(rawColor);

  final String id;
  final String calendarId;
  final String title;
  final String location;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final Color rawColor;
  final Color fill;
  final Uri? htmlLink;
  final Uri? meetingLink;
  final CalendarResponse response;

  bool get declined => response == .declined;
  Duration get duration => end.difference(start);

  bool occursOn(DateTime civilDay) {
    if (allDay) return !start.isAfter(civilDay) && end.isAfter(civilDay);
    final from = DateTime(civilDay.year, civilDay.month, civilDay.day);
    final to = DateTime(civilDay.year, civilDay.month, civilDay.day + 1);
    return start.isBefore(to) &&
        (end.isAfter(from) || start == end && start == from);
  }

  static CalendarEvent? parse(Object? json) {
    if (json is! Map || json['status'] == 'cancelled') return null;
    final id = _nonempty(json['id']);
    final calendarId = _nonempty(json['calendarId']);
    final startSpec = json['start'];
    final endSpec = json['end'];
    if (id == null ||
        calendarId == null ||
        startSpec is! Map ||
        endSpec is! Map) {
      return null;
    }
    final allDay = startSpec.containsKey('date');
    final start = allDay ? _date(startSpec['date']) : _dateTime(startSpec);
    final end = allDay ? _date(endSpec['date']) : _dateTime(endSpec);
    if (start == null ||
        end == null ||
        end.isBefore(start) ||
        allDay && end == start) {
      return null;
    }
    final color = _nonempty(json['backgroundColor']);
    final rgb = color != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)
        ? int.parse(color.substring(1), radix: 16)
        : 0x7986CB;
    final description = _nonempty(json['description']) ?? '';
    final location = _nonempty(json['location']) ?? '';
    final htmlLink = _webLink(json['htmlLink']);
    return CalendarEvent._(
      id: id,
      calendarId: calendarId,
      title: _nonempty(json['summary']) ?? 'Untitled event',
      location: location,
      start: start,
      end: end,
      allDay: allDay,
      rawColor: Color(0xFF000000 | rgb),
      htmlLink: calendarEventLink(htmlLink),
      meetingLink: _meeting(
        json['conferenceData'],
        json['hangoutLink'],
        location,
        description,
      ),
      response: _response(json['attendees'], json['status']),
    );
  }
}

String? _nonempty(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? _date(Object? value) {
  if (value is! String || !_isoDate.hasMatch(value)) return null;
  final date = DateTime.tryParse('${value}T00:00:00Z');
  return date?.toIso8601String().startsWith('${value}T') == true ? date : null;
}

final _timestamp = RegExp(
  r'^\d{4}-\d{2}-\d{2}[Tt](?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d'
  r'(?:\.\d+)?([Zz]|[+-](?:[01]\d|2[0-3]):[0-5]\d)?$',
);
final _initializeZones = (() {
  zone_data.initializeTimeZones();
  return true;
})();

DateTime? _dateTime(Map value) {
  final text = _nonempty(value['dateTime']);
  if (text == null) return null;
  final match = _timestamp.firstMatch(text);
  if (match == null || _date(text.substring(0, 10)) == null) return null;
  if (match[1] != null) return DateTime.tryParse(text)?.toLocal();
  final timezone = _nonempty(value['timeZone']);
  final fields = DateTime.tryParse('${text}Z');
  if (timezone == null || fields == null || !_initializeZones) return null;
  try {
    return zone.TZDateTime(
      zone.getLocation(timezone),
      fields.year,
      fields.month,
      fields.day,
      fields.hour,
      fields.minute,
      fields.second,
      fields.millisecond,
      fields.microsecond,
    ).native.toLocal();
  } on zone.LocationNotFoundException {
    return null;
  }
}

CalendarResponse _response(Object? attendees, Object? status) {
  if (attendees is List) {
    for (final attendee in attendees) {
      if (attendee is! Map || attendee['self'] != true) continue;
      switch (attendee['responseStatus']) {
        case 'declined':
          return .declined;
        case 'needsAction':
          return .awaitingReply;
        case 'tentative':
          return .tentative;
      }
      break;
    }
  }
  return status == 'tentative' ? .tentative : .accepted;
}

Color calendarReadableFill(Color raw) {
  const maxLuminance = 1.05 / 4.5 - .05;
  if (raw.computeLuminance() <= maxLuminance) return raw;
  final source = Hct.fromInt(raw.toARGB32());
  var tone = 50.0;
  var fill = Color(Hct.from(source.hue, source.chroma, tone).toInt());
  while (fill.computeLuminance() > maxLuminance) {
    tone -= .1;
    fill = Color(Hct.from(source.hue, source.chroma, tone).toInt());
  }
  return fill;
}

Uri? _webLink(Object? value) {
  final text = _nonempty(value);
  final uri = text == null ? null : Uri.tryParse(text);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

final _urls = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
final _urlEnd = RegExp(r'[.,;!?)\]]+$');

String? _meetingName(String host) {
  bool matches(String domain) => host == domain || host.endsWith('.$domain');
  if (host == 'meet.google.com') return 'Google Meet';
  if (matches('zoom.us') || matches('zoom.com')) return 'Zoom';
  if (matches('meeting.tencent.com') || matches('voovmeeting.com')) {
    return 'Tencent Meeting';
  }
  if (matches('teams.microsoft.com') || matches('teams.live.com')) {
    return 'Teams';
  }
  return null;
}

Uri? _meeting(
  Object? conference,
  Object? hangout,
  String location,
  String note,
) {
  final entries = conference is Map ? conference['entryPoints'] : null;
  if (entries is List) {
    for (final entry in entries) {
      if (entry is Map && entry['entryPointType'] == 'video') {
        if (_webLink(entry['uri']) case final uri?) return uri;
      }
    }
  }
  if (_webLink(hangout) case final uri?) return uri;
  for (final match in _urls.allMatches('$location\n$note')) {
    final url = match[0]!.replaceFirst(_urlEnd, '');
    final uri = _webLink(url);
    if (uri != null && _meetingName(uri.host) != null) return uri;
  }
  return null;
}

/// Keep room names and compact fully qualified web locations for the agenda.
String calendarLocationLabel(String location) =>
    location.replaceAllMapped(_urls, (match) {
      final text = match[0]!;
      final end = _urlEnd.firstMatch(text)?.start ?? text.length;
      final uri = _webLink(text.substring(0, end));
      if (uri == null) return text;
      return '${_meetingName(uri.host) ?? uri.host}${text.substring(end)}';
    });
