import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/battery/bar_battery.dart';
import 'package:remya_bar/features/media/bar_media.dart';
import 'package:remya_bar/features/media/media_preview.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';
import 'package:remya_bar/widgets/bar_pill.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_bar/features/system/system_popup_data.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

Widget _host(Widget child, {double scale = 1}) => BarPopupScope(
  theme: RemyaTheme(),
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: .linear(scale)),
      child: Material(child: child),
    ),
  ),
);

Finder _batteryFill() => find.descendant(
  of: find.byType(ClipRRect),
  matching: find.byType(ClipPath),
);

void main() {
  for (final seek in [true, false]) {
    testWidgets(
      '${seek ? 'seek' : 'volume'} holds a commit until match or timeout',
      (tester) async {
        Widget host(double value) => _mediaSliders((_) {}, value: value);
        Finder slider() =>
            seek ? find.byType(Slider).first : find.byType(Slider).last;
        Slider control() => tester.widget<Slider>(slider());

        await tester.pumpWidget(host(0.2));
        control().onChanged!(0.7);
        control().onChangeEnd!(0.7);
        await tester.pump();
        expect(control().value, 0.7);
        await tester.pumpWidget(host(0.2));
        expect(control().value, 0.7);
        await tester.pumpWidget(host(0.704));
        expect(control().value, closeTo(0.704, 0.0001));
        await tester.pumpWidget(host(0.2));
        expect(control().value, 0.2);
        control().onChanged!(0.8);
        control().onChangeEnd!(0.8);
        await tester.pump(const Duration(milliseconds: 1499));
        expect(control().value, 0.8);
        await tester.pump(const Duration(milliseconds: 1));
        expect(control().value, 0.2);
      },
    );
  }

  testWidgets('only volume sends leading and latest trailing drag commits', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await tester.pumpWidget(_mediaSliders(actions.add));
    final volume = tester.widget<Slider>(find.byType(Slider).last);
    volume.onChanged!(0.3);
    volume.onChanged!(0.4);
    volume.onChanged!(0.5);
    expect(actions.map((action) => action['percent']), [30]);
    await tester.pump(const Duration(milliseconds: 59));
    expect(actions, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(actions.map((action) => action['percent']), [30, 50]);
    volume.onChanged!(0.6);
    await tester.pump(const Duration(milliseconds: 60));
    expect(actions.map((action) => action['percent']), [30, 50, 60]);
    volume.onChangeEnd!(0.7);
    await tester.pump(const Duration(milliseconds: 120));
    expect(actions.map((action) => action['percent']), [30, 50, 60, 70]);
    final seek = tester.widget<Slider>(find.byType(Slider).first);
    seek.onChanged!(0.4);
    await tester.pump(const Duration(milliseconds: 120));
    expect(actions, hasLength(4));
    seek.onChangeEnd!(0.4);
    expect(actions.last['action'], 'media.seek');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('the media pill and card share the artwork palette', (
    tester,
  ) async {
    final preferences = RemyaTheme.fromConfig(
      const ThemeConfig(styleVariant: 'expressive', mode: 'dark'),
    );
    final fallback = preferences.theme(.dark);
    final cover = File('assets/icons/media-artwork.png').absolute;

    Widget host(String artUrl, {Color? seed}) {
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
                  seedColor: seed,
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
        if (pillColor() != fallback.colorScheme.primary) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(pillColor(), isNot(fallback.colorScheme.primary));
    final seed = tester
        .widget<BarPill>(find.byType(BarPill).first)
        .card!
        .seedColor;
    expect(seed, isNotNull);
    await tester.pumpWidget(host(cover.uri.toString(), seed: seed));
    final expected = BarCardSurface.colors(
      fallback,
      seed,
      preferences.styleVariant,
    );
    expect(cardColors(), expected);
    BarPopup.openCard.value = 'media';
    await tester.pumpAndSettle();
    final pill = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(BarPill),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(
      (pill.decoration as BoxDecoration).color,
      cardColors().surfaceContainer,
    );
    BarPopup.openCard.value = null;

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
      find.descendant(of: _batteryFill(), matching: find.byType(ColoredBox)),
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
      find.descendant(of: _batteryFill(), matching: find.byType(ColoredBox)),
    );
    expect(saverFillBox.color, const Color(0xFFF2E70D));
    final clipper = tester.widget<ClipPath>(_batteryFill()).clipper!;
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
      find.descendant(of: _batteryFill(), matching: find.byType(ColoredBox)),
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
    expect(_batteryFill(), findsNothing);

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

Widget _mediaSliders(
  ValueChanged<Map<String, Object?>> onAction, {
  double value = 0.2,
}) => _host(
  MediaPreview(
    data: {
      'players': [
        {
          'name': 'test',
          'identity': 'Test player',
          'title': 'Track',
          'status': 'Paused',
          'positionSeconds': value * 100,
          'lengthSeconds': 100,
          'seekToken': ':1.2/track',
        },
      ],
      'output': {'name': 'speaker', 'percent': value * 100},
    },
    onAction: onAction,
  ),
);
