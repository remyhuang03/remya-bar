import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/notifications/notification_tile.dart';
import 'package:remya_bar/features/notifications/notification_toasts.dart';

void main() {
  testWidgets('row stays compact when the dismiss segment appears', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    const row = ValueKey('row');
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 372,
            child: StatefulBuilder(
              builder: (context, setState) => NotificationTile(
                key: row,
                data: const {
                  'id': 1,
                  'appName': 'Mail',
                  'summary': 'One message',
                  'body': [
                    {'text': 'First line\nSecond line'},
                  ],
                },
                onAction: actions.add,
                expanded: expanded,
                onToggle: () => setState(() => expanded = !expanded),
              ),
            ),
          ),
        ),
      ),
    );
    final tile = find.byKey(row);
    final title = find.text('One message');
    final initialTitle = tester.getTopLeft(title);
    expect(tester.getSize(tile), const Size(372, 72));
    expect(tester.getSize(find.byTooltip('Expand')), const Size(32, 24));
    expect(find.byTooltip('Dismiss'), findsNothing);
    expect(find.text('First line Second line'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(tile));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title), initialTitle);
    expect(tester.getSize(find.byTooltip('Dismiss')), const Size(32, 24));

    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('First line\nSecond line'), findsOneWidget);
    expect(find.byTooltip('Collapse'), findsOneWidget);

    final dismiss = tester.getCenter(find.byTooltip('Dismiss'));
    await tester.tapAt(dismiss + const Offset(0, -20));
    await tester.tapAt(
      tester.getCenter(title),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    expect(actions, [
      {'action': 'notification.dismiss', 'id': 1},
      {'action': 'notification.dismiss', 'id': 1},
    ]);
    await mouse.removePointer();
  });

  testWidgets('row keyboard commands invoke the default, toggle and dismiss', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final actions = <Map<String, Object?>>[];
    var toggles = 0;
    var clearSection = 0;
    Widget row({required bool showFocus}) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 372,
          child: NotificationTile(
            data: const {
              'id': 2,
              'appName': 'Calendar',
              'summary': 'Event starting',
              'default': true,
            },
            onAction: actions.add,
            expanded: false,
            onToggle: () => toggles++,
            onDismissSection: () => clearSection++,
            focusNode: focus,
            showFocusIndicator: showFocus,
          ),
        ),
      ),
    );
    await tester.pumpWidget(row(showFocus: false));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(find.byTooltip('Dismiss'), findsNothing);
    await tester.pumpWidget(row(showFocus: true));
    expect(find.byTooltip('Dismiss'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(toggles, 1);
    expect(clearSection, 1);
    expect(actions, [
      {'action': 'notification.invoke', 'id': 2, 'key': 'default'},
      {'action': 'notification.dismiss', 'id': 2},
    ]);
  });

  testWidgets('expanded history shows the full summary and rich body', (
    tester,
  ) async {
    const summary =
        'A long notification summary that spans several lines in the center';
    final body = List.generate(12, (index) => 'Line ${index + 1}').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 280,
            child: NotificationTile(
              data: {
                'id': 3,
                'appName': 'Mail',
                'summary': summary,
                'body': [
                  {'text': body, 'bold': true},
                ],
              },
              onAction: (_) {},
              expanded: true,
              onToggle: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.text(summary)).height, greaterThan(20));
    expect(tester.getSize(find.text(body)).height, greaterThan(6 * 20));
    expect(tester.widget<Text>(find.text(summary)).maxLines, isNull);
    expect(tester.widget<Text>(find.text(body)).maxLines, isNull);
  });

  testWidgets('toasts announce new titles once at their urgency', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final announcements = <Map>[];
    messenger.setMockDecodedMessageHandler(SystemChannels.accessibility, (
      event,
    ) {
      if (event is Map && event['type'] == 'announce') {
        announcements.add(event['data'] as Map);
      }
      return Future<Object?>.value();
    });
    addTearDown(
      () => messenger.setMockDecodedMessageHandler(
        SystemChannels.accessibility,
        null,
      ),
    );

    Widget toasts(String summary) => MaterialApp(
      home: Center(
        child: MediaQuery(
          data: const MediaQueryData(supportsAnnounce: true),
          child: SizedBox(
            width: 404,
            child: NotificationToasts(
              data: {
                'notifications': [
                  {'id': 1, 'appName': 'Mail', 'summary': 'New mail'},
                  {
                    'id': 2,
                    'appName': 'Power',
                    'summary': summary,
                    'urgency': 2,
                  },
                ],
              },
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(toasts('Battery low'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(toasts('Battery low'));
    await tester.pumpWidget(toasts('Shutdown imminent'));
    expect(announcements.map((data) => data['message']), [
      'Mail, New mail',
      'Critical, Power, Battery low',
      'Critical, Power, Shutdown imminent',
    ]);
    expect(announcements.map((data) => data['assertiveness']), [null, 1, 1]);
  });
}
