import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/sidebar/right_sidebar.dart';

void main() {
  Future<void> showSidebar(
    WidgetTester tester,
    List<Map<String, Object?>> actions, {
    Map<String, Object?> overrides = const {},
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 663);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: RightSidebar(
          data: {
            'account': {'username': 'Tester'},
            'uptimeSeconds': 3600,
            'layout': ['internet', 'power', 'audio', 'caffeine'],
            'brightness': {'output': 'eDP-1', 'percent': 50},
            'network': {
              'available': true,
              'wifi_hardware_enabled': true,
              'writable': true,
              'wifi_enabled': true,
              'adapter': 'wlan0',
              'devices': [
                {
                  'interface': 'wlan0',
                  'networks': [
                    {'ssid': 'Nearby', 'signal': 90, 'security': 'open'},
                    {
                      'ssid': 'Home',
                      'signal': 60,
                      'in_use': true,
                      'known_uuid': 'wifi-id',
                      'security': 'wpa2',
                    },
                  ],
                },
              ],
            },
            ...overrides,
          },
          onAction: (action) async => actions.add(action),
          onHeight: (_) {},
        ),
      ),
    );
  }

  testWidgets('compact toggles send the inverse of live Settings state', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(
      tester,
      actions,
      overrides: {
        'layout': ['caffeine', 'dark', 'mic-mute'],
        'keep-awake': {'value': true},
        'theme': {
          'theme': {'theme_mode': 'light'},
        },
        'sound': {
          'system': {
            'default_input': 'mic',
            'devices': [
              {
                'name': 'mic',
                'direction': 'input',
                'preferences': {'muted': true},
              },
            ],
          },
        },
      },
    );
    for (final title in ['Keep awake', 'Dark mode', 'Mic mute']) {
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == title),
      );
      await tester.pumpAndSettle();
    }
    expect(actions, [
      {'action': 'sidebar.keep-awake', 'target': null, 'value': false},
      {'action': 'sidebar.dark', 'target': null, 'value': true},
      {'action': 'sidebar.input-muted', 'target': 'mic', 'value': false},
    ]);
  });

  testWidgets('Wi-Fi sorts connected first and dispatches disconnect', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    await tester.tap(find.text('Internet'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Home')).dy,
      lessThan(tester.getTopLeft(find.text('Nearby')).dy),
    );
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    expect(actions.map((action) => action['action']), [
      'sidebar.wifi-scan',
      'sidebar.wifi-disconnect',
    ]);
  });

  testWidgets('power actions expire and require a second click', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    await tester.tap(find.byTooltip('Power'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shut down'));
    await tester.pump();
    expect(find.text('Confirm?'), findsOneWidget);
    expect(actions, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Shut down'), findsOneWidget);
    await tester.tap(find.text('Shut down'));
    await tester.pump();
    await tester.tap(find.text('Confirm?'));
    expect(actions.single['value'], 'shutdown');
  });

  testWidgets('editing sends previous and new tile order on Escape', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    await tester.tap(find.byTooltip('Edit layout'));
    await tester.pumpAndSettle();
    final smallTile = find
        .ancestor(
          of: find.byIcon(Icons.coffee_rounded),
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getSize(smallTile), const Size(68, 52));
    await tester.tap(find.byTooltip('Hide Internet').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(actions.single, {
      'action': 'sidebar.layout',
      'target': ['internet', 'power', 'audio', 'caffeine'],
      'value': ['power', 'audio', 'caffeine'],
    });
  });

  testWidgets('tile state layers cover the whole tile', (tester) async {
    await showSidebar(tester, []);
    final title = find.text('Internet');
    final tile = find
        .ancestor(of: title, matching: find.byType(Material))
        .first;
    final colors = Theme.of(tester.element(title)).colorScheme;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(title));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Material>(tile).color,
      Color.alphaBlend(
        colors.onPrimaryContainer.withValues(alpha: .08),
        colors.primaryContainer,
      ),
    );
    await mouse.down(tester.getCenter(title));
    await tester.pump();
    expect(
      tester.widget<Material>(tile).color,
      Color.alphaBlend(
        colors.onPrimaryContainer.withValues(alpha: .16),
        colors.primaryContainer,
      ),
    );
    await mouse.cancel();
  });

  testWidgets('native slider reaches both edges while dragging', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    final slider = find.byType(Slider).first;
    final rect = tester.getRect(slider);
    final drag = await tester.startGesture(rect.center);
    await drag.moveTo(Offset(rect.right, rect.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 100);
    final theme = SliderTheme.of(tester.element(slider));
    expect(theme.thumbSize!.resolve({}), const Size(2, 52));
    expect(find.text('100%'), findsOneWidget);
    await drag.moveTo(Offset(rect.left, rect.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 0);
    expect(find.text('0%'), findsOneWidget);
    expect(actions, isEmpty);
    await drag.up();
    expect(actions.single['value'], 0);
  });

  testWidgets('Audio and Power detail headers have no switch', (tester) async {
    await showSidebar(tester, []);
    for (final page in ['Audio', 'Power']) {
      await tester.tap(find.text(page));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
  });
}
