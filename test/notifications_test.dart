import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/notifications/bar_notifications.dart';
import 'package:remya_bar/features/notifications/notification_backend.dart';
import 'package:remya_bar/features/notifications/notification_view.dart';
import 'package:remya_bar/features/notifications/notification_tile.dart';
import 'package:remya_bar/features/notifications/notification_toasts.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/widgets/bar_hover_card.dart';
import 'package:remya_ui/remya_ui.dart';

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
  testWidgets('center groups within urgency sections and restores expansion', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    final expansion = NotificationExpansion();
    Widget center() => MaterialApp(
      home: NotificationCenterCard(
        data: {
          'notifications': [
            _item(5, 'chat', urgency: 0),
            _item(
              4,
              'chat',
              actions: [
                ['reply', 'Reply'],
              ],
            ),
            _item(3, 'mail', urgency: 2),
            _item(2, 'chat', defaultAction: true),
            _item(1, 'browser'),
          ],
          'dnd': false,
        },
        expansion: expansion,
        onAction: actions.add,
      ),
    );
    await tester.pumpWidget(center());
    await tester.pumpAndSettle();

    expect(find.text('5 notifications'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.byType(NotificationTile), findsNWidgets(3));
    expect(
      tester.getTopLeft(find.text('Summary 3')).dy,
      lessThan(tester.getTopLeft(find.text('Summary 1')).dy),
    );

    // Expand the group, then the first child to expose its action.
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationTile), findsNWidgets(5));
    final row = find.ancestor(
      of: find.text('Summary 4'),
      matching: find.byType(NotificationTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Expand')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.tap(find.text('Summary 2'));
    await tester.ensureVisible(find.byTooltip('Clear section'));
    await tester.tap(find.byTooltip('Clear section'));
    await tester.tap(find.text('Do not disturb'));
    await tester.tap(find.text('Clear all'));

    expect(actions, [
      {'action': 'notification.invoke', 'id': 4, 'key': 'reply'},
      {'action': 'notification.invoke', 'id': 2, 'key': 'default'},
      {'action': 'notification.clear', 'urgency': 0},
      {'action': 'notification.dnd', 'value': true},
      {'action': 'notification.clear'},
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(center());
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
  });

  testWidgets('critical-only history disables clear until setting is enabled', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    Widget center(bool clearCritical) => MaterialApp(
      home: NotificationCenterCard(
        data: {
          'notifications': [_item(1, 'system', urgency: 2)],
          'clearCritical': clearCritical,
        },
        onAction: actions.add,
      ),
    );
    await tester.pumpWidget(center(false));
    expect(
      find.byTooltip('Critical notifications must be dismissed individually'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Clear all'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(center(true));
    await tester.tap(find.text('Clear all'));
    expect(actions, [
      {'action': 'notification.clear'},
    ]);
  });

  testWidgets('toast overflow opens history and exiting toasts are removed', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    Widget toasts(List<Map> notifications, int overflow) => MaterialApp(
      home: NotificationToasts(
        data: {'notifications': notifications, 'overflow': overflow},
        onAction: actions.add,
      ),
    );
    await tester.pumpWidget(toasts([_item(1, 'app')], 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+2 more · Open notifications'));
    expect(actions, [
      {'action': 'notification.open'},
    ]);
    await tester.pumpWidget(toasts([], 0));
    await tester.pumpAndSettle();
    expect(find.text('Summary 1'), findsNothing);
  });

  testWidgets(
    'clearing notification history sends the notification clear action',
    (tester) async {
      var notifications = [_item(1, 'mail')];
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) => NotificationCenterCard(
                data: {'notifications': notifications},
                onAction: (action) {
                  expect(action, {'action': 'notification.clear'});
                  setState(() => notifications = []);
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(find.text('Summary 1'), findsNothing);
    },
  );

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
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'panel pins header and footer, supports arrow navigation and Escape',
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
      final dnd = find.text('Do not disturb');
      final header = find.text('Notifications');
      final history = find.byType(SingleChildScrollView);
      final dndTop = tester.getTopLeft(dnd).dy;
      final headerTop = tester.getTopLeft(header).dy;
      expect(dndTop, greaterThan(tester.getBottomLeft(history).dy));
      expect(headerTop, lessThan(tester.getTopLeft(history).dy));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.drag(history, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(dnd).dy, dndTop);
      expect(tester.getTopLeft(header).dy, headerTop);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(actions, [
        {'action': 'notification.dismiss', 'id': 2},
        {'action': 'close'},
      ]);
    },
  );

  testWidgets(
    'automatic focus only reveals group controls after keyboard use',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCenterCard(
            data: {
              'notifications': [_item(2, 'chat'), _item(1, 'chat')],
            },
            onAction: (_) {},
            onHeight: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Dismiss'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Dismiss'), findsOneWidget);

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Dismiss'), findsNothing);
    },
  );

  testWidgets(
    'closing after a mouse click leaves the notification pill unfocused',
    (tester) async {
      final calls = <(Rect, double)>[];
      final backend = NotificationBackend();
      addTearDown(backend.dispose);
      Widget bar({required bool open}) => BarPopupScope(
        theme: const RemyaTheme(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 40,
                child: BarNotifications(
                  backend: backend,
                  open: open,
                  onToggle: (anchor, scale) async => calls.add((anchor, scale)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(bar(open: false));
      expect(find.byType(BarHoverCard), findsNothing);
      await tester.tap(find.byType(BarNotifications), kind: .mouse);
      expect(calls, hasLength(1));
      expect(calls.single.$1.width, greaterThan(0));

      await tester.pumpWidget(bar(open: true));
      await tester.pumpWidget(bar(open: false));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<BarNotifications>(),
        isNull,
      );
    },
  );
}
