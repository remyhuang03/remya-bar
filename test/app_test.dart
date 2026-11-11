import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/app.dart';
import 'package:remya_bar/features/battery/bar_battery.dart';
import 'package:remya_bar/features/clock/bar_clock.dart';
import 'package:remya_bar/features/hyprland/hyprland_backend.dart';
import 'package:remya_bar/features/media/bar_media.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/resources/bar_resources.dart';
import 'package:remya_bar/features/sidebar/right_sidebar.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_bar/features/window/bar_active_window.dart';
import 'package:remya_bar/features/workspaces/bar_workspaces.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

Future<void> _openSettings(WidgetTester tester) async {
  const codec = StandardMethodCodec();
  final reply = await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(
        BarPopup.channel.name,
        codec.encodeMethodCall(
          const MethodCall('action', {'action': 'settings'}),
        ),
        (_) {},
      );
  codec.decodeEnvelope(reply!);
}

void main() {
  testWidgets('card state validates payloads and ignores stale close actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      RemyaBarApp(
        preferences: SettingsThemeController(
          () => File('/nonexistent/theme.toml'),
        ),
      ),
    );
    addTearDown(() => BarPopup.openCard.value = null);
    Future<void> state(Map<String, Object?> data) async {
      const codec = StandardMethodCodec();
      final reply = await tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
            BarPopup.channel.name,
            codec.encodeMethodCall(
              MethodCall('action', {'action': 'card.state', ...data}),
            ),
            (_) {},
          );
      codec.decodeEnvelope(reply!);
      await tester.pump();
    }

    await state({'kind': 'media', 'open': true});
    expect(BarPopup.openCard.value, 'media');
    await state({'kind': 'battery', 'open': true});
    await state({'kind': 'media', 'open': false});
    expect(BarPopup.openCard.value, 'battery');
    await state({'kind': 'battery', 'open': false});
    expect(BarPopup.openCard.value, isNull);
    for (final data in [
      {'kind': 'tooltip', 'open': true},
      {'kind': 'media', 'open': 1},
      {'open': false},
    ]) {
      await expectLater(state(data), throwsA(isA<PlatformException>()));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'bar exposes Quick settings while its Settings action remains available',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 40);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = SettingsThemeController(
        () => File('/nonexistent/theme.toml'),
      );
      var opened = 0;
      await tester.pumpWidget(
        RemyaBarApp(
          preferences: preferences,
          onOpenSettings: () async {
            opened++;
          },
        ),
      );
      expect(find.byIcon(Icons.settings_rounded), findsNothing);
      expect(tester.getSize(find.byType(Scaffold)).height, 40);
      await _openSettings(tester);
      await tester.pump();
      expect(opened, 1);
      final context = tester.element(find.byType(Scaffold));
      expect(Theme.of(context).useMaterial3, isTrue);
      expect(
        Theme.of(context).colorScheme,
        preferences.theme.theme(.light).colorScheme,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clock follows real time and releases its timer', (tester) async {
    tester.view.physicalSize = const Size(600, 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RemyaBarApp(
        preferences: SettingsThemeController(
          () => File('/nonexistent/theme.toml'),
        ),
      ),
    );
    final clock = find.descendant(
      of: find.byType(BarClock),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
      ),
    );
    String time() => tester.widget<Text>(clock).textSpan!.toPlainText();
    final before = time();
    expect(before, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    expect(tester.getCenter(find.byType(BarClock)), const Offset(300, 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(time(), isNot(before));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings action propagates launch failures and can be retried', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = SettingsThemeController(
      () => File('/nonexistent/theme.toml'),
    );
    var attempts = 0;
    await tester.pumpWidget(
      RemyaBarApp(
        preferences: preferences,
        onOpenSettings: () async {
          if (attempts++ == 0) throw const ProcessException('settings', []);
        },
      ),
    );
    await expectLater(_openSettings(tester), throwsA(isA<PlatformException>()));
    await _openSettings(tester);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup widths do not overflow with a settings warning', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = SettingsThemeController(
      () => File('/nonexistent/theme.toml'),
    )..error = 'Invalid debug configuration';
    for (final width in [1.0, 39.0, 40.0, 59.0, 60.0, 1920.0]) {
      tester.view.physicalSize = Size(width, 40);
      await tester.pumpWidget(
        RemyaBarApp(preferences: preferences, onOpenSettings: () async {}),
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(
        find.byType(BarSidebarButton),
        width < 40 ? findsNothing : findsOneWidget,
      );
    }
  });

  testWidgets('missing data leaves no capsules or placeholder readings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RemyaBarApp(
        preferences: SettingsThemeController(
          () => File('/nonexistent/theme.toml'),
        ),
        onOpenSettings: () async {},
      ),
    );
    for (final type in [
      BarActiveWindow,
      BarResources,
      BarMedia,
      BarWorkspaces,
      BarBattery,
    ]) {
      expect(find.byType(type), findsNothing);
    }
    expect(find.byType(BarSidebarButton), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout adapts at breakpoints and with larger text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final preferences = SettingsThemeController(
      () => File('/nonexistent/theme.toml'),
    )..error = 'Invalid debug configuration';
    final system = SystemBackend()
      ..isPowerSaver = true
      ..resourceSnapshot = const SystemSnapshot(
        cpuPercent: 100,
        memoryUsedBytes: 32 * 1024 * 1024 * 1024,
        memoryTotalBytes: 32 * 1024 * 1024 * 1024,
        swapTotalBytes: 0,
        gpus: [GpuSnapshot(id: 'gpu', name: 'GPU', utilizationPercent: 100)],
        batteries: [
          BatterySnapshot(name: 'BAT0', percent: 100, state: 'Charging'),
        ],
      )
      ..players = const [
        MediaPlayerSnapshot(
          busName: 'org.mpris.MediaPlayer2.test',
          identity: 'Test player',
          title: 'Test track',
          artist: '',
          album: '',
          artUrl: '',
          playbackStatus: 'Paused',
          canControl: false,
          canGoNext: false,
          canGoPrevious: false,
          canPlay: false,
          canPause: false,
        ),
      ];
    final hyprland = HyprlandBackend(
      outputName: 'DP-1',
      readSnapshot: () async => const HyprlandSnapshot(
        monitors: [
          HyprlandMonitor(
            name: 'DP-1',
            outputNumber: 1,
            x: 0,
            y: 0,
            activeWorkspaceId: 1,
            workspaceSlots: [
              HyprlandWorkspaceSlot(
                id: 1,
                name: '1',
                active: true,
                occupied: false,
                urgent: false,
                apps: [],
                windowCount: 0,
              ),
            ],
          ),
        ],
        workspaces: [],
      ),
    );
    await hyprland.refresh();
    for (final scale in [1.0, 1.5, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final width in [
        200.0,
        599.0,
        600.0,
        799.0,
        800.0,
        999.0,
        1000.0,
        1199.0,
        1200.0,
        1440.0,
        1599.0,
        1600.0,
        1920.0,
        2304.0,
        3840.0,
      ]) {
        tester.view.physicalSize = Size(width, 40);
        await tester.pumpWidget(
          RemyaBarApp(
            preferences: preferences,
            system: system,
            hyprland: hyprland,
            onOpenSettings: () async {},
          ),
        );
        expect(tester.takeException(), isNull, reason: '$width at $scale');
        expect(find.byType(BarClock), findsOneWidget);
        if (scale == 1 && [1440.0, 1600.0, 2304.0].contains(width)) {
          // Media is hidden by default.
          expect(find.byType(BarMedia), findsNothing);
          expect(find.byType(BarResources), findsOneWidget);
          expect(
            tester.widget<BarBattery>(find.byType(BarBattery)).isPowerSaver,
            isTrue,
          );
        }
        if (width / scale >= 700) {
          // Default groups keep pills in order, without overlap, and end
          // with the quick settings toggle.
          Rect? previous;
          for (final type in [
            BarResources,
            BarWorkspaces,
            BarClock,
            BarBattery,
            BarSidebarButton,
          ]) {
            if (find.byType(type).evaluate().isEmpty) continue;
            final rect = tester.getRect(find.byType(type));
            if (previous != null) {
              expect(
                rect.left,
                greaterThanOrEqualTo(previous.right),
                reason: '$type at $width, $scale',
              );
            }
            previous = rect;
          }
          // Overlong content scrolls until the last pill is fully visible.
          if (previous!.right > width) {
            final position = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            // A vertical wheel over a non-scrolling pill scrolls the bar.
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: tester.getCenter(find.byType(BarResources)),
                scrollDelta: const Offset(0, 10000),
              ),
            );
            await tester.pump();
            expect(position.pixels, position.maxScrollExtent);
          }
          expect(
            tester.getRect(find.byType(BarSidebarButton)).right,
            lessThanOrEqualTo(width - 24),
          );
          expect(find.byType(BarWorkspaces), findsOneWidget);
        } else {
          expect(find.byType(BarWorkspaces), findsNothing);
          expect(tester.getCenter(find.byType(BarClock)).dx, width / 2);
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Settings layout orders, hides and configures pills', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final system = SystemBackend()
      ..resourceSnapshot = const SystemSnapshot(
        cpuPercent: 50,
        memoryUsedBytes: 1024,
        memoryTotalBytes: 2048,
        swapTotalBytes: 0,
        gpus: [],
        batteries: [BatterySnapshot(name: 'BAT0', percent: 80, state: '')],
      )
      ..layout = const BarLayout(
        groups: [
          ['sidebar', 'resources'],
          ['clock'],
        ],
        resources: ['cpu'],
      );
    await tester.pumpWidget(
      RemyaBarApp(
        preferences: SettingsThemeController(
          () => File('/nonexistent/theme.toml'),
        ),
        system: system,
        onOpenSettings: () async {},
      ),
    );
    expect(find.byType(BarBattery), findsNothing);
    final sidebar = tester.getRect(find.byType(BarSidebarButton));
    final resources = tester.getRect(find.byType(BarResources));
    expect(sidebar.left, 24);
    expect(resources.left, sidebar.right + 8);
    expect(tester.getRect(find.byType(BarClock)).right, 1920 - 24);
    expect(tester.getSize(find.byType(BarClock)).width, greaterThan(180));
    expect(find.text('50%'), findsOneWidget);
    expect(tester.widget<BarResources>(find.byType(BarResources)).metrics, [
      'cpu',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a centered group stays centered with its own sides', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var hasWindow = true;
    final hyprland = HyprlandBackend(
      outputName: 'DP-1',
      readSnapshot: () async => HyprlandSnapshot(
        monitors: [
          HyprlandMonitor(
            name: 'DP-1',
            outputNumber: 1,
            x: 0,
            y: 0,
            activeWorkspaceId: 1,
            currentWindow: hasWindow
                ? const HyprlandWindow(
                    address: '0x1',
                    title:
                        'A very long window title that must not widen the slot',
                    appId: 'kitty',
                    workspaceId: 1,
                    monitorName: 'DP-1',
                  )
                : null,
            workspaceSlots: [],
          ),
        ],
        workspaces: [],
      ),
    );
    await hyprland.refresh();
    final system = SystemBackend()
      ..layout = const BarLayout(
        groups: [
          ['window'],
          ['clock'],
          ['sidebar'],
        ],
        center: 1,
      );
    await tester.pumpWidget(
      RemyaBarApp(
        preferences: SettingsThemeController(
          () => File('/nonexistent/theme.toml'),
        ),
        system: system,
        hyprland: hyprland,
        onOpenSettings: () async {},
      ),
    );
    expect(tester.getCenter(find.byType(BarClock)).dx, 960);
    final window = tester.getRect(find.byType(BarActiveWindow));
    expect(window.left, 24);
    expect(window.width, BarActiveWindow.width);
    expect(tester.getRect(find.byType(BarSidebarButton)).right, 1920 - 24);
    hasWindow = false;
    await hyprland.refresh();
    await tester.pump();
    expect(find.byType(BarActiveWindow), findsNothing);
    expect(tester.getCenter(find.byType(BarClock)).dx, 960);
    hasWindow = true;
    await hyprland.refresh();
    await tester.pump();
    expect(find.byType(BarActiveWindow), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('atomic theme updates apply and malformed files retain the last valid theme', () async {
    final directory = Directory.systemTemp.createTempSync('remya-bar-theme-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/config.toml');
    final preferences = SettingsThemeController(() => file);
    addTearDown(preferences.dispose);
    await preferences.reload();
    expect(preferences.error, isNull);
    file.writeAsStringSync(
      'version = 1\n[theme]\nstyle_variant = "vibrant"\ntheme_mode = "dark"\n',
    );
    await preferences.reload();
    expect(preferences.theme.mode, ThemeMode.dark);
    expect(preferences.theme.styleVariant, DynamicSchemeVariant.vibrant);
    final previous = preferences.theme;
    file.writeAsStringSync('invalid');
    await preferences.reload();
    expect(preferences.theme, same(previous));
    expect(preferences.error, isNotNull);
    final replacement = File('${directory.path}/new.toml')
      ..writeAsStringSync('version = 1\n');
    replacement.renameSync(file.path);
    await preferences.reload();
    expect(preferences.theme.styleVariant, DynamicSchemeVariant.tonalSpot);
    expect(preferences.error, isNull);
  });
}
