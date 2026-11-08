import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/notifications/notification_view.dart';

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
}
