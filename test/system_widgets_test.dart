import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/battery/bar_battery.dart';
import 'package:remya_bar/features/media/bar_media.dart';
import 'package:remya_bar/features/media/media_preview.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_bar/features/system/system_popup_data.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: .linear(scale)),
    child: Material(child: child),
  ),
);

void main() {
  testWidgets('the media pill and card share the artwork palette', (
    tester,
  ) async {
    final preferences = RemyaTheme.fromConfig(
      const ThemeConfig(styleVariant: 'expressive', mode: 'dark'),
    );
    final fallback = preferences.theme(.dark);
    final cover = File('assets/icons/media-artwork.png').absolute;

    Widget host(String artUrl) {
      final players = [
        MediaPlayerSnapshot(
          busName: 'test',
          identity: 'Test player',
          title: 'Track',
          artist: '',
          album: '',
          artUrl: artUrl,
          playbackStatus: 'Playing',
          canControl: true,
          canGoNext: false,
          canGoPrevious: false,
          canPlay: true,
          canPause: true,
        ),
      ];
      return BarPopupScope(
        theme: preferences,
        child: MaterialApp(
          theme: fallback,
          home: Column(
            children: [
              SizedBox(
                width: 204,
                height: 40,
                child: BarMedia(players: players),
              ),
              Expanded(
                child: MediaPreview(
                  data: mediaPopupData(players),
                  onAction: (_) {},
                  styleVariant: preferences.styleVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Color? pillColor() =>
        tester.widget<Icon>(find.byIcon(Icons.music_note)).color;
    ColorScheme cardColors() =>
        Theme.of(tester.element(find.text('Now playing'))).colorScheme;

    await tester.pumpWidget(host(''));
    expect(pillColor(), fallback.colorScheme.primary);
    expect(cardColors(), fallback.colorScheme);

    await tester.runAsync(() async {
      await tester.pumpWidget(host(cover.uri.toString()));
      for (var attempt = 0; attempt < 50; attempt++) {
        if (pillColor() != fallback.colorScheme.primary &&
            cardColors() != fallback.colorScheme) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(pillColor(), isNot(fallback.colorScheme.primary));
    expect(pillColor(), cardColors().primary);

    await tester.pumpWidget(host(''));
    expect(pillColor(), fallback.colorScheme.primary);
    expect(cardColors(), fallback.colorScheme);
  });

  testWidgets('battery distinguishes charging, low power, unknown and absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BarBattery(
          battery: const BatterySnapshot(
            name: 'BAT0',
            percent: 100,
            state: 'Charging',
          ),
        ),
        scale: 2,
      ),
    );
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    final fullFillBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ClipPath),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(fullFillBox.color, const Color(0xFF0AC20A));
    final track = tester.getRect(find.byType(ClipRRect));
    expect(track.width, 48);
    expect(track.height, 24);
    expect(track.contains(tester.getCenter(find.text('100'))), isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _host(const BarBattery(level: 80, isPowerSaver: true, isCharging: false)),
    );
    final saverFillBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ClipPath),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(saverFillBox.color, const Color(0xFFF2E70D));
    final clipper = tester.widget<ClipPath>(find.byType(ClipPath)).clipper!;
    final fill = clipper.getClip(const Size(48, 24));
    expect(fill.contains(const Offset(1, 12)), isTrue);
    expect(fill.contains(const Offset(38, 12)), isTrue);
    expect(fill.contains(const Offset(39, 12)), isFalse);
    expect(fill.contains(const Offset(36, 1)), isFalse);
    expect(fill.contains(const Offset(34, 1)), isTrue);

    await tester.pumpWidget(
      _host(
        BarBattery(
          isPowerSaver: true,
          battery: const BatterySnapshot(
            name: 'BAT0',
            percent: 20,
            state: 'Charging',
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.bolt_rounded), findsNWidgets(2));
    expect(find.text('20'), findsNWidgets(2));
    final fillBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ClipPath),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(fillBox.color, const Color(0xFFC2230A));

    await tester.pumpWidget(
      _host(
        BarBattery(
          battery: const BatterySnapshot(
            name: 'BAT0',
            percent: 0,
            state: 'Not charging',
          ),
        ),
      ),
    );
    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    expect(find.byType(ClipPath), findsNothing);

    await tester.pumpWidget(_host(const BarBattery()));
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(
      _host(
        const BarBattery(
          battery: BatterySnapshot(name: 'BAT0', state: 'Unknown'),
        ),
      ),
    );
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
