import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/notifications/bar_notifications.dart';
import 'package:remya_bar/features/notifications/notification_backend.dart';
import 'package:remya_bar/features/notifications/notification_view.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/widgets/bar_hover_card.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

Map<String, Object?> _item(
  int id,
  String group, {
  int urgency = 1,
  List actions = const [],
  bool defaultAction = false,
  String href = '',
}) => {
  'id': id,
  'appName': group,
  'group': group,
  'urgency': urgency,
  'summary': 'Summary $id',
  'body': [
    {
      'text': 'Body $id',
      'bold': false,
      'italic': false,
      'underline': false,
      'href': href,
    },
  ],
  'actions': actions,
  'default': defaultAction,
  'received': DateTime.now().millisecondsSinceEpoch,
};

void main() {
  testWidgets('center groups by sender and routes actions', (tester) async {
    final actions = <Map<String, Object?>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: NotificationCenterCard(
              data: {
                'notifications': [
                  _item(
                    3,
                    'chat',
                    actions: [
                      ['reply', 'Reply'],
                    ],
                  ),
                  _item(2, 'mail', urgency: 2),
                  _item(1, 'chat', defaultAction: true),
                ],
                'dnd': false,
              },
              onAction: actions.add,
            ),
          ),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    // Later group members drop the repeated app header and close button.
    expect(find.byTooltip('Dismiss'), findsNWidgets(2));
    final chat = find.text('Summary 3');
    final follower = find.text('Summary 1');
    expect(
      tester.getTopLeft(follower).dy,
      greaterThan(tester.getTopLeft(chat).dy),
    );
    expect(
      tester.getTopLeft(follower).dy,
      lessThan(tester.getTopLeft(find.text('Summary 2')).dy),
    );

    await tester.tap(find.byTooltip('Dismiss').first);
    expect(actions.map((action) => action['id']), [3, 1]);
    actions.clear();

    await tester.tap(find.text('Reply'));
    await tester.tap(follower);
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Clear all'));
    expect(actions, [
      {'action': 'notification.invoke', 'id': 3, 'key': 'reply'},
      {'action': 'notification.invoke', 'id': 1, 'key': 'default'},
      {'action': 'notification.dnd', 'value': true},
      {'action': 'notification.clear'},
    ]);
  });

  testWidgets('center reports an unavailable service', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: NotificationCenterCard(
            data: const {
              'serviceError': 'Another notification service is running',
            },
            onAction: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.text('Another notification service is running'),
      findsOneWidget,
    );
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets(
    'panel pins Do not disturb at top, right-aligns Switch, and closes on Escape',
    (tester) async {
      final actions = <Map<String, Object?>>[];
      final heights = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 420,
              height: 400,
              child: NotificationCenterCard(
                data: {
                  'notifications': [
                    for (var i = 1; i <= 15; i++) _item(i, 'app-$i'),
                  ],
                  'dnd': false,
                },
                onAction: actions.add,
                onHeight: heights.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(heights, isNotEmpty);
      final dndTop = tester.getTopLeft(find.text('Do not disturb')).dy;
      final listTop = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
      expect(dndTop, lessThan(listTop));
      expect(
        tester.getTopRight(find.byType(Switch)).dx,
        closeTo(tester.getTopRight(find.text('Clear all')).dx, 16),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(actions, [
        {'action': 'close'},
      ]);
    },
  );

  testWidgets('bar button toggles notifications panel without hover card', (
    tester,
  ) async {
    BarPopup.openCard.value = null;
    final calls = <(Rect, double)>[];
    await tester.pumpWidget(
      BarPopupScope(
        theme: const RemyaTheme(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 40,
                child: BarNotifications(
                  backend: NotificationBackend(),
                  onToggle: (anchor, scale) async => calls.add((anchor, scale)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BarHoverCard), findsNothing);
    await tester.tap(find.byType(BarNotifications));
    expect(calls, hasLength(1));
    expect(calls.single.$1.width, greaterThan(0));
  });
}
