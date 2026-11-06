import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/tray/tray_menu_popup.dart';

void main() {
  testWidgets('tray menu renders and routes actions to the owning tray', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: TrayMenuPopup(
              data: const {
                'token': 7,
                'parent': 0,
                'title': 'Test application',
                'artwork': <String, Object?>{},
                'canFold': true,
                'folded': false,
                'entries': [
                  {'id': 1, 'label': 'Open', 'enabled': true},
                  {'id': 2, 'label': 'Unavailable', 'enabled': false},
                  {
                    'id': 3,
                    'label': 'Options',
                    'enabled': true,
                    'submenu': true,
                  },
                  {'id': 4, 'separator': true},
                  {
                    'id': 5,
                    'label': 'Alerts',
                    'enabled': true,
                    'toggleType': 'checkmark',
                    'toggleState': 1,
                  },
                ],
              },
              onAction: (action) async => actions.add(action),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test application'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Open')),
      const Size(192, 36),
    );
    expect(
      tester.getTopLeft(find.text('Move to overflow')).dy,
      lessThan(tester.getTopLeft(find.text('Alerts')).dy),
    );
    await tester.tap(find.text('Unavailable'));
    expect(actions, isEmpty);
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.tap(find.text('Options'));
    await tester.pump();
    await tester.tap(find.text('Move to overflow'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(actions, [
      {'action': 'tray.menu', 'token': 7, 'entry': 1, 'label': 'Open'},
      {'action': 'tray.submenu', 'token': 7, 'entry': 3, 'label': 'Options'},
      {'action': 'tray.fold', 'token': 7},
      {'action': 'close', 'token': 7},
    ]);
  });
}
