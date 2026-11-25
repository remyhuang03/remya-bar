import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/clock/calendar_agenda.dart';
import 'package:remya_bar/features/clock/calendar_events.dart';

void main() {
  test('keeps all-day spans exclusive and respects an explicit IANA zone', () {
    final allDay = CalendarEvent.parse({
      ..._eventJson('Holiday'),
      'start': {'date': '2026-11-23'},
      'end': {'date': '2026-11-26'},
    })!;
    expect(allDay.duration.inDays, 3);
    expect(allDay.occursOn(DateTime.utc(2026, 11, 22)), isFalse);
    expect(allDay.occursOn(DateTime.utc(2026, 11, 23)), isTrue);
    expect(allDay.occursOn(DateTime.utc(2026, 11, 25)), isTrue);
    expect(allDay.occursOn(DateTime.utc(2026, 11, 26)), isFalse);

    final timed = CalendarEvent.parse({
      ..._eventJson('Late meeting'),
      'start': {'dateTime': '2026-11-24T01:00:00', 'timeZone': 'Asia/Taipei'},
      'end': {'dateTime': '2026-11-24T02:00:00+08:00'},
    })!;
    expect(timed.start.toUtc(), DateTime.utc(2026, 11, 23, 17));
    expect(timed.start, DateTime.utc(2026, 11, 23, 17).toLocal());
    expect(timed.duration, const Duration(hours: 1));
    expect(
      CalendarEvent.parse({
        ..._eventJson('Wrong month'),
        'start': {'date': '2026-11-31'},
        'end': {'date': '2026-12-02'},
      }),
      isNull,
    );
  });

  test(
    'uses self RSVP, resolves meeting precedence and keeps fills readable',
    () {
      final event = CalendarEvent.parse({
        ..._eventJson('Invited'),
        'backgroundColor': '#fef14b',
        'htmlLink': 'https://calendar.google.com.other.test/calendar/event',
        'location': 'Meet in Room 1 or https://us02web.zoom.us/j/42.',
        'description': 'Link: https://meet.google.com/abc-defg-hij',
        'conferenceData': {
          'entryPoints': [
            {'entryPointType': 'phone', 'uri': 'tel:+1'},
            {'entryPointType': 'video', 'uri': 'https://other.test/meeting'},
          ],
        },
        'attendees': [
          {'responseStatus': 'accepted'},
          {'self': true, 'responseStatus': 'declined'},
        ],
      })!;
      expect(event.declined, isTrue);
      expect(event.htmlLink, isNull);
      expect(event.meetingLink?.host, 'other.test');
      expect(calendarLocationLabel(event.location), 'Meet in Room 1 or Zoom.');
      expect(event.rawColor, const Color(0xfffef14b));
      expect(
        1.05 / (event.fill.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      const dark = Color(0xff38235a);
      expect(calendarReadableFill(dark), dark);
    },
  );

  testWidgets(
    'folds elapsed events, shows a running event and opens via keys',
    (tester) async {
      final state = GlobalKey<CalendarAgendaState>();
      final today = DateTime(2026, 11, 23);
      final now = today.add(const Duration(hours: 10, minutes: 30));
      final events = [
        _timed('Breakfast', today, 7, 8),
        _timed('Exercise', today, 8, 9),
        _timed(
          'Lecture',
          today,
          10,
          11,
          meeting: 'https://meet.google.com/xyz',
        ),
        _timed('Declined event', today, 11, 12, declined: true),
        _timed('Lunch', today, 12, 13),
      ];
      CalendarEvent? opened;
      CalendarEvent? joined;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: 372,
                height: 300,
                child: CalendarAgenda(
                  key: state,
                  selectedDay: DateTime.utc(2026, 11, 23),
                  now: now,
                  events: events,
                  rangeDays: 14,
                  foldFinished: true,
                  showDeclined: false,
                  onOpen: (event) => opened = event,
                  onJoin: (event) => joined = event,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 earlier events'), findsOneWidget);
      expect(find.text('Breakfast'), findsNothing);
      expect(find.text('Declined event'), findsNothing);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('10:00 – 11:00 · 30 min left'), findsOneWidget);
      await tester.tap(find.text('Join'));
      expect(joined?.title, 'Lecture');
      expect(opened, isNull);
      joined = null;
      state.currentState!.focusFirstEvent();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(joined?.title, 'Lecture');
      expect(opened?.title, 'Lecture');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened?.title, 'Lunch');
      await tester.tap(
        find.text('Lecture'),
        kind: .mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy title & time'), findsOneWidget);
      await tester.tap(find.text('Open in Google Calendar'));
      await tester.pumpAndSettle();
      expect(opened?.title, 'Lecture');

      await tester.tap(find.text('2 earlier events'));
      await tester.pumpAndSettle();
      Finder agendaText(String title) => find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == title,
      );
      expect(agendaText('Breakfast'), findsOneWidget);
      expect(agendaText('Exercise'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a forward wheel extends an agenda with a short initial range', (
    tester,
  ) async {
    final today = DateTime(2026, 11, 23);
    final upcoming = _timed(
      'Appointment',
      today.add(const Duration(days: 12)),
      10,
      11,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 372,
              height: 200,
              child: CalendarAgenda(
                selectedDay: DateTime.utc(2026, 11, 23),
                now: today,
                events: [upcoming],
                rangeDays: 7,
                foldFinished: true,
                showDeclined: false,
                onOpen: (_) {},
                onJoin: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No events'), findsOneWidget);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: .mouse,
        position: tester.getCenter(find.byType(CalendarAgenda)),
        scrollDelta: const Offset(0, 64),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Appointment'), findsOneWidget);
    expect(find.text('No events'), findsOneWidget);
  });

  testWidgets('pins the date badge and resets scrolling on day selection', (
    tester,
  ) async {
    final today = DateTime(2026, 11, 23);
    final events = [
      for (var hour = 9; hour < 15; hour++)
        _timed('Event $hour', today, hour, hour + 1),
      _timed('Tomorrow', DateTime(2026, 11, 24), 8, 9),
    ];
    var selected = DateTime.utc(2026, 11, 23);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 372,
              height: 180,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return CalendarAgenda(
                    selectedDay: selected,
                    now: today.add(const Duration(hours: 8)),
                    events: events,
                    rangeDays: 14,
                    foldFinished: false,
                    showDeclined: false,
                    onOpen: (_) {},
                    onJoin: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final badgeY = tester.getTopLeft(find.text('Mon')).dy;
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(86);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Mon')).dy, closeTo(badgeY, .01));
    expect(position.pixels, 86);

    update(() => selected = DateTime.utc(2026, 11, 24));
    await tester.pump();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      0,
    );
    expect(find.text('Tue'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, Object?> _eventJson(String title) => {
  'id': title,
  'calendarId': 'primary',
  'summary': title,
  'htmlLink': 'https://calendar.google.com/calendar/event?eid=id',
  'start': {'dateTime': '2026-11-23T10:00:00Z'},
  'end': {'dateTime': '2026-11-23T11:00:00Z'},
};

CalendarEvent _timed(
  String title,
  DateTime day,
  int startHour,
  int endHour, {
  String? meeting,
  bool declined = false,
}) => CalendarEvent.parse({
  ..._eventJson(title),
  'start': {
    'dateTime': day.add(Duration(hours: startHour)).toUtc().toIso8601String(),
  },
  'end': {
    'dateTime': day.add(Duration(hours: endHour)).toUtc().toIso8601String(),
  },
  'hangoutLink': meeting,
  if (declined)
    'attendees': [
      {'self': true, 'responseStatus': 'declined'},
    ],
})!;
