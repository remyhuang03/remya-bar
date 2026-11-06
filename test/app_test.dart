import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/settings/settings_button.dart';
import 'package:remya_bar/features/sidebar/right_sidebar.dart';
import 'package:remya_bar/app.dart';
import 'package:remya_bar/features/clock/bar_clock.dart';
import 'package:remya_bar/features/media/bar_media.dart';
import 'package:remya_bar/features/resources/bar_resources.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

void main() {
  final settingsButton = find.descendant(
    of: find.byType(SettingsButton),
    matching: find.byType(IconButton),
  );
  testWidgets('settings button fits the 40-pixel bar and opens settings', (
    tester,
  ) async {
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
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(Scaffold)).height, 40);
    await tester.tap(settingsButton);
    await tester.pump();
    expect(opened, 1);
    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).useMaterial3, isTrue);
    expect(
      Theme.of(context).colorScheme,
      preferences.theme.theme(.light).colorScheme,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clock is centered, follows real time and releases its timer', (
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
    expect(tester.getCenter(find.byType(BarClock)), const Offset(960, 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(time(), isNot(before));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch failure is visible and can be retried', (tester) async {
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
    await tester.tap(settingsButton);
    await tester.pump();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await tester.tap(settingsButton);
    await tester.pump();
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
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
      expect(settingsButton, width < 40 ? findsNothing : findsOneWidget);
      expect(
        find.byType(BarSidebarButton),
        width < 100 ? findsNothing : findsOneWidget,
      );
    }
  });

  testWidgets('media and resources fit their lane as output width changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 40);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final system = SystemBackend()
      ..resourceSnapshot = const SystemSnapshot(cpuPercent: 42, gpus: [])
      ..players = const [
        MediaPlayerSnapshot(
          busName: 'org.mpris.MediaPlayer2.test',
          identity: 'Test',
          title: 'A long media title',
          artist: '',
          album: '',
          artUrl: '',
          playbackStatus: 'Playing',
          canControl: false,
          canGoNext: false,
          canGoPrevious: false,
          canPlay: false,
          canPause: false,
        ),
      ];
    await tester.pumpWidget(
      RemyaBarApp(
        preferences: SettingsThemeController(
          () => File('/nonexistent/theme.toml'),
        ),
        system: system,
      ),
    );
    for (final width in [1200.0, 650.0, 280.0]) {
      tester.view.physicalSize = Size(width, 40);
      await tester.pump();
      final clock = tester.getRect(find.byType(BarClock));
      expect(clock.center.dx, width / 2);
      if (width >= 650) {
        final media = tester.getRect(find.byType(BarMedia));
        final resources = tester.getRect(find.byType(BarResources));
        expect(media.right, lessThanOrEqualTo(resources.left));
        expect(resources.right, lessThanOrEqualTo(clock.left));
        expect(
          media.width,
          width == 1200 ? BarMedia.width : lessThan(BarMedia.width),
        );
      } else {
        expect(find.byType(BarMedia), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
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
