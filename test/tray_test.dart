import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/tray/tray_backend.dart';
import 'package:remya_bar/features/tray/tray_menu_popup.dart';
import 'package:remya_bar/src/rust/system_bridge/api.dart';
import 'package:remya_bar/widgets/bar_icon_cache.dart';

void main() {
  testWidgets('tray subscribers share polling and only see changed data', (
    tester,
  ) async {
    var reads = 0;
    var iconReads = 0;
    var argb = 1;
    var png = 2;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(barIconChannel, (call) async {
      expectSync(call.method, 'lookupTray');
      expectSync(call.arguments, [
        ['test-icon', ''],
      ]);
      iconReads++;
      return {
        trayIconKey('test-icon', ''): Uint8List.fromList([png]),
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(barIconChannel, null));
    final backend = TrayBackend(
      readItems: () async {
        reads++;
        return [
          TrayItem(
            id: 'test',
            appId: 'app',
            iconThemePath: '',
            title: 'Test',
            iconName: 'test-icon',
            iconArgb: Uint8List.fromList([argb, 0, 0, 0]),
            iconWidth: 1,
            iconHeight: 1,
            itemIsMenu: false,
            hasMenu: false,
            attention: false,
          ),
        ];
      },
    );
    var firstUpdates = 0;
    var secondUpdates = 0;
    void first() => firstUpdates++;
    void second() => secondUpdates++;
    backend.addListener(first);
    backend.addListener(second);
    await tester.pump();
    expect([reads, iconReads, firstUpdates, secondUpdates], [1, 1, 1, 1]);

    const interval = Duration(seconds: 1);
    await tester.pump(interval);
    expect([reads, iconReads, firstUpdates, secondUpdates], [2, 2, 1, 1]);

    argb++;
    await tester.pump(interval);
    expect([reads, iconReads, firstUpdates, secondUpdates], [3, 3, 2, 2]);

    backend.removeListener(first);
    png++;
    await tester.pump(interval);
    expect([reads, iconReads, firstUpdates, secondUpdates], [4, 4, 2, 3]);

    backend.removeListener(second);
    await tester.pump(interval);
    expect([reads, iconReads], [4, 4]);
    expect(backend.items, isEmpty);
    backend.dispose();
  });

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
