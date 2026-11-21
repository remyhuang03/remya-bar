import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/tray/tray_backend.dart';
import 'package:remya_bar/features/tray/tray_menu_popup.dart';
import 'package:remya_bar/src/rust/system_bridge/api.dart';
import 'package:remya_bar/widgets/bar_icon_cache.dart';

TrayItem _trayItem({
  String id = 'test',
  String title = 'Test',
  String iconName = 'test-icon',
  String iconThemePath = '',
  int argb = 1,
}) => TrayItem(
  id: id,
  appId: 'app',
  iconThemePath: iconThemePath,
  title: title,
  iconName: iconName,
  iconArgb: Uint8List.fromList([argb, 0, 0, 0]),
  iconWidth: 1,
  iconHeight: 1,
  itemIsMenu: false,
  hasMenu: false,
  attention: false,
);

void main() {
  testWidgets(
    'tray subscribers share one stream and re-lookup icons only on key or theme changes',
    (tester) async {
      var subscriptions = 0;
      var cancellations = 0;
      var iconReads = 0;
      var png = 2;
      late StreamController<List<TrayItem>> controller;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(barIconChannel, (call) async {
        expectSync(call.method, 'lookupTray');
        iconReads++;
        final requests = call.arguments as List<Object?>;
        return {
          for (final entry in requests.cast<List<Object?>>())
            trayIconKey(entry[0]! as String, entry[1]! as String):
                Uint8List.fromList([png]),
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(barIconChannel, null),
      );
      final backend = TrayBackend(
        watchItems: () {
          subscriptions++;
          controller = StreamController<List<TrayItem>>(
            onCancel: () => cancellations++,
          );
          return controller.stream;
        },
      );
      var firstUpdates = 0;
      var secondUpdates = 0;
      void first() => firstUpdates++;
      void second() => secondUpdates++;
      backend.addListener(first);
      backend.addListener(second);
      expect(subscriptions, 1);

      controller.add([_trayItem(argb: 1)]);
      await tester.pump();
      expect([iconReads, firstUpdates, secondUpdates], [1, 1, 1]);

      // Identical snapshot does not notify or re-lookup icons.
      controller.add([_trayItem(argb: 1)]);
      await tester.pump();
      expect([iconReads, firstUpdates, secondUpdates], [1, 1, 1]);

      // Changing title or ARGB bytes notifies without re-running icon lookup.
      controller.add([_trayItem(title: 'Updated', argb: 2)]);
      await tester.pump();
      expect([iconReads, firstUpdates, secondUpdates], [1, 2, 2]);
      expect(backend.items.single.title, 'Updated');

      // Changing icon name or theme path triggers a new icon lookup.
      controller.add([_trayItem(title: 'Updated', iconName: 'next-icon')]);
      await tester.pump();
      expect([iconReads, firstUpdates, secondUpdates], [2, 3, 3]);

      // Theme invalidation re-runs lookup and notifies when icon bytes change.
      png++;
      await messenger.handlePlatformMessage(
        barIconChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('themeChanged'),
        ),
        (_) {},
      );
      await tester.pump();
      expect([iconReads, firstUpdates, secondUpdates], [3, 4, 4]);
      expect(backend.iconFor(backend.items.single), Uint8List.fromList([png]));

      // Removing one listener keeps the shared stream active.
      backend.removeListener(first);
      controller.add([_trayItem(title: 'Final', iconName: 'next-icon')]);
      await tester.pump();
      expect([iconReads, firstUpdates, secondUpdates], [3, 4, 5]);

      // Removing the last listener cancels the subscription and clears state.
      backend.removeListener(second);
      await tester.pump();
      expect(cancellations, 1);
      expect(backend.items, isEmpty);

      // Re-attaching starts a fresh subscription.
      backend.addListener(first);
      expect(subscriptions, 2);
      backend.removeListener(first);
      await tester.pump();
      expect(cancellations, 2);
      backend.dispose();
    },
  );

  testWidgets('tray backend retries after stream closes while listened to', (
    tester,
  ) async {
    var subscriptions = 0;
    late StreamController<List<TrayItem>> controller;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(barIconChannel, (call) async => {});
    addTearDown(() => messenger.setMockMethodCallHandler(barIconChannel, null));

    final backend = TrayBackend(
      watchItems: () {
        subscriptions++;
        controller = StreamController<List<TrayItem>>();
        return controller.stream;
      },
    );
    var updates = 0;
    void listener() => updates++;
    backend.addListener(listener);
    expect(subscriptions, 1);

    await controller.close();
    await tester.pump();
    expect(subscriptions, 1);

    await tester.pump(const Duration(seconds: 1));
    expect(subscriptions, 2);
    controller.add([_trayItem(iconName: '')]);
    await tester.pump();
    expect(updates, 1);

    backend.removeListener(listener);
    await tester.pump();
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
